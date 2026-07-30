# =============================================================================
# 03b_instrument_construction.R  (pipeline stage 3b — external-demand IV)
# -----------------------------------------------------------------------------
# Builds the shift-share INSTRUMENT for delta_EPW: rest-of-world (RoW) export
# demand, excluding Brazil on BOTH sides of every flow, pushed through the
# IDENTICAL crosswalk protocol as the treatment (producer primacy, composite
# aggregation, complete grid), so instrument and treatment live on the same
# v7 industry universe.
#
# INSTRUMENT VARIANTS (all saved; IV-B is the recommended primary):
#   IV-A  "pure world demand":
#         D_kt   = sum of world trade in HS6 product k, year t, excluding
#                  Brazil as exporter AND as importer
#         z_jt   = (D_jt - D_j,2010) / L_j,2010            (after ISIC mapping)
#   IV-B  "predicted exports" (Costa-Garred-Pessoa / export-demand form):
#         Xhat_kt = X^BR_k,2010 * (D_kt / D_k,2010)         (product level!)
#         z_jt    = (Xhat_jt - Xhat_j,2010) / L_j,2010
#         -> preserves Brazil's 2010 product mix; growth comes ONLY from RoW.
#            Note Xhat_k,2010 = X^BR_k,2010, so z_j,2010 = 0 by construction.
#   IV-C  (optional, CHINA_VARIANT flag): China's imports from world excl.
#         Brazil (Campello-Urdinez style), same construction as IV-A with
#         importer restricted to China.
#
# DATA SOURCE: BACI (CEPII), **HS07 vintage** — deliberately NOT HS12:
#   - BACI HS12 starts in 2012 and therefore cannot cover the 2010 base year;
#     HS07 covers 2010-2022 in ONE consistent classification (no splicing).
#   - HS2007 codes are bridged to the HS2012 dictionary ORPHANS-ONLY, exactly
#     mirroring [B2-2] in 03_epw_construction.R, via hs2007_hs2012.csv.
#   - Only ELECTION-YEAR files are needed (shocks are cumulative vs 2010),
#     so download 4 files, not 13.
#
# REQUIRED INPUTS (DATA_DIR unless noted):
#   baci/BACI_HS07_Y2010_V*.csv   \
#   baci/BACI_HS07_Y2014_V*.csv    |  download: https://www.cepii.fr/CEPII/en/
#   baci/BACI_HS07_Y2018_V*.csv    |  bdd_modele/bdd_modele_item.asp?id=37
#   baci/BACI_HS07_Y2022_V*.csv   /   (columns: t, i, j, k, v[, q])
#       t = year | i = exporter (numeric ISO, BRA = 76) | j = importer
#       k = HS6 code (HS2007, leading zeros may be stripped) | v = value,
#       THOUSANDS of current USD.
#   un_hs2012_isic4_weighted.csv     (same dictionary as 03)
#   hs2007_hs2012.csv                (same bridge as 03; REQUIRED here)
#   cpi_us.rds                       (cached by 03)
#   rais_isic_v7.rds                 (employment denominator L_j,2010)
#   exposure_shares_isic_v7.rds      (s_rj)
#   sectoral_shocks_isic_v7.rds      (bilateral universe + first-stage check)
#   epw_panel_isic_v7.rds            (region-level first-stage check)
#   OPTIONAL: manual_residual_assignments.csv  (same [F-2] hook as 03)
#   OPTIONAL: df_estimation_v7.rds   (full regional first-stage regression)
#
# OUTPUTS (DATA_DIR):
#   epw_iv_panel_v1.rds        micro x year: EPW_IV_A, EPW_IV_B [, EPW_IV_CHN]
#   sectoral_demand_iv_v1.rds  isic4 x year: z_A, z_B [, z_CHN] + components
#   output/03b_iv_run_log.txt  full log incl. first-stage diagnostics
#   output/iv_orphan_hs6_v1.csv  unmapped BACI value (audit)
#
# NOTE ON CODE DUPLICATION: 03 does not save its final NCM->ISIC match table
# or the composite map, so STEP 1 REPLAYS that construction from the same raw
# inputs and ASSERTS the resulting industry universe matches the saved v7
# outputs byte-for-byte. Recommended (later, in 03): saveRDS(ncm_isic_v6,
# "ncm_isic_match_v7.rds"); saveRDS(composite_map, "composite_map_v7.rds"),
# then replace STEP 1 with two readRDS calls.
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")

library(tidyverse)
library(data.table)   # fread: the BACI files are ~1 GB each

dir.create("output", showWarnings = FALSE)
log_con <- file(file.path("output", "03b_iv_run_log.txt"), open = "wt")
sink(log_con, split = TRUE)

# ---- CONTROL FLAGS ----------------------------------------------------------
CHINA_VARIANT  <- TRUE     # also build IV-C (China's imports, excl. Brazil)
BRA_ISO        <- 76L      # BACI numeric code for Brazil
CHN_ISO        <- 156L     # BACI numeric code for China
BACI_DIR       <- "baci"   # subfolder of DATA_DIR holding the 4 yearly CSVs
USD_UNIT       <- 1e4      # tens of thousands of constant-2010 USD (same as 03)

cat("=== 03b instrument construction:", format(Sys.time()), "===\n")
cat("Flags: CHINA_VARIANT =", CHINA_VARIANT, "\n\n")

# ---- helpers (copied verbatim from 03 — keep in sync until factored out) ----
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
SUPPORT_ISIC_REGEX <- "^(016|017|024|091|099)"

# =============================================================================
# STEP 1 — READ THE PERSISTED v7 MATCH TABLE + COMPOSITE MAP (saved by 03)
#   03 now writes ncm_isic_match_v7.rds and composite_map_v7.rds; this script
#   READS them instead of replaying the crosswalk, so instrument and treatment
#   cannot drift. If the files are absent (03 not yet re-run), fall back to the
#   in-line replay (identical logic to 03 steps 3a / 3a.3 / [F-2] / [E-1]).
# =============================================================================
if (file.exists("ncm_isic_match_v7.rds") && file.exists("composite_map_v7.rds")) {
  ncm_isic_v7   <- readRDS("ncm_isic_match_v7.rds")
  composite_map <- readRDS("composite_map_v7.rds")
  cat("STEP 1: read persisted ncm_isic_match_v7.rds + composite_map_v7.rds\n")
} else {
  cat("STEP 1: persisted match tables absent — replaying crosswalk (03 not re-run yet).\n")
  ncm_isic <- read_csv("un_hs2012_isic4_weighted.csv", col_types = cols(.default = "c")) |>
    mutate(w_ncm = as.numeric(w_share)) |>
    select(ncm6, isic4, w_ncm) |>
    mutate(ncm6 = str_pad(ncm6, 6, pad = "0"))

  ncm_isic_v7 <- ncm_isic |>
    mutate(tradable = is_tradable_isic(isic4),
           support  = str_detect(isic4, SUPPORT_ISIC_REGEX)) |>
    group_by(ncm6) |>
    mutate(has_producer = any(tradable & !support)) |>
    filter(if_else(has_producer, tradable & !support, tradable)) |>
    mutate(w_ncm = w_ncm / sum(w_ncm)) |>
    ungroup() |>
    select(ncm6, isic4, w_ncm)

  # [F-2] manual residual hook — mirror 03 so both sides see the same table
  if (file.exists("manual_residual_assignments.csv")) {
    man <- read_csv("manual_residual_assignments.csv", col_types = cols(.default = "c")) |>
      mutate(ncm6 = str_pad(ncm6, 6, pad = "0"), w_ncm = as.numeric(coalesce(w_ncm, "1")))
    ncm_isic_v7 <- bind_rows(ncm_isic_v7, man |> select(ncm6, isic4, w_ncm))
    cat("[F-2] manual residual assignments appended:", nrow(man), "rows\n")
  }

  # [E-1] composite map from export-side signatures (identical rule to 03)
  isic_signature <- ncm_isic_v7 |>
    arrange(ncm6) |>
    group_by(isic4) |>
    summarise(sig = paste(ncm6, round(w_ncm, 4), collapse = "|"), .groups = "drop")
  composite_map <- isic_signature |>
    group_by(sig) |>
    mutate(isic_composite = min(isic4), n_in_group = n()) |>
    ungroup() |>
    select(isic4, isic_composite, n_in_group)
}

stopifnot(all(abs(
  ncm_isic_v7 |> group_by(ncm6) |> summarise(s = sum(w_ncm)) |> pull(s) - 1) < 1e-9))

# ---- assert: replay reproduces the saved v7 universe ------------------------
shocks_v7 <- readRDS("sectoral_shocks_isic_v7.rds")
universe  <- sort(unique(shocks_v7$isic4))          # bilateral composite ISIC set

replay_universe <- composite_map |> distinct(isic_composite) |> pull() |> sort()
missing_from_replay <- setdiff(universe, replay_universe)
stopifnot(
  "replayed match table does not span the saved v7 industry universe — 03's
   crosswalk logic has drifted from the copy in this script; re-sync STEP 1" =
    length(missing_from_replay) == 0
)
cat("STEP 1 OK: replayed composite map spans all", length(universe),
    "bilateral v7 industries.\n\n")

# =============================================================================
# STEP 2 — READ BACI (election years only), COLLAPSE TO PRODUCT x YEAR
#   Three product-level series in ONE pass over each file:
#     D_row  : world trade excl. Brazil (i != 76 AND j != 76)   -> IV-A, IV-B
#     X_bra  : Brazil's exports (i == 76)                        -> IV-B shares
#     D_chn  : China's imports excl. Brazil (j == 156, i != 76)  -> IV-C
#   BACI 'v' is in THOUSANDS of current USD -> convert to USD here.
# =============================================================================
baci_file <- function(y) {
  hits <- list.files(BACI_DIR, pattern = paste0("^BACI_HS07_Y", y, "_V.*\\.csv$"),
                     full.names = TRUE)
  stopifnot(length(hits) >= 1)   # if 0: file missing — see header for download URL
  sort(hits)[length(hits)]       # newest release version if several
}

read_baci_year <- function(y) {
  f  <- baci_file(y)
  cat("Reading", f, "...\n")
  dt <- fread(f, select = c("t", "i", "j", "k", "v"),
              colClasses = list(character = "k"))
  dt[, `:=`(k = str_pad(str_trim(k), 6, pad = "0"), v_usd = as.numeric(v) * 1000)]
  out <- rbind(
    dt[i != BRA_ISO & j != BRA_ISO,
       .(series = "D_row", value = sum(v_usd)), by = .(year = t, hs6 = k)],
    dt[i == BRA_ISO,
       .(series = "X_bra", value = sum(v_usd)), by = .(year = t, hs6 = k)],
    if (CHINA_VARIANT)
      dt[j == CHN_ISO & i != BRA_ISO,
         .(series = "D_chn", value = sum(v_usd)), by = .(year = t, hs6 = k)]
  )
  rm(dt); gc()
  out
}

baci <- map_dfr(election_years, read_baci_year) |> as_tibble()

cat("\nBACI totals by series x year (T USD, current):\n")
baci |> group_by(series, year) |>
  summarise(total_T = round(sum(value) / 1e12, 2), .groups = "drop") |>
  pivot_wider(names_from = year, values_from = total_T) |> print()
# Sanity anchors: D_row world trade ~ 15-25 T; X_bra ~ 0.2-0.34 T (Brazil's
# exports; cross-check against exports_national_ncm.rds totals below).

# =============================================================================
# STEP 3 — HS2007 -> HS2012 BRIDGE, ORPHANS-ONLY (mirrors [B2-2] in 03)
#   Codes already present in the HS2012 dictionary pass through untouched;
#   only dictionary-orphans are bridged, with weights renormalized over
#   surviving targets. w_bridge splits VALUE across targets.
# =============================================================================
stopifnot("hs2007_hs2012.csv is REQUIRED for 03b (all BACI codes are HS2007)" =
            file.exists("hs2007_hs2012.csv"))
bridge <- read_csv("hs2007_hs2012.csv", col_types = cols(.default = "c"))
if (!"w_bridge" %in% names(bridge))
  bridge <- bridge |> group_by(hs6_from) |> mutate(w_bridge = 1 / n()) |> ungroup()
bridge <- bridge |>
  mutate(w_bridge = as.numeric(w_bridge)) |>
  transmute(hs6_from = str_pad(hs6_from, 6, pad = "0"),
            hs6_to   = str_pad(hs6_to,   6, pad = "0"), w_bridge) |>
  distinct()

dict_codes <- unique(ncm_isic_v7$ncm6)

in_dict  <- baci |> filter(hs6 %in% dict_codes)
orphans  <- baci |> filter(!hs6 %in% dict_codes)

bridged <- orphans |>
  inner_join(bridge, by = c("hs6" = "hs6_from"), relationship = "many-to-many") |>
  filter(hs6_to %in% dict_codes) |>
  group_by(series, hs6, year) |>
  mutate(w_bridge = w_bridge / sum(w_bridge)) |>
  ungroup() |>
  transmute(series, year, hs6 = hs6_to, value = value * w_bridge)

still_orphan <- orphans |>
  anti_join(bridge |> filter(hs6_to %in% dict_codes) |> distinct(hs6_from),
            by = c("hs6" = "hs6_from"))
write_csv(still_orphan |> group_by(series, hs6) |>
            summarise(value = sum(value), .groups = "drop") |>
            arrange(desc(value)),
          file.path("output", "iv_orphan_hs6_v1.csv"))

cat("\n--- HS2007->HS2012 BRIDGE (orphans-only) ---\n")
cat("Direct dictionary hits :", round(100 * sum(in_dict$value)  / sum(baci$value), 1), "% of value\n")
cat("Recovered via bridge   :", round(100 * sum(bridged$value)  / sum(baci$value), 1), "% of value\n")
cat("Residual orphan value  :", round(100 * sum(still_orphan$value) / sum(baci$value), 2),
    "% (audited in output/iv_orphan_hs6_v1.csv)\n")

baci_h12 <- bind_rows(in_dict, bridged) |>
  group_by(series, year, hs6) |>
  summarise(value = sum(value), .groups = "drop")

# =============================================================================
# STEP 4 — DEFLATE TO CONSTANT 2010 USD (same CPI cache + unit as 03)
# =============================================================================
stopifnot("cpi_us.rds missing — run 03 first (it caches the CPI)" =
            file.exists("cpi_us.rds"))
cpi      <- readRDS("cpi_us.rds")
cpi_2010 <- filter(cpi, year == 2010) |> pull(cpi)

baci_h12 <- baci_h12 |>
  left_join(cpi, by = "year") |>
  mutate(value_real = value * (cpi_2010 / cpi) / USD_UNIT) |>
  select(series, year, hs6, value_real)

# =============================================================================
# STEP 5 — PRODUCT-LEVEL INSTRUMENT SERIES (complete product grid, zeros)
#   The [B-1] lesson applies to the instrument too: a product absent from
#   BACI in year t is ZERO demand, not missing.
# =============================================================================
wide <- baci_h12 |>
  pivot_wider(names_from = series, values_from = value_real, values_fill = 0) |>
  complete(hs6 = unique(baci_h12$hs6), year = election_years,
           fill = list(D_row = 0, X_bra = 0,
                       D_chn = if (CHINA_VARIANT) 0 else NULL))

base_2010 <- wide |> filter(year == 2010) |>
  select(hs6, D_row_2010 = D_row, X_bra_2010 = X_bra,
         any_of(c(D_chn_2010 = "D_chn")))

wide <- wide |> left_join(base_2010, by = "hs6")

# IV-B predicted exports: Xhat_kt = X_bra_2010 * (D_row_t / D_row_2010).
# Products with zero RoW demand in 2010 have no defined growth factor ->
# excluded from IV-B (value at stake reported); they still enter IV-A.
n_undef <- wide |> filter(year == 2010, D_row_2010 == 0, X_bra_2010 > 0)
cat("\nIV-B: products with X_bra>0 but zero 2010 RoW demand (excluded from IV-B):",
    nrow(n_undef), "| BR-2010 value (B USD):",
    round(sum(n_undef$X_bra_2010) * USD_UNIT / 1e9, 3), "\n")

product_iv <- wide |>
  mutate(Xhat = if_else(D_row_2010 > 0, X_bra_2010 * (D_row / D_row_2010), NA_real_))

# Cross-check Brazil's exports in BACI vs Comex (levels won't match exactly:
# FOB vs CIF harmonization, BACI reconciliation — expect ratio ~0.9-1.1):
comex_2010 <- readRDS("exports_national_ncm.rds") |>
  filter(ano == 2010) |> summarise(v = sum(as.numeric(valor_fob_dolar))) |> pull(v)
baci_bra_2010 <- sum(base_2010$X_bra_2010) * USD_UNIT
cat("Cross-check 2010 Brazilian exports — BACI:",
    round(baci_bra_2010 / 1e9, 1), "B | Comex:", round(comex_2010 / 1e9, 1),
    "B | ratio:", round(baci_bra_2010 / comex_2010, 3), "\n")

# =============================================================================
# STEP 6 — MAP TO ISIC (same match table), COMPOSITE-AGGREGATE, RESTRICT
# =============================================================================
map_to_isic <- function(df, value_col) {
  df |>
    filter(!is.na(.data[[value_col]])) |>
    inner_join(ncm_isic_v7, by = c("hs6" = "ncm6"), relationship = "many-to-many") |>
    mutate(val = .data[[value_col]] * w_ncm) |>
    left_join(composite_map |> select(isic4, isic_composite), by = "isic4") |>
    mutate(isic4 = coalesce(isic_composite, isic4)) |>
    group_by(isic4, year) |>
    summarise(!!value_col := sum(val), .groups = "drop")
}

demand_isic <- map_to_isic(product_iv, "D_row") |>
  left_join(map_to_isic(product_iv, "Xhat"), by = c("isic4", "year"))
if (CHINA_VARIANT)
  demand_isic <- demand_isic |>
    left_join(map_to_isic(product_iv, "D_chn"), by = c("isic4", "year"))

# Restrict to the v7 bilateral universe and complete the grid with zeros:
demand_isic <- demand_isic |>
  filter(isic4 %in% universe) |>
  complete(isic4 = universe, year = election_years,
           fill = setNames(as.list(rep(0, 2 + CHINA_VARIANT)),
                           c("D_row", "Xhat", if (CHINA_VARIANT) "D_chn")))
stopifnot(nrow(demand_isic) == length(universe) * length(election_years),
          !anyNA(demand_isic))

# =============================================================================
# STEP 7 — INDUSTRY-LEVEL INSTRUMENT SHOCKS  z_jt = (D_jt - D_j,2010)/L_j,2010
# =============================================================================
L_j_2010 <- readRDS("rais_isic_v7.rds") |>
  group_by(isic4) |>
  summarise(L_j_2010 = sum(workers, na.rm = TRUE), .groups = "drop")

base_isic <- demand_isic |> filter(year == 2010) |>
  select(isic4, D_row_b = D_row, Xhat_b = Xhat,
         any_of(c(D_chn_b = "D_chn")))

z_panel <- demand_isic |>
  left_join(base_isic, by = "isic4") |>
  inner_join(L_j_2010,  by = "isic4") |>
  mutate(z_A = (D_row - D_row_b) / L_j_2010,
         z_B = (Xhat  - Xhat_b)  / L_j_2010,
         z_CHN = if (CHINA_VARIANT) (D_chn - D_chn_b) / L_j_2010 else NA_real_) |>
  filter(L_j_2010 > 0)

stopifnot(!anyNA(z_panel$z_A), !anyNA(z_panel$z_B),
          all(abs(z_panel$z_A[z_panel$year == 2010]) < 1e-12),
          all(abs(z_panel$z_B[z_panel$year == 2010]) < 1e-12))

# ---- industry-level first stage (the relevance condition, BHJ shock-level) --
cat("\n--- INDUSTRY-LEVEL FIRST STAGE:  g_jt ~ z, weighted by L_j ---\n")
fs_df <- shocks_v7 |>
  select(isic4, year, g_jt) |>
  inner_join(z_panel, by = c("isic4", "year")) |>
  filter(year != 2010)
library(fixest)
for (zv in c("z_A", "z_B", if (CHINA_VARIANT) "z_CHN")) {
  m <- feols(as.formula(paste("g_jt ~", zv, "| year")),
             data = fs_df, weights = ~ L_j_2010,
             cluster = ~ isic4)
  cat(sprintf("%-6s: beta = %+.4f | t = %5.2f | within-R2 = %.3f\n",
              zv, coef(m)[zv], tstat(m)[zv], fitstat(m, "wr2")$wr2))
}
cat("(Expect z_B strongly predictive — it embeds Brazil's product mix.\n",
    " If z_B t-stat < ~4 here, the regional first stage will be weak.)\n")

# =============================================================================
# STEP 8 — REGIONAL INSTRUMENT  EPW_IV_rt = sum_j s_rj * z_jt
# =============================================================================
shares <- readRDS("exposure_shares_isic_v7.rds")

epw_iv <- shares |>
  select(micro, isic4, s_rj,
         any_of(c("state", "mesoregion_code", "mesoregion_name"))) |>
  crossing(year = election_years) |>
  left_join(z_panel |> select(isic4, year, z_A, z_B, any_of("z_CHN")),
            by = c("isic4", "year")) |>
  mutate(across(any_of(c("z_A", "z_B", "z_CHN")), ~ replace_na(., 0))) |>
  group_by(micro, year,
           across(any_of(c("state", "mesoregion_code", "mesoregion_name")))) |>
  summarise(EPW_IV_A   = sum(s_rj * z_A),
            EPW_IV_B   = sum(s_rj * z_B),
            EPW_IV_CHN = if (CHINA_VARIANT) sum(s_rj * z_CHN) else NA_real_,
            .groups = "drop")

stopifnot(all(abs(epw_iv$EPW_IV_A[epw_iv$year == 2010]) < 1e-12),
          all(abs(epw_iv$EPW_IV_B[epw_iv$year == 2010]) < 1e-12))

# ---- regional first stage vs the actual treatment ---------------------------
epw_v7 <- readRDS("epw_panel_isic_v7.rds") |> mutate(micro = as.character(micro))
fs_reg <- epw_iv |> mutate(micro = as.character(micro)) |>
  inner_join(epw_v7 |> select(micro, year, EPW), by = c("micro", "year")) |>
  filter(year != 2010)

cat("\n--- REGIONAL FIRST-STAGE CORRELATIONS  cor(EPW, EPW_IV) by year ---\n")
fs_reg |> group_by(year) |>
  summarise(cor_A   = round(cor(EPW, EPW_IV_A), 3),
            cor_B   = round(cor(EPW, EPW_IV_B), 3),
            cor_CHN = if (CHINA_VARIANT) round(cor(EPW, EPW_IV_CHN), 3) else NA) |>
  print()

# Full regional first stage with the baseline controls, if the panel exists:
if (file.exists("df_estimation_v7.rds")) {
  dfe <- readRDS("df_estimation_v7.rds") |>
    mutate(micro = as.character(microregion_code)) |>
    filter(year != 2010) |>
    inner_join(fs_reg |> select(micro, year, EPW, EPW_IV_A, EPW_IV_B,
                                any_of("EPW_IV_CHN")),
               by = c("micro", "year"))
  cat("\n--- REGIONAL FIRST STAGE:  EPW ~ EPW_IV + controls | state^year ---\n")
  for (iv in c("EPW_IV_A", "EPW_IV_B", if (CHINA_VARIANT) "EPW_IV_CHN")) {
    m <- feols(as.formula(paste("EPW ~", iv, "+ ln_gdp_pc + ln_pop | state^year")),
               data = dfe, cluster = ~ mesoregion_code^year)
    cat(sprintf("%-10s: beta = %+.4f | t = %5.2f | (cluster) F ~ %.1f\n",
                iv, coef(m)[iv], tstat(m)[iv], tstat(m)[iv]^2))
  }
  cat("(Report Kleibergen-Paap F from the actual feols IV run in 07;\n",
      " the AKM0 confidence set is the weak-IV-robust complement.)\n")
}

# =============================================================================
# STEP 9 — SAVE
# =============================================================================
saveRDS(z_panel |> select(isic4, year, z_A, z_B, any_of("z_CHN"),
                          D_row, Xhat, any_of("D_chn"), L_j_2010),
        "sectoral_demand_iv_v1.rds")
saveRDS(epw_iv, "epw_iv_panel_v1.rds")
write_csv(epw_iv, "epw_iv_panel_v1.csv")

cat("\n--- PROVENANCE ---\n")
print(sessionInfo())
sink(); close(log_con)

# =============================================================================
# INTEGRATION INTO 07 (do NOT run here — paste/adapt in 07_regression_inference.R)
# -----------------------------------------------------------------------------
#  epw_iv <- readRDS("epw_iv_panel_v1.rds") |> mutate(micro = as.character(micro))
#  df_scaled <- df_scaled |>
#    left_join(epw_iv |> filter(year != 2010) |>
#                select(micro, year, EPW_IV_B), by = c("micro", "year")) |>
#    mutate(EPW_IV_B = replace_na(EPW_IV_B, 0),           # zero-tradable micros
#           EPW_IV_B = EPW_IV_B / sd(EPW_IV_B))           # scale only, no demean
#
#  ## 2SLS (fixest three-part formula):
#  iv_mod <- feols(delta_P_dalton ~ ln_gdp_pc + ln_pop + tradable_emp_share |
#                    state^year | delta_EPW ~ EPW_IV_B, data = df_scaled)
#  summary(iv_mod, stage = 1)                    # first stage + KP F
#  fitstat(iv_mod, ~ ivf + ivwald)               # weak-IV diagnostics
#
#  ## RI under the IV design: permute the INSTRUMENT's industry shocks
#  ## (z_B paths, jointly across years), rebuild EPW_IV*, re-run the 2SLS —
#  ## same make_epw_star() machinery with g_mat replaced by the z_B matrix.
#
#  ## AKM/AKM0 for IV: reg_ss(..., X = EPW_IV, ...) — ShiftShareSE supports
#  ## the IV case directly via the 'X' (instrument) vs 'Xname' distinction;
#  ## see package docs for ivreg_ss().
#
#  ## Asymmetric decomposition under IV: instrument boom/bust magnitudes of
#  ## delta_EPW with boom/bust magnitudes of EPW_IV_B (two endogenous vars,
#  ## two instruments) — discuss monotonicity in the text.
# =============================================================================
