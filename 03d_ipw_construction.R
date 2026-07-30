# =============================================================================
# 03d_ipw_construction.R  (pipeline stage 3d — IMPORT-competition treatment)
# -----------------------------------------------------------------------------
# WHY THIS SCRIPT EXISTS (read 03c first)
#   The export treatment has an effective number of shocks eff_n = 1/HHI(|alpha|)
#   ~ 2.4 — iron ore (0710) and oil/gas (0610) carry ~0.6 of the Rotemberg mass,
#   cluster SEs over-reject ~7x, and the baseline OLS null is UNINFORMATIVE (the
#   design lacks power). Import competition plausibly spreads identifying
#   variation across dozens of mid-sized manufacturing industries in many
#   regions, which should RAISE the effective shock count. The HEADLINE
#   diagnostic here is therefore the Rotemberg concentration of the IMPORT
#   treatment vs the export treatment — reported prominently even if the
#   coefficient is null (see output/ipw_rotemberg_comparison.csv).
#
# TREATMENT DEFINITION (mirrors the export construction exactly)
#   IPW_rt = sum_j s_rj * m_jt ,   m_jt = (IMP_jt - IMP_j,2010) / L_j,2010
#   s_rj  : COMMON shares (03a, exposure_shares_common_v8.rds) — sum to 1 over
#           the FULL tradable RAIS universe, so EPW and IPW are commensurable.
#   L_j,2010 : national 2010 employment in ISIC j (rais_isic_full_tradable_v8).
#
# VARIANTS
#   IPW_total                          — all imports (headline)
#   IPW_final / _interm / _capital     — UN-BEC-style end-use split (see [BEC])
#   IPW_china                          — Brazil's imports FROM CHINA only
#                                        (BACI-sourced here; the canonical Comex
#                                        id_pais version is scaffolded as
#                                        01_extraction.R BLOCK B2, BQ-gated)
#
# INSTRUMENT (ADH transposition)
#   z^IMP_jt = growth of OTHER middle-income countries' imports FROM CHINA in
#   industry j, per Brazilian worker, excluding Brazil throughout. Built from
#   the BACI HS07 files already downloaded for 03b, same 4 election years, same
#   orphans-only HS2007->HS2012 bridge, same crosswalk.
#
# INPUTS (DATA_DIR): imports_national_ncm.rds, ncm_isic_match_v7.rds,
#   composite_map_v7.rds, exposure_shares_common_v8.rds,
#   rais_isic_full_tradable_v8.rds, sectoral_shocks_isic_v7.rds,
#   epw_common_panel_v8.rds, df_estimation_v7.rds, cpi_us.rds,
#   hs2007_hs2012.csv, baci/BACI_HS07_Y{2010,2014,2018,2022}_V*.csv
#   OPTIONAL: hs2012_bec.csv (hs6,bec_enduse) — real BEC map, overrides [BEC]
#             manual_residual_assignments.csv ([F-2] hook, mirrors 03)
#
# OUTPUTS (DATA_DIR): ipw_panel_isic_v1.rds, sectoral_import_shocks_v1.rds,
#   ipw_iv_panel_v1.rds, output/03d_ipw_run_log.txt,
#   output/ipw_rotemberg_comparison.csv, output/03d_bec_split_audit.csv
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
source("/Users/solenoide/Documents/dissertação/data/códigos/_estimation_functions.R")

library(tidyverse)
library(data.table)
library(fixest)
set.seed(2026)

dir.create("output", showWarnings = FALSE)
log_con <- file(file.path("output", "03d_ipw_run_log.txt"), open = "wt")
sink(log_con, split = TRUE)
cat("=== 03d IPW construction:", format(Sys.time()), "===\n\n")

# ---- CONTROL FLAGS ----------------------------------------------------------
USD_UNIT   <- 1e4        # tens of thousands of constant-2010 USD (same as 03)
BRA_ISO    <- 76L
CHN_ISO    <- 156L
BACI_DIR   <- "baci"
# ADH comparison set (OTHER middle-income importers of Chinese goods), a FLAG:
CMP_SET <- c(Argentina = 32L, Chile = 152L, Colombia = 170L, Mexico = 484L,
             Peru = 604L, `South Africa` = 710L, Turkey = 792L,
             Indonesia = 360L, Malaysia = 458L, Thailand = 764L)
N_PLACEBO  <- 4999
SPECIAL_NCM_PREFIXES <- c("97", "98", "99")

cat("ADH comparison set:", paste(names(CMP_SET), collapse = ", "), "\n\n")

# ---- helpers (identical to 03/03b) ------------------------------------------
clean_code <- function(x, pad_width = NULL) {
  out <- as.character(x) |> str_trim() |> str_remove_all("[.\\-/ ]")
  if (!is.null(pad_width)) out <- str_pad(out, width = pad_width, side = "left", pad = "0")
  out
}
is_tradable_isic <- function(isic4) {
  code <- suppressWarnings(as.integer(isic4))
  !is.na(code) & ((code >=  100 & code <=  399) |
                  (code >=  500 & code <=  999) |
                  (code >= 1000 & code <= 3399))
}
is_special_ncm <- function(ncm8)
  str_detect(ncm8, paste0("^(", paste(SPECIAL_NCM_PREFIXES, collapse = "|"), ")"))

# =============================================================================
# STEP 1 — PERSISTED MATCH TABLE + COMPOSITE MAP + COMMON SHARES + L_j
# =============================================================================
stopifnot("run 03a first (materializes match/composite/common-shares)" =
            file.exists("ncm_isic_match_v7.rds") &&
            file.exists("composite_map_v7.rds") &&
            file.exists("exposure_shares_common_v8.rds") &&
            file.exists("rais_isic_full_tradable_v8.rds"))
ncm_isic_v7   <- readRDS("ncm_isic_match_v7.rds")
composite_map <- readRDS("composite_map_v7.rds")
shares_common <- readRDS("exposure_shares_common_v8.rds") |> mutate(micro = as.character(micro))
rais_full     <- readRDS("rais_isic_full_tradable_v8.rds")

L_j_2010 <- rais_full |> group_by(isic4) |>
  summarise(L_j_2010 = sum(workers, na.rm = TRUE), .groups = "drop")
rais_universe <- sort(unique(rais_full$isic4))          # 163 tradable composites
export_universe <- sort(unique(readRDS("sectoral_shocks_isic_v7.rds")$isic4))  # 152

cat("Full tradable RAIS universe (common denominator):", length(rais_universe), "\n")
cat("Export-bilateral universe (v7):", length(export_universe), "\n\n")

# =============================================================================
# STEP 2 — BRAZIL IMPORTS (Comex): special-regime drop, deflate, NCM8->NCM6
# =============================================================================
imports_raw <- readRDS("imports_national_ncm.rds") |>
  rename(year = ano, ncm8 = id_ncm, value = valor_fob_dolar) |>
  mutate(ncm8 = str_pad(as.character(ncm8), width = 8, pad = "0"))

imports_clean <- imports_raw |> filter(!is_special_ncm(ncm8))
cat("Special-regime import rows removed (ch. 97-99 only):",
    nrow(imports_raw) - nrow(imports_clean), "\n")

cpi      <- readRDS("cpi_us.rds")
cpi_2010 <- filter(cpi, year == 2010) |> pull(cpi)
imports_clean <- imports_clean |>
  left_join(cpi, by = "year") |>
  mutate(value_real = value * (cpi_2010 / cpi) / USD_UNIT)

imports_ncm6 <- imports_clean |>
  mutate(ncm6 = str_sub(ncm8, 1, 6)) |>
  group_by(ncm6, year) |>
  summarise(value_real = sum(value_real, na.rm = TRUE), .groups = "drop")

# =============================================================================
# [BEC] END-USE SPLIT — final (consumer) / intermediate / capital
#   The UN BEC correspondence is NOT shipped by the R 'concordance' package
#   (contrary to a note in the spec); if a real map hs2012_bec.csv (columns
#   hs6, bec_enduse in {final,intermediate,capital}) is present it is used.
#   Otherwise a TRANSPARENT, documented HS-chapter/heading classifier is applied
#   (the spec's stated fallback: "flag consumer-goods chapters and report the
#   split as heterogeneity"). Final goods are the ADH job-displacement channel;
#   intermediate/capital are the input-cost channel that can RAISE local
#   employment — pooling them attenuates both. Treat the split as heterogeneity.
# =============================================================================
end_use_of_hs6 <- function(hs6) {
  ch  <- str_sub(hs6, 1, 2)
  hd  <- str_sub(hs6, 1, 4)
  # heading-level overrides for large mixed chapters (consumer electronics,
  # passenger cars, consumer appliances kept as FINAL; trucks/machines CAPITAL)
  final_head   <- c("8703",                                  # passenger cars
                    "8517","8518","8519","8521","8527","8528","8471","8443", # consumer electronics
                    "8450","8418","8516","8508","8509","8414","8415")        # household appliances
  capital_head <- character(0)
  dplyr::case_when(
    hd %in% final_head ~ "final",
    # FINAL / consumer chapters: prepared food & bev, pharma, apparel, footwear,
    # printed matter, furniture, toys, misc manufactures, watches, instruments,
    # arms — goods that reach households essentially as-is.
    ch %in% c("16","17","18","19","20","21","22","30","33","42","43","46",
              "48","49","61","62","63","64","65","66","67","91","92","93",
              "94","95","96") ~ "final",
    # CAPITAL: machinery & equipment, transport equipment, optical/medical.
    ch %in% c("84","85","86","87","88","89","90") ~ "capital",
    # INTERMEDIATE: raw ag/animal, minerals, chemicals, plastics/rubber, wood/
    # paper pulp, textile yarn/fabric, stone/ceramic/glass, base metals & parts.
    TRUE ~ "intermediate"
  )
}
if (file.exists("hs2012_bec.csv")) {
  bec_map <- read_csv("hs2012_bec.csv", col_types = cols(.default = "c")) |>
    transmute(ncm6 = str_pad(hs6, 6, pad = "0"), end_use = tolower(bec_enduse))
  imports_ncm6 <- imports_ncm6 |> left_join(bec_map, by = "ncm6") |>
    mutate(end_use = coalesce(end_use, end_use_of_hs6(ncm6)))
  cat("[BEC] using supplied hs2012_bec.csv (fallback classifier fills gaps)\n")
} else {
  imports_ncm6 <- imports_ncm6 |> mutate(end_use = end_use_of_hs6(ncm6))
  cat("[BEC] using documented HS-chapter/heading end-use classifier (approx.)\n")
}

# =============================================================================
# STEP 3 — MAP NCM6->ISIC (persisted table), COMPOSITE-AGGREGATE  [E-1][F-3]
#   Value is split by w_ncm then collapsed to composite ISIC. Done separately
#   for the total and for each end-use bucket, so the buckets sum to the total.
# =============================================================================
map_imports_to_isic <- function(df) {
  val_before <- sum(df$value_real)
  out <- df |>
    inner_join(ncm_isic_v7, by = "ncm6", relationship = "many-to-many") |>
    mutate(val = value_real * w_ncm) |>
    left_join(composite_map |> select(isic4, isic_composite), by = "isic4") |>
    mutate(isic4 = coalesce(isic_composite, isic4)) |>
    group_by(isic4, year) |>
    summarise(imp = sum(val), .groups = "drop")
  # coverage (mappable value) reported by caller
  attr(out, "cov") <- sum(out$imp) / val_before
  out
}
imports_isic_total <- map_imports_to_isic(imports_ncm6)
cat(sprintf("Import value coverage after crosswalk (mappable/total): %.1f%%\n",
            100 * attr(imports_isic_total, "cov")))

bec_isic <- imports_ncm6 |> group_split(end_use) |>
  map(~ { z <- map_imports_to_isic(.x); z$end_use <- .x$end_use[1]; z }) |>
  bind_rows()

# import-bilateral universe: ISIC present in imports AND in the RAIS universe
imports_isic_set <- sort(unique(imports_isic_total$isic4[
  imports_isic_total$isic4 %in% rais_universe]))
overlap_exp <- length(intersect(imports_isic_set, export_universe))
cat(sprintf("\nImport-bilateral universe: %d ISIC | overlap with export-152: %d | import-only: %d\n",
            length(imports_isic_set), overlap_exp,
            length(setdiff(imports_isic_set, export_universe))))

# =============================================================================
# STEP 4 — SHOCKS m_jt ON A COMPLETE GRID (explicit zeros) [B-1], per L_j
#   Two scalings, BOTH carried:
#     m_lev  = (IMP_jt - IMP_j,2010) / L_j,2010           (per-worker levels)
#     m_arc  = (IMP_jt - IMP_j,2010) / (0.5*(IMP_jt+IMP_j,2010))   (DH arc, [-2,2],
#              unit-free, robust to zeros — removes the mechanical inflation of
#              capital-intensive extraction that per-worker scaling induces)
# =============================================================================
build_shocks <- function(isic_year_val, value_name = "imp",
                          universe = imports_isic_set) {
  full <- isic_year_val |>
    filter(isic4 %in% universe, year %in% election_years) |>
    rename(v = all_of(value_name)) |>
    complete(isic4 = universe, year = election_years, fill = list(v = 0))
  base <- full |> filter(year == 2010) |> select(isic4, v0 = v)
  full |>
    left_join(base, by = "isic4") |>
    left_join(L_j_2010, by = "isic4") |>
    filter(!is.na(L_j_2010), L_j_2010 > 0) |>
    mutate(delta = v - v0,
           m_lev = delta / L_j_2010,
           m_arc = if_else(abs(v) + abs(v0) > 0, delta / (0.5 * (v + v0)), 0))
}
imp_shocks <- build_shocks(imports_isic_total, "imp")
stopifnot(!anyNA(imp_shocks$m_lev),
          all(abs(imp_shocks$m_lev[imp_shocks$year == 2010]) < 1e-12))

# BEC-split shocks (per-worker levels; buckets share the same universe/L_j)
bec_shocks <- map(c("final", "intermediate", "capital"), function(eu) {
  build_shocks(filter(bec_isic, end_use == eu) |> select(isic4, year, imp), "imp") |>
    transmute(isic4, year, !!paste0("m_", eu) := m_lev)
}) |> reduce(full_join, by = c("isic4", "year")) |>
  mutate(across(starts_with("m_"), ~ replace_na(., 0)))

cat("\n--- IMPORT-SHOCK DIAGNOSTICS (per-worker levels) ---\n")
imp_shocks |> filter(year != 2010) |> group_by(year) |>
  summarise(min = min(m_lev), p5 = quantile(m_lev, .05), mean = mean(m_lev),
            max = max(m_lev), pct_pos = round(100 * mean(m_lev > 0), 1)) |>
  as.data.frame() |> print(digits = 4)

# =============================================================================
# STEP 5 — BACI: comparison-set imports from China (instrument) + Brazil-from-
#          China (IPW_china). ONE pass per file, filter exporter == China.
# =============================================================================
stopifnot("hs2007_hs2012.csv required (BACI codes are HS2007)" =
            file.exists("hs2007_hs2012.csv"))
baci_file <- function(y) {
  hits <- list.files(BACI_DIR, pattern = paste0("^BACI_HS07_Y", y, "_V.*\\.csv$"),
                     full.names = TRUE)
  stopifnot(length(hits) >= 1); sort(hits)[length(hits)]
}
read_baci_china <- function(y) {
  f <- baci_file(y); cat("Reading", f, "...\n")
  dt <- fread(f, select = c("t","i","j","k","v"), colClasses = list(character = "k"))
  dt <- dt[i == CHN_ISO]                                   # China as exporter
  dt[, `:=`(k = str_pad(str_trim(k), 6, pad = "0"), v_usd = as.numeric(v) * 1000)]
  out <- rbind(
    dt[j %in% CMP_SET & j != BRA_ISO,
       .(series = "M_cmp", value = sum(v_usd)), by = .(year = t, hs6 = k)],
    dt[j == BRA_ISO,
       .(series = "M_bra_chn", value = sum(v_usd)), by = .(year = t, hs6 = k)]
  )
  rm(dt); gc(); out
}
baci <- map_dfr(election_years, read_baci_china) |> as_tibble()
cat("\nBACI China-export series totals by year (B USD, current):\n")
baci |> group_by(series, year) |>
  summarise(total_B = round(sum(value) / 1e9, 1), .groups = "drop") |>
  pivot_wider(names_from = year, values_from = total_B) |> as.data.frame() |> print()

# HS2007->HS2012 bridge, orphans-only (mirrors 03b STEP 3)
bridge <- read_csv("hs2007_hs2012.csv", col_types = cols(.default = "c"))
if (!"w_bridge" %in% names(bridge))
  bridge <- bridge |> group_by(hs6_from) |> mutate(w_bridge = 1 / n()) |> ungroup()
bridge <- bridge |> mutate(w_bridge = as.numeric(w_bridge)) |>
  transmute(hs6_from = str_pad(hs6_from, 6, pad = "0"),
            hs6_to = str_pad(hs6_to, 6, pad = "0"), w_bridge) |> distinct()
dict_codes <- unique(ncm_isic_v7$ncm6)
in_dict <- baci |> filter(hs6 %in% dict_codes)
orphans <- baci |> filter(!hs6 %in% dict_codes)
bridged <- orphans |>
  inner_join(bridge, by = c("hs6" = "hs6_from"), relationship = "many-to-many") |>
  filter(hs6_to %in% dict_codes) |>
  group_by(series, hs6, year) |> mutate(w_bridge = w_bridge / sum(w_bridge)) |> ungroup() |>
  transmute(series, year, hs6 = hs6_to, value = value * w_bridge)
cat(sprintf("BACI dictionary hits: %.1f%% | bridged: %.1f%% | residual orphan: %.2f%%\n",
            100 * sum(in_dict$value) / sum(baci$value),
            100 * sum(bridged$value) / sum(baci$value),
            100 * (1 - (sum(in_dict$value) + sum(bridged$value)) / sum(baci$value))))
baci_h12 <- bind_rows(in_dict, bridged) |>
  group_by(series, year, hs6) |> summarise(value = sum(value), .groups = "drop") |>
  left_join(cpi, by = "year") |>
  mutate(value_real = value * (cpi_2010 / cpi) / USD_UNIT) |>
  select(series, year, hs6, value_real)

# map each series to ISIC (persisted table + composite map), complete grid
map_series_to_isic <- function(series_name) {
  baci_h12 |> filter(series == series_name) |>
    rename(ncm6 = hs6) |>
    inner_join(ncm_isic_v7, by = "ncm6", relationship = "many-to-many") |>
    mutate(val = value_real * w_ncm) |>
    left_join(composite_map |> select(isic4, isic_composite), by = "isic4") |>
    mutate(isic4 = coalesce(isic_composite, isic4)) |>
    group_by(isic4, year) |> summarise(imp = sum(val), .groups = "drop")
}
z_shocks   <- build_shocks(map_series_to_isic("M_cmp"),     "imp") |>
  transmute(isic4, year, z_imp = m_lev)
chn_shocks <- build_shocks(map_series_to_isic("M_bra_chn"), "imp") |>
  transmute(isic4, year, m_china = m_lev)

# =============================================================================
# STEP 6 — INDUSTRY-LEVEL FIRST STAGE  m_jt ~ z^IMP  (pooled AND by year)
#   03b's log showed a SIGN-FLIPPING first stage for the China EXPORT instrument
#   across years; check the same pathology here before trusting any pooled F.
# =============================================================================
fs_df <- imp_shocks |> select(isic4, year, m_lev) |>
  inner_join(z_shocks, by = c("isic4", "year")) |>
  inner_join(L_j_2010, by = "isic4") |>
  filter(year != 2010)
cat("\n--- INDUSTRY-LEVEL FIRST STAGE:  m_jt ~ z^IMP, weighted by L_j ---\n")
m_pool <- feols(m_lev ~ z_imp | year, data = fs_df, weights = ~ L_j_2010, cluster = ~ isic4)
cat(sprintf("POOLED : beta = %+.4f | t = %5.2f | within-R2 = %.3f\n",
            coef(m_pool)["z_imp"], tstat(m_pool)["z_imp"], fitstat(m_pool, "wr2")$wr2))
for (t in c(2014, 2018, 2022)) {
  d <- filter(fs_df, year == t)
  m <- feols(m_lev ~ z_imp, data = d, weights = ~ L_j_2010)
  cat(sprintf("  %d : beta = %+.4f | t = %5.2f | R2 = %.3f | n = %d\n",
              t, coef(m)["z_imp"], tstat(m)["z_imp"], fitstat(m, "r2")$r2, nobs(m)))
}

# =============================================================================
# STEP 7 — REGIONAL TREATMENTS  IPW_rt = sum_j s_rj * m_jt  (COMMON shares)
# =============================================================================
sc <- shares_common |> select(micro, isic4, s_rj,
                              any_of(c("state","mesoregion_code","mesoregion_name")))
all_shocks <- imp_shocks |> select(isic4, year, m_lev) |>
  full_join(bec_shocks, by = c("isic4", "year")) |>
  full_join(chn_shocks, by = c("isic4", "year")) |>
  full_join(z_shocks,   by = c("isic4", "year")) |>
  mutate(across(c(m_lev, m_final, m_intermediate, m_capital, m_china, z_imp),
                ~ replace_na(., 0)))

ipw_panel <- sc |>
  crossing(year = election_years) |>
  left_join(all_shocks, by = c("isic4", "year")) |>
  mutate(across(c(m_lev, m_final, m_intermediate, m_capital, m_china, z_imp),
                ~ replace_na(., 0))) |>
  group_by(micro, year, across(any_of(c("state","mesoregion_code","mesoregion_name")))) |>
  summarise(IPW_total   = sum(s_rj * m_lev),
            IPW_final   = sum(s_rj * m_final),
            IPW_interm  = sum(s_rj * m_intermediate),
            IPW_capital = sum(s_rj * m_capital),
            IPW_china   = sum(s_rj * m_china),
            IPW_IV      = sum(s_rj * z_imp),
            .groups = "drop")
stopifnot("IPW_total != 0 in 2010" =
            all(abs(filter(ipw_panel, year == 2010)$IPW_total) < 1e-12))

# =============================================================================
# STEP 8 — cor(EPW_common, IPW_total) BY YEAR
#   Strongly NEGATIVE => the export-only spec omitted a correlated regressor
#   (the exclusion-restriction argument from the assessment).
# =============================================================================
epw_common <- readRDS("epw_common_panel_v8.rds") |> mutate(micro = as.character(micro))
cor_ei <- ipw_panel |> mutate(micro = as.character(micro)) |>
  inner_join(epw_common |> select(micro, year, EPW_common), by = c("micro", "year")) |>
  filter(year != 2010) |>
  group_by(year) |>
  summarise(n = n(),
            cor_EPW_IPW = cor(EPW_common, IPW_total),
            cor_EPW_IPWfinal = cor(EPW_common, IPW_final),
            cor_EPW_IPWchina = cor(EPW_common, IPW_china), .groups = "drop")
cat("\n--- cor(EPW_common, IPW) BY YEAR ---\n"); print(as.data.frame(cor_ei), digits = 4)

# =============================================================================
# STEP 9 — ROTEMBERG / EFFECTIVE-# -SHOCKS  (the headline diagnostic)
#   Compute for BOTH treatments (export EPW, import IPW) under BOTH scalings
#   (per-worker levels vs DH-arc growth). Mining is capital-intensive, so
#   per-worker scaling mechanically inflates extraction-sector shocks; the arc
#   scaling shows how much eff_n RECOVERS once that is removed.
# =============================================================================
# The share matrix below is share_wide, built from shares_common (FULL tradable
# numerator), so the BHJ control must be measured over that same set -- reading
# the export-bilateral file here would be the numerator/control mismatch flagged
# in CODE_CHANGES_TODO.md 1b. ss_bhj_control() resolves this per SHARE_DENOM.
df_est <- readRDS("df_estimation_v7.rds") |> mutate(micro = as.character(microregion_code)) |>
  filter(year %in% c(2014, 2018, 2022)) |>
  select(-any_of("tradable_emp_share")) |>
  left_join(ss_bhj_control("common"), by = "micro") |>
  mutate(tradable_emp_share = replace_na(tradable_emp_share, 0))

# share matrix W_common aligned to the estimation micros x years (common shares)
share_wide <- shares_common |> select(micro, isic4, s_rj) |>
  pivot_wider(names_from = isic4, values_from = s_rj, values_fill = 0)

# residualize a treatment on controls + state, per year, and form Rotemberg alpha
rotemberg_eff_n <- function(shock_tbl, shock_col, universe, tag) {
  res <- map_dfr(c(2014, 2018, 2022), function(t) {
    dt <- filter(df_est, year == t)
    Wt <- dt |> select(micro) |> left_join(share_wide, by = "micro") |>
      select(-micro) |> mutate(across(everything(), ~ replace_na(., 0))) |> as.matrix()
    gt <- shock_tbl |> filter(year == t)
    gvec <- setNames(rep(0, ncol(Wt)), colnames(Wt))
    idx  <- match(colnames(Wt), gt$isic4)
    gvec[!is.na(idx)] <- gt[[shock_col]][idx[!is.na(idx)]]
    # treatment for this scaling = W %*% g
    trt <- as.numeric(Wt %*% gvec)
    dt2 <- dt |> mutate(trt = trt)
    x_perp <- resid(lm(trt ~ ln_gdp_pc + ln_pop + tradable_emp_share + factor(state),
                       data = dt2))
    stopifnot(length(x_perp) == nrow(Wt))
    num <- gvec * as.numeric(t(Wt) %*% x_perp)
    tibble(isic4 = names(gvec), year = t, alpha = num / sum(num))
  })
  effn <- res |> group_by(year) |>
    summarise(hhi = sum((abs(alpha) / sum(abs(alpha)))^2), eff_n = 1 / hhi,
              .groups = "drop") |> mutate(treatment = tag)
  list(alpha = res |> mutate(treatment = tag), eff_n = effn)
}

# export shocks (levels g_jt + DH arc) — same source the export EPW is built from
exp_shk <- readRDS("sectoral_shocks_isic_v7.rds") |>
  mutate(m_lev = g_jt,
         m_arc = if_else(abs(exp_national) + abs(exp_2010) > 0,
                         (exp_national - exp_2010) / (0.5 * (exp_national + exp_2010)), 0)) |>
  select(isic4, year, m_lev, m_arc)
imp_arc <- imp_shocks |> select(isic4, year, m_lev, m_arc)

rot <- list(
  rotemberg_eff_n(exp_shk, "m_lev", export_universe,    "EPW_export_level"),
  rotemberg_eff_n(exp_shk, "m_arc", export_universe,    "EPW_export_arc"),
  rotemberg_eff_n(imp_arc, "m_lev", imports_isic_set,   "IPW_import_level"),
  rotemberg_eff_n(imp_arc, "m_arc", imports_isic_set,   "IPW_import_arc")
)
eff_n_tbl <- map_dfr(rot, "eff_n") |>
  select(treatment, year, eff_n) |>
  pivot_wider(names_from = year, values_from = eff_n)
cat("\n===== EFFECTIVE NUMBER OF SHOCKS (1/HHI |alpha|) — HEADLINE =====\n")
print(as.data.frame(eff_n_tbl), digits = 3)
cat("(Export side reference from 03c: ~2.6/2.5/2.2 in 2014/18/22, mean ~2.4.)\n")
write_csv(map_dfr(rot, "eff_n") |> select(treatment, year, hhi, eff_n),
          file.path("output", "ipw_rotemberg_comparison.csv"))

# top-10 import industries by mean |alpha| (level scaling)
top_imp <- rot[[3]]$alpha |> group_by(isic4) |>
  summarise(abs_alpha = mean(abs(alpha)), .groups = "drop") |>
  slice_max(abs_alpha, n = 10)
cat("\nTop-10 IMPORT industries by mean |Rotemberg alpha| (per-worker levels):\n")
print(as.data.frame(top_imp), digits = 4)

# =============================================================================
# STEP 10 — AKM PLACEBO for the IMPORT treatment (reuse 03c routine)
#   Random iid shocks on the IMPORT-bilateral industries only; cluster-SE
#   rejection rate at 5% (nominal 0.05). Over-rejection => same few-effective-
#   shocks pathology; ~0.05 => imports spread the variation as hoped.
# =============================================================================
df_scaled <- df_est |>
  mutate(across(c(delta_P_dalton, delta_P_center, ln_gdp_pc, ln_pop, tradable_emp_share),
                ~ as.numeric(scale(.))))
Wc <- df_scaled |> select(micro) |> left_join(share_wide, by = "micro") |>
  select(-micro) |> mutate(across(everything(), ~ replace_na(., 0))) |> as.matrix()
imp_cols <- which(colnames(Wc) %in% imports_isic_set)
ctrl_mm <- model.matrix(~ factor(state):factor(year) + ln_gdp_pc + ln_pop +
                          tradable_emp_share, data = df_scaled)
qrC <- qr(ctrl_mm); R_ <- function(x) qr.resid(qrC, x)
cl <- interaction(df_scaled$mesoregion_code, df_scaled$year, drop = TRUE)
Gn <- nlevels(cl); Nn <- nrow(df_scaled); Kd <- ncol(ctrl_mm)
placebo_rate <- function(dv) {
  Yt <- R_(df_scaled[[dv]]); rej <- 0
  for (i in seq_len(N_PLACEBO)) {
    g <- rep(0, ncol(Wc)); g[imp_cols] <- rnorm(length(imp_cols))
    epw <- as.numeric(Wc %*% g); epw <- (epw - mean(epw)) / sd(epw); Xt <- R_(epw)
    sxx <- sum(Xt * Xt); b <- sum(Xt * Yt) / sxx; e <- Yt - Xt * b
    meat <- sum(tapply(Xt * e, cl, sum)^2)
    se_cl <- sqrt((Gn / (Gn - 1)) * ((Nn - 1) / (Nn - Kd)) * meat / sxx^2)
    if (abs(b / se_cl) > 1.96) rej <- rej + 1
  }
  rej / N_PLACEBO
}
placebo_imp <- tibble(outcome = c("delta_P_dalton", "delta_P_center"),
                      reject_rate_5pct = c(placebo_rate("delta_P_dalton"),
                                           placebo_rate("delta_P_center")))
cat(sprintf("\n--- AKM PLACEBO (import treatment, %d draws) ---\n", N_PLACEBO))
print(as.data.frame(placebo_imp), digits = 3)
cat("Export-side reference (03c): Dalton 0.357 | Center 0.334 (nominal 0.05).\n")

# =============================================================================
# STEP 11 — SAVE
# =============================================================================
saveRDS(all_shocks,  "sectoral_import_shocks_v1.rds")
saveRDS(ipw_panel,   "ipw_panel_isic_v1.rds")
saveRDS(ipw_panel |> select(micro, year, IPW_IV,
                            any_of(c("state","mesoregion_code","mesoregion_name"))),
        "ipw_iv_panel_v1.rds")
write_csv(ipw_panel, "ipw_panel_isic_v1.csv")
write_csv(imports_ncm6 |> count(end_use, wt = value_real, name = "value_real") |>
            mutate(pct = round(100 * value_real / sum(value_real), 1)),
          file.path("output", "03d_bec_split_audit.csv"))
saveRDS(list(eff_n = map_dfr(rot, "eff_n"), cor_epw_ipw = cor_ei,
             first_stage_pooled = coef(m_pool)["z_imp"], placebo = placebo_imp),
        "ipw_diagnostics_v1.rds")

cat("\n--- BEC end-use split (share of 2010-2022 import value) ---\n")
imports_ncm6 |> group_by(end_use) |>
  summarise(value = sum(value_real), .groups = "drop") |>
  mutate(pct = round(100 * value / sum(value), 1)) |> as.data.frame() |> print()

cat("\n--- PROVENANCE ---\n"); print(sessionInfo())
sink(); close(log_con)
