# =============================================================================
# 00_epw_calculo_v7.R
# EPW construction pipeline — v7 (canonical audited protocol).
#
# CHANGES vs v6:
#   [F-1]  Election-year filter BEFORE complete(): v6's grid silently expanded
#          to all 13 annual years present in Comex (complete() adds, never
#          removes), tripling the shock panel; caught by the Step-7 assert.
#   [E-1]  IDENTIFIED-COMPOSITE AGGREGATION: ISIC-4 classes fed by an identical
#          product-code signature (same NCMs, same weights) are not separately
#          identified by the data on either side of the shift-share (~39% of
#          2022 export value; e.g. 0610/0620 oil & gas). Each signature group
#          collapses to one composite industry BEFORE shares/shocks. Required
#          for inference validity: duplicated shocks violate AKM independence
#          and RI exchangeability.
#   [F-2]  Bounded manual-residual hook: optional, fully documented CSV of
#          hand assignments for residual orphans (Rettl-style last resort,
#          validated + logged; absent file = residual stays excluded).
#   [F-3]  Post-aggregation identity asserts (no duplicated export series
#          across all years; value/worker conservation through aggregation).
#
# (v6 changelog below retained for provenance.)
#
# CHANGES vs v4_singlehop (rationale in RATIONALE.md, section 1):
#   [B-1]  CRITICAL: industry x year shock panel is COMPLETED with explicit
#          zeros before differencing. v4 silently coded total export
#          collapses (and post-2010 entrants) as g_jt = 0 via replace_na(),
#          censoring the largest busts -- the margin the EPW- result lives on.
#   [B-2]  HS Chapters 95 (toys, sporting goods) and 96 (misc. manufactures)
#          RESTORED to the export universe: they are ordinary manufactured
#          tradables (ISIC Div. 32), wrongly excluded as "non-industry".
#          Chapters 97-99 (art/antiques, special regimes) remain excluded.
#   [B2-1] Orphan autopsy: unmatched NCM-6 value tabulated by year x chapter
#          to diagnose HS-vintage drift (Comex codes transactions in the
#          NCM vintage current at the time; the dictionary is HS2012).
#   [B2-2] HS-vintage bridge: orphan codes bridged to HS2012 (HS2007/2017/
#          2022 -> HS2012) before the ISIC map, when bridge tables present.
#   [B2-3] Producer-primacy rule + restrict-then-renormalize: support-
#          activity ISIC classes dropped from a match set whenever a genuine
#          goods-producing class remains; non-tradable matches dropped;
#          occurrence-share weights renormalized over survivors. v4
#          allocated value to non-producers (e.g. half of iron ore to 0990)
#          and silently destroyed value flowing to non-tradable matches.
#   [B-3]  US CPI cached to disk (no live network call inside the pipeline).
#   [B-4]  paths$un_uniform defined (the "uniform" branch errored in v4);
#          dead top-of-file read.csv removed.
#   [B-5]  Post-filter coverage diagnostic (v4 reported coverage BEFORE the
#          tradable filter, overstating it); v4-vs-v6 EPW comparison saved.
#   [B-6]  All outputs suffixed _v6; sessionInfo + flags logged.
#
# INPUTS (working dir):
#   exports_national_ncm.rds      : year | id_ncm (=ncm8) | valor_fob_dolar
#   rais_fte.rds / rais_2010_micro.rds
#   CNAE20_ISIC4.xls              : IBGE CONCLA CNAE 2.0 x ISIC rev.4
#   un_hs2012_isic4_weighted.csv  : UN HS6->ISIC4, occurrence-share weights
#   un_hs2012_isic4_tradable.csv  : UN HS6->ISIC4, unweighted (1/n option)
#   OPTIONAL (for [B2-2]):
#     hs2007_hs2012.csv, hs2017_hs2012.csv, hs2022_hs2012.csv
#       columns: hs6_from | hs6_to | w_bridge (weights within hs6_from;
#       if w_bridge absent, uniform split is applied)
#   OPTIONAL (for [B-5]): epw_panel_isic.rds  (the v4 panel, for comparison)
#
# OUTPUTS: epw_panel_isic_v6.rds, sectoral_shocks_isic_v6.rds,
#          exposure_shares_isic_v6.rds, exports_isic_v6.rds, rais_isic_v6.rds,
#          tradable_emp_share_2010_v6.rds, output/orphan_autopsy.csv,
#          output/orphan_ncm6_v6.csv, output/epw_v4_v6_comparison.csv,
#          output/00_v6_run_log.txt
# =============================================================================

source("C:/Users/Yago Ramalho/Documents/tema mestrado/data/códigos/_config.R")

library(tidyverse)
library(readxl)
library(janitor)

log_con <- file(file.path("output", "00_v7_run_log.txt"), open = "wt")
sink(log_con, split = TRUE)   # everything printed also lands in the log

# ---- CONTROL FLAGS ----------------------------------------------------------
WEIGHT_SCHEME <- "share"   # "share" (UN occurrence weights) | "uniform" (1/n)
RAIS_MEASURE  <- "fte"     # "fte" | "head"

paths <- list(
  exports     = "exports_national_ncm.rds",
  rais_fte    = "rais_fte.rds",
  rais_head   = "rais_2010_micro.rds",
  cnae_isic   = "CNAE20_ISIC4.xls",
  un_weighted = "un_hs2012_isic4_weighted.csv",
  un_uniform  = "un_hs2012_isic4_tradable.csv",          # [B-4]
  bridges     = c(hs2007 = "hs2007_hs2012.csv",           # [B2-2]
                  hs2017 = "hs2017_hs2012.csv",
                  hs2022 = "hs2022_hs2012.csv"),
  epw_v4      = "epw_panel_isic.rds",                     # [B-5], optional
  manual_residual = "manual_residual_assignments.csv"     # [F-2], optional
)

election_years <- c(2010, 2014, 2018, 2022)

# ---- helpers ----------------------------------------------------------------
clean_code <- function(x, pad_width = NULL) {
  out <- as.character(x) |> str_trim() |> str_remove_all("[.\\-/ ]")
  if (!is.null(pad_width)) out <- str_pad(out, width = pad_width, side = "left", pad = "0")
  out
}

# [B-2] Only genuinely non-attributable chapters are excluded:
#   97 = works of art / antiques; 98-99 = special regimes, returned goods,
#   confidential shipments. Chapters 95-96 (toys, sporting goods, misc.
#   manufactures) are RESTORED: they are tradable manufactures (ISIC Div. 32).
SPECIAL_NCM_PREFIXES <- c("97", "98", "99")
is_special_ncm <- function(ncm8) {
  str_detect(ncm8, paste0("^(", paste(SPECIAL_NCM_PREFIXES, collapse = "|"), ")"))
}

is_tradable_isic <- function(isic4) {
  code <- suppressWarnings(as.integer(isic4))
  !is.na(code) & ((code >=  100 & code <=  399) |   # Section A: Agriculture
                  (code >=  500 & code <=  999) |   # Section B: Mining
                  (code >= 1000 & code <= 3399))    # Section C: Manufacturing
}

# [B2-3] ISIC support-activity groups (services incidental to production).
# These classes do not PRODUCE traded goods; a physical export should never
# be attributed to them when a producing class is available in the match set.
#   016x = support to agriculture; 017x = hunting/trapping support (kept for
#   completeness); 024x = support to forestry; 0910/099x = support to mining.
SUPPORT_ISIC_REGEX <- "^(016|017|024|091|099)"

cat("=== 00_epw v7 run:", format(Sys.time()), "===\n")
cat("Flags: WEIGHT_SCHEME =", WEIGHT_SCHEME, "| RAIS_MEASURE =", RAIS_MEASURE, "\n\n")

# =============================================================================
# STEP 1 — LOAD & STANDARDISE
# =============================================================================
exports_raw <- readRDS(paths$exports)

if (RAIS_MEASURE == "fte") {
  rais_raw <- readRDS(paths$rais_fte) |>
    rename(micro = microregion_code, cnae5 = cnae_2, workers = total_fte)
} else {
  rais_raw <- readRDS(paths$rais_head) |>
    rename(micro = microregion_code, cnae5 = cnae_2, workers = total_vinculos)
}
cat("RAIS measure:", RAIS_MEASURE, "| total workers:",
    format(round(sum(rais_raw$workers)), big.mark = ","), "\n")

exports <- exports_raw |>
  rename(year = ano, ncm8 = id_ncm, value = valor_fob_dolar) |>
  mutate(ncm8 = str_pad(as.character(ncm8), width = 8, pad = "0"))

rais <- rais_raw |> mutate(cnae5 = clean_code(cnae5))

# =============================================================================
# STEP 2 — DROP SPECIAL REGIMES, THEN DEFLATE TO CONSTANT 2010 USD
# =============================================================================
exports_clean <- exports |> filter(!is_special_ncm(ncm8))
cat("Special-regime rows removed (ch. 97-99 only, v6):",
    nrow(exports) - nrow(exports_clean), "\n")

# [B-3] CPI cached: the pipeline must not depend on a live API.
if (!file.exists("cpi_us.rds")) {
  library(wbstats)
  saveRDS(
    wb_data("FP.CPI.TOTL", country = "US", start_date = 2009, end_date = 2023) |>
      select(year = date, cpi = FP.CPI.TOTL),
    "cpi_us.rds")
  cat("CPI fetched from World Bank and cached to cpi_us.rds\n")
} else cat("CPI read from local cache (cpi_us.rds)\n")
cpi      <- readRDS("cpi_us.rds")
cpi_2010 <- filter(cpi, year == 2010) |> pull(cpi)

# Deflation and unit scaling kept as SEPARATE, named operations.
USD_UNIT <- 1e4   # values expressed in tens of thousands of constant-2010 USD
exports_clean <- exports_clean |>
  left_join(cpi, by = "year") |>
  mutate(value_defl = value * (cpi_2010 / cpi),
         value_real = value_defl / USD_UNIT)

# Aggregate to NCM-6 (crosswalk-native resolution)
exports_ncm6 <- exports_clean |>
  mutate(ncm6 = str_sub(ncm8, 1, 6)) |>
  group_by(ncm6, year) |>
  summarise(value_real = sum(value_real, na.rm = TRUE), .groups = "drop")

# =============================================================================
# STEP 3a — UN EXPORT-SIDE MAP (single hop, weighted or uniform)
# =============================================================================
if (WEIGHT_SCHEME == "share") {
  ncm_isic <- read_csv(paths$un_weighted, col_types = cols(.default = "c")) |>
    mutate(w_ncm = as.numeric(w_share)) |>
    select(ncm6, isic4, w_ncm)
} else {
  ncm_isic <- read_csv(paths$un_uniform, col_types = cols(.default = "c")) |>
    group_by(ncm6) |> mutate(w_ncm = 1 / n()) |> ungroup() |>
    select(ncm6, isic4, w_ncm)
}
ncm_isic <- ncm_isic |> mutate(ncm6 = str_pad(ncm6, 6, pad = "0"))

cat("UN export map:", n_distinct(ncm_isic$ncm6), "NCM6 ->",
    n_distinct(ncm_isic$isic4), "ISIC4 (", WEIGHT_SCHEME, "weights )\n")

# =============================================================================
# STEP 3a.1 — [B2-1] ORPHAN AUTOPSY (diagnose before repairing)
# =============================================================================
orphans0 <- exports_ncm6 |> anti_join(ncm_isic, by = "ncm6")

autopsy <- orphans0 |>
  mutate(chapter = str_sub(ncm6, 1, 2)) |>
  group_by(year, chapter) |>
  summarise(value_B_USD = sum(value_real) * USD_UNIT / 1e9, n_codes = n_distinct(ncm6),
            .groups = "drop") |>
  arrange(desc(value_B_USD))
write_csv(autopsy, file.path("output", "orphan_autopsy.csv"))

cat("\n--- ORPHAN AUTOPSY (pre-bridge) ---\n")
cat("Orphan NCM-6 codes:", n_distinct(orphans0$ncm6),
    "| value (B USD):", round(sum(orphans0$value_real) * USD_UNIT / 1e9, 2), "\n")
orphans0 |> group_by(year) |>
  summarise(value_B_USD = round(sum(value_real) * USD_UNIT / 1e9, 2)) |> print(n = 20)
cat("If orphan value concentrates in 2010-11 and 2017-22, the cause is\n",
    "HS-vintage drift (codes created/split after HS2012), not unmappable goods.\n")

# =============================================================================
# STEP 3a.2 — [B2-2] HS-VINTAGE BRIDGE (orphans only; single hop preserved:
#             an HS->HS bridge is a revision within ONE classification,
#             not a cross-system concordance)
# =============================================================================
bridge_files <- paths$bridges[file.exists(paths$bridges)]

if (length(bridge_files) > 0) {
  bridge <- map_dfr(bridge_files, function(f) {
    b <- read_csv(f, col_types = cols(.default = "c"))
    if (!"w_bridge" %in% names(b))
      b <- b |> group_by(hs6_from) |> mutate(w_bridge = 1 / n()) |> ungroup()
    b |> mutate(w_bridge = as.numeric(w_bridge)) |>
      transmute(hs6_from = str_pad(hs6_from, 6, pad = "0"),
                hs6_to   = str_pad(hs6_to,   6, pad = "0"), w_bridge)
  }) |> distinct()

  # Keep only bridge targets that exist in the dictionary, then renormalize
  # bridge weights over those surviving targets:
  bridged <- orphans0 |>
    inner_join(bridge, by = c("ncm6" = "hs6_from"), relationship = "many-to-many") |>
    semi_join(ncm_isic, by = c("hs6_to" = "ncm6")) |>
    group_by(ncm6, year) |> mutate(w_bridge = w_bridge / sum(w_bridge)) |> ungroup() |>
    transmute(ncm6 = hs6_to, year, value_real = value_real * w_bridge)

  recovered_val <- sum(bridged$value_real) * USD_UNIT / 1e9
  cat("\n--- VINTAGE BRIDGE ---\n")
  cat("Orphan value recovered via HS bridge (B USD):", round(recovered_val, 2), "\n")

  # Fold recovered value back into the universe: drop the orphan-coded rows
  # that were successfully bridged, then append their re-coded counterparts.
  bridged_sources <- orphans0 |>
    inner_join(bridge, by = c("ncm6" = "hs6_from"), relationship = "many-to-many") |>
    semi_join(ncm_isic, by = c("hs6_to" = "ncm6")) |>
    distinct(ncm6)
  exports_ncm6 <- exports_ncm6 |>
    anti_join(bridged_sources, by = "ncm6") |>
    bind_rows(bridged) |>
    group_by(ncm6, year) |>
    summarise(value_real = sum(value_real), .groups = "drop")
} else {
  cat("\n--- VINTAGE BRIDGE ---\n",
      "No HS bridge tables found (", paste(names(paths$bridges), collapse = ", "),
      "). Skipping [B2-2]; residual orphans reported below.\n",
      ">>> ACTION: obtain UNSD HS2007/HS2017/HS2022 -> HS2012 tables (also\n",
      ">>> shipped with the R 'concordance' package) and re-run. <<<\n")
}

# Residual orphans after bridging
orphan_ncm6 <- exports_ncm6 |>
  anti_join(ncm_isic, by = "ncm6") |>
  group_by(ncm6) |>
  summarise(total_real = sum(value_real, na.rm = TRUE), .groups = "drop") |>
  arrange(desc(total_real))
write_csv(orphan_ncm6, file.path("output", "orphan_ncm6_v7.csv"))
cat("Residual orphan NCM-6 codes:", nrow(orphan_ncm6),
    "| value (B USD):", round(sum(orphan_ncm6$total_real) * USD_UNIT / 1e9, 2), "\n")

# =============================================================================
# STEP 3a.3 — [B2-3] PRODUCER PRIMACY + RESTRICT-THEN-RENORMALIZE
#   Rationale: occurrence counts measure dictionary granularity, not economic
#   weight. When a match set mixes a goods PRODUCER (e.g. ISIC 0710, iron-ore
#   mining) with a SUPPORT class (0990, services incidental to mining), the
#   exported good was produced by the producer; splitting value 50/50 dilutes
#   the true shock and manufactures a spurious one for the support class,
#   which propagates into EPW wherever support workers live. Additionally,
#   v4 let weights sum to one over ALL matches (incl. non-tradables) and
#   filtered AFTER allocation, destroying the value routed to non-tradable
#   classes. v6 restricts the match set FIRST and renormalizes over survivors.
# =============================================================================
ncm_isic_v6 <- ncm_isic |>
  mutate(tradable = is_tradable_isic(isic4),
         support  = str_detect(isic4, SUPPORT_ISIC_REGEX)) |>
  group_by(ncm6) |>
  mutate(has_producer = any(tradable & !support)) |>
  filter(if_else(has_producer, tradable & !support, tradable)) |>
  mutate(w_ncm = w_ncm / sum(w_ncm)) |>
  ungroup() |>
  select(ncm6, isic4, w_ncm)

stopifnot(all(abs(
  ncm_isic_v6 |> group_by(ncm6) |> summarise(s = sum(w_ncm)) |> pull(s) - 1
) < 1e-9))

# NCM codes whose ENTIRE match set was non-tradable drop out here; report them.
dropped_all_nontradable <- ncm_isic |> distinct(ncm6) |>
  anti_join(ncm_isic_v6 |> distinct(ncm6), by = "ncm6")
cat("\n--- PRODUCER PRIMACY / RENORMALIZATION ---\n")
cat("NCM-6 codes whose matches were all non-tradable (dropped):",
    nrow(dropped_all_nontradable), "\n")

mm_share <- exports_ncm6 |>
  filter(year == 2010) |>
  left_join(ncm_isic_v6 |> count(ncm6, name = "n_match"), by = "ncm6") |>
  summarise(pct_multi = 100 * sum(value_real[!is.na(n_match) & n_match > 1]) /
                              sum(value_real[!is.na(n_match)]))
cat("Share of mappable 2010 export value in many-to-many NCM codes (post-primacy):",
    round(mm_share$pct_multi, 1), "%\n")
cat("(If small, the weighting-scheme choice is second-order; report this in the appendix.)\n")

# Sanity anchor: iron ore must now map fully to 0710.
iron <- ncm_isic_v6 |> filter(ncm6 == "260111")
cat("NCM 260111 (iron ore) mapping:",
    paste(sprintf("%s (w=%.3f)", iron$isic4, iron$w_ncm), collapse = "; "), "\n")
stopifnot("iron ore not fully assigned to 0710" =
            nrow(iron) == 1 && iron$isic4 == "0710" && abs(iron$w_ncm - 1) < 1e-9)

# =============================================================================
# STEP 3a.4 — [F-2] BOUNDED MANUAL RESIDUAL ASSIGNMENTS (optional, documented)
#   Rettl-style manual assignment, admitted ONLY as a validated last resort for
#   residual orphans, with every assignment carried in a versioned CSV
#   (columns: ncm6, isic4, w_ncm [default 1], justification). Rules enforced:
#   target must be a tradable non-support producer; weights sum to 1 per ncm6;
#   source code must currently be an orphan. Absent file => residual orphans
#   remain excluded, which is the default and is itself documented.
# =============================================================================
if (file.exists(paths$manual_residual)) {
  man <- read_csv(paths$manual_residual, col_types = cols(.default = "c")) |>
    mutate(ncm6  = str_pad(ncm6, 6, pad = "0"),
           w_ncm = as.numeric(coalesce(w_ncm, "1")))
  stopifnot(
    "[F-2] manual file must have ncm6, isic4, justification" =
      all(c("ncm6", "isic4", "justification") %in% names(man)),
    "[F-2] manual targets must be tradable producers" =
      all(is_tradable_isic(man$isic4) & !str_detect(man$isic4, SUPPORT_ISIC_REGEX)),
    "[F-2] manual weights must sum to 1 per ncm6" =
      all(abs((man |> group_by(ncm6) |> summarise(s = sum(w_ncm)))$s - 1) < 1e-9),
    "[F-2] manual codes must be residual orphans" =
      all(man$ncm6 %in% orphan_ncm6$ncm6)
  )
  cat("\n--- [F-2] MANUAL RESIDUAL ASSIGNMENTS (", nrow(man), "rows ) ---\n")
  print(man |> select(ncm6, isic4, w_ncm, justification), n = 50)
  ncm_isic_v6 <- bind_rows(ncm_isic_v6, man |> select(ncm6, isic4, w_ncm))
} else {
  cat("\n[F-2] No manual residual file found; residual orphan value remains",
      "excluded (default, documented in the appendix).\n")
}

# =============================================================================
# STEP 3b — IBGE CNAE 2.0 -> ISIC4 (employment side, single hop)
#   Uniform 1/n splits are innocuous here: CNAE 2.0 nests within ISIC Rev.4
#   by construction, multi-matches are rare and carry negligible employment,
#   and no auxiliary magnitude exists to justify unequal weights.
# =============================================================================
cnae_isic_raw <- read_excel(paths$cnae_isic, skip = 1) |> clean_names()
cnae_isic <- cnae_isic_raw |>
  slice(-1) |>
  select(cnae_raw = 1, isic_raw = 3) |>
  filter(!is.na(cnae_raw), !is.na(isic_raw)) |>
  separate_rows(isic_raw, sep = ";") |>
  mutate(cnae4 = str_sub(clean_code(cnae_raw), 1, 4),
         isic4 = str_sub(clean_code(isic_raw), 1, 4)) |>
  filter(str_detect(cnae4, "^[0-9]{4}$"), str_detect(isic4, "^[0-9]{4}$")) |>
  select(cnae4, isic4) |>
  distinct()

# =============================================================================
# STEP 4 — MAP EXPORTS: NCM-6 -> ISIC-4 (single hop, v6 match table)
# =============================================================================
exports_isic <- exports_ncm6 |>
  inner_join(ncm_isic_v6, by = "ncm6", relationship = "many-to-many") |>
  mutate(value_isic = value_real * w_ncm) |>
  group_by(isic4, year) |>
  summarise(exp_national = sum(value_isic, na.rm = TRUE), .groups = "drop")
# NOTE: no post-hoc tradable filter is needed -- the v6 match table only
# contains tradable producing classes by construction.

# [B-5] Coverage AFTER restriction/renormalization, by year:
cov_by_year <- exports_ncm6 |> group_by(year) |>
  summarise(total = sum(value_real), .groups = "drop") |>
  left_join(exports_isic |> group_by(year) |>
              summarise(mapped = sum(exp_national), .groups = "drop"),
            by = "year") |>
  mutate(pct_cov = round(100 * mapped / total, 1))
cat("\n--- POST-FILTER EXPORT VALUE COVERAGE (v6, by year) ---\n")
print(cov_by_year)

# =============================================================================
# STEP 5 — MAP EMPLOYMENT: CNAE-5 -> CNAE-4 -> ISIC-4
# =============================================================================
rais_cnae4 <- rais |>
  mutate(cnae4 = str_sub(cnae5, 1, 4)) |>
  group_by(micro, cnae4,
           across(any_of(c("state", "mesoregion_code", "mesoregion_name")))) |>
  summarise(workers = sum(workers, na.rm = TRUE), .groups = "drop")

cnae_isic_w <- cnae_isic |>
  group_by(cnae4) |> mutate(w_cnae = 1 / n()) |> ungroup()

rais_isic <- rais_cnae4 |>
  inner_join(cnae_isic_w, by = "cnae4", relationship = "many-to-many") |>
  mutate(workers_isic = workers * w_cnae) |>
  group_by(micro, isic4,
           across(any_of(c("state", "mesoregion_code", "mesoregion_name")))) |>
  summarise(workers = sum(workers_isic, na.rm = TRUE), .groups = "drop") |>
  filter(is_tradable_isic(isic4))

# =============================================================================
# STEP 5b — [E-1] IDENTIFIED-COMPOSITE AGGREGATION
#   ISIC-4 classes fed by an identical (ncm6, weight) signature are one
#   industry as far as the data can tell; keeping them separate injects
#   perfectly duplicated shocks into the design (breaking AKM independence
#   and RI exchangeability) and smears exposure across phantom units.
#   Merge rule: export-side signature (the treatment's source); the
#   employment-side agreement rate is reported as validation.
# =============================================================================
isic_signature <- ncm_isic_v6 |>
  arrange(ncm6) |>
  group_by(isic4) |>
  summarise(sig = paste(ncm6, round(w_ncm, 4), collapse = "|"), .groups = "drop")

composite_map <- isic_signature |>
  group_by(sig) |>
  mutate(isic_composite = min(isic4),           # deterministic representative
         n_in_group     = n()) |>
  ungroup() |>
  select(isic4, isic_composite, n_in_group)

cnae_signature <- cnae_isic_w |>
  arrange(cnae4) |>
  group_by(isic4) |>
  summarise(csig = paste(cnae4, round(w_cnae, 4), collapse = "|"), .groups = "drop")

agree <- composite_map |> filter(n_in_group > 1) |>
  left_join(cnae_signature, by = "isic4") |>
  group_by(isic_composite) |>
  summarise(emp_side_identical = n_distinct(csig) == 1, .groups = "drop")

cat("\n--- [E-1] COMPOSITE AGGREGATION ---\n")
cat("Composite groups (collapsing >1 ISIC code):",
    composite_map |> filter(n_in_group > 1) |> distinct(isic_composite) |> nrow(), "\n")
cat("ISIC codes absorbed:", sum(composite_map$n_in_group > 1), "\n")
cat("Groups also identical on the employment side:",
    sum(agree$emp_side_identical), "of", nrow(agree),
    "(disagreements listed below for manual review)\n")
if (any(!agree$emp_side_identical))
  print(agree |> filter(!emp_side_identical))

comp_table <- composite_map |> filter(n_in_group > 1) |>
  arrange(isic_composite, isic4)
write_csv(comp_table, file.path("output", "composite_groups_v7.csv"))

# value share collapsed, per year (the ~39% figure for the appendix):
exports_isic |>
  left_join(composite_map, by = "isic4") |>
  group_by(year) |>
  summarise(pct_value_in_composites =
              round(100 * sum(exp_national[coalesce(n_in_group, 1L) > 1]) /
                          sum(exp_national), 1), .groups = "drop") |>
  print()

val_before  <- sum(exports_isic$exp_national)
work_before <- sum(rais_isic$workers)

exports_isic <- exports_isic |>
  left_join(composite_map |> select(isic4, isic_composite), by = "isic4") |>
  mutate(isic_composite = coalesce(isic_composite, isic4)) |>
  group_by(isic4 = isic_composite, year) |>
  summarise(exp_national = sum(exp_national), .groups = "drop")

rais_isic <- rais_isic |>
  left_join(composite_map |> select(isic4, isic_composite), by = "isic4") |>
  mutate(isic_composite = coalesce(isic_composite, isic4)) |>
  group_by(micro, isic4 = isic_composite,
           across(any_of(c("state", "mesoregion_code", "mesoregion_name")))) |>
  summarise(workers = sum(workers), .groups = "drop")

# [F-3] conservation + identification asserts:
stopifnot(
  "[F-3] export value not conserved through aggregation" =
    abs(sum(exports_isic$exp_national) - val_before) < 1e-6 * max(val_before, 1),
  "[F-3] employment not conserved through aggregation" =
    abs(sum(rais_isic$workers) - work_before) < 1e-6 * max(work_before, 1)
)
fp <- exports_isic |> arrange(year) |>
  group_by(isic4) |>
  summarise(fingerprint = paste(round(exp_national, 6), collapse = "|"),
            .groups = "drop")
dup_fp <- fp |> count(fingerprint) |> filter(n > 1)
stopifnot("[F-3] duplicated export series survive aggregation" = nrow(dup_fp) == 0)
cat("[F-3] PASS: no two industries share an identical export series across years.\n")

# =============================================================================
# STEP 6 — BILATERAL UNIVERSE (industries present in BOTH sides)
# =============================================================================
isic_bilateral <- intersect(unique(exports_isic$isic4), unique(rais_isic$isic4))
cat("\nBilateral tradable ISIC-4 industries (v6):", length(isic_bilateral),
    "(v4 was 176; Rettl benchmark: 174 -- expect movement: ch. 95-96 in,\n",
    " support classes out; the NEW count supersedes the dissertation text)\n")

exports_isic <- filter(exports_isic, isic4 %in% isic_bilateral)
rais_isic    <- filter(rais_isic,    isic4 %in% isic_bilateral)

# =============================================================================
# STEP 7 — [B-1] SECTORAL SHOCKS ON A COMPLETE GRID
#   g_jt = (EXP_jt - EXP_j,2010) / L_j,2010
#   An industry-year ABSENT from Comex means zero exports, not "no shock".
#   The grid is completed with explicit zeros BEFORE differencing, so a
#   total collapse yields g_jt = -EXP_j,2010 / L_j,2010 (the most negative
#   admissible shock) instead of the v4 value of 0, and post-2010 entrants
#   yield genuine positive shocks instead of NA -> 0.
# =============================================================================
exports_full <- exports_isic |>
  filter(year %in% election_years) |>                      # [F-1]
  tidyr::complete(isic4 = isic_bilateral,
                  year  = election_years,
                  fill  = list(exp_national = 0))

exp_2010 <- exports_full |> filter(year == 2010) |>
  select(isic4, exp_2010 = exp_national)          # zero when absent, never NA

L_j_2010 <- rais_isic |> group_by(isic4) |>
  summarise(L_j_2010 = sum(workers, na.rm = TRUE), .groups = "drop")

shocks <- exports_full |>
  left_join(exp_2010, by = "isic4") |>
  left_join(L_j_2010, by = "isic4") |>
  mutate(delta_exp = exp_national - exp_2010,
         g_jt      = delta_exp / L_j_2010) |>
  filter(!is.na(L_j_2010), L_j_2010 > 0)

stopifnot(!anyNA(shocks$g_jt),
          nrow(shocks) == length(unique(shocks$isic4)) * length(election_years))

# ---- [B-1] diagnostics ------------------------------------------------------
cat("\n===== V6 SHOCK-PANEL DIAGNOSTICS =====\n")
rescued <- shocks |>
  anti_join(exports_isic |> distinct(isic4, year), by = c("isic4", "year")) |>
  filter(year != 2010)
cat("Industry-years previously coded g = 0 by omission, now explicit:",
    nrow(rescued), "\n")
cat("  of which true collapses (exp_2010 > 0, exp_t = 0):",
    sum(rescued$exp_2010 > 0), "\n")
cat("  2010 export value at stake (B USD):",
    round(sum(rescued$exp_2010) * USD_UNIT / 1e9, 2), "\n")
if (nrow(rescued) == 0)
  cat(">>> FLAG TO ORCHESTRATOR: zero rescued industry-years -- the v4 bug\n",
      ">>> was latent, not active. Report before proceeding. <<<\n")

shocks |> filter(year != 2010) |> group_by(year) |>
  summarise(min = min(g_jt), p5 = quantile(g_jt, .05), mean = mean(g_jt),
            max = max(g_jt), pct_neg = round(100 * mean(g_jt < 0), 1)) |>
  print()

# =============================================================================
# STEP 8 — EXPOSURE SHARES  s_rj = L_rj,2010 / L_r,2010
# =============================================================================
L_r_2010 <- rais_isic |> group_by(micro) |>
  summarise(L_r_2010 = sum(workers, na.rm = TRUE), .groups = "drop")

shares <- rais_isic |>
  rename(L_rj_2010 = workers) |>
  left_join(L_r_2010, by = "micro") |>
  mutate(s_rj = L_rj_2010 / L_r_2010)

stopifnot(all(abs(
  shares |> group_by(micro) |> summarise(s = sum(s_rj)) |> pull(s) - 1
) < 1e-6))

# BHJ sum-of-shares control (exported for 01_): shares of TOTAL formal
# employment in bilateral tradables. (The s_rj above are within-tradable
# shares; the BHJ control needs tradable / total.)
if (RAIS_MEASURE == "fte") {
  L_r_total <- readRDS(paths$rais_fte) |>
    rename(micro = microregion_code, workers = total_fte)
} else {
  L_r_total <- readRDS(paths$rais_head) |>
    rename(micro = microregion_code, workers = total_vinculos)
}
L_r_total <- L_r_total |> group_by(micro) |>
  summarise(L_r_all = sum(workers, na.rm = TRUE), .groups = "drop")

tradable_emp_share <- L_r_2010 |>
  right_join(L_r_total, by = "micro") |>
  mutate(L_r_2010 = replace_na(L_r_2010, 0),
         tradable_emp_share = L_r_2010 / L_r_all) |>
  select(micro, tradable_emp_share)

# =============================================================================
# STEP 9 — EPW PANEL  EPW_rt = sum_j s_rj * g_jt
# =============================================================================
epw_panel <- shares |>
  crossing(year = election_years) |>
  left_join(shocks |> select(isic4, year, g_jt), by = c("isic4", "year")) |>
  mutate(g_jt = replace_na(g_jt, 0),   # post-v6: guard only; all bilateral
                                        # industry-years carry explicit g_jt
         epw_component = s_rj * g_jt) |>
  group_by(micro, year,
           across(any_of(c("state", "mesoregion_code", "mesoregion_name")))) |>
  summarise(EPW = sum(epw_component, na.rm = TRUE),
            n_industries = n_distinct(isic4[g_jt != 0]), .groups = "drop")

# ---- Sanity checks ----------------------------------------------------------
cat("\n--- SANITY CHECKS ---\n")
cat("EPW == 0 in 2010:",
    ifelse(all(filter(epw_panel, year == 2010)$EPW == 0), "PASS", "FAIL"), "\n")
cat("ISIC-4 industries in universe:", length(isic_bilateral), "\n")
epw_panel |> group_by(year) |>
  summarise(mean = mean(EPW), sd = sd(EPW), min = min(EPW),
            median = median(EPW), max = max(EPW),
            pct_neg = round(100 * mean(EPW < 0), 1)) |> print()

# ---- [B-5] v4 vs v6 comparison ---------------------------------------------
if (file.exists(paths$epw_v4)) {
  epw_v4 <- readRDS(paths$epw_v4) |> select(micro, year, EPW_v4 = EPW)
  comp <- epw_panel |> select(micro, year, EPW_v6 = EPW) |>
    inner_join(epw_v4, by = c("micro", "year")) |>
    filter(year != 2010)
  comp_summary <- comp |> group_by(year) |>
    summarise(sd_v4 = sd(EPW_v4), sd_v6 = sd(EPW_v6),
              min_v4 = min(EPW_v4), min_v6 = min(EPW_v6),
              pct_neg_v4 = round(100 * mean(EPW_v4 < 0), 1),
              pct_neg_v6 = round(100 * mean(EPW_v6 < 0), 1),
              cor_v4_v6 = round(cor(EPW_v4, EPW_v6), 4), .groups = "drop")
  cat("\n--- EPW v4 vs v6 ---\n"); print(comp_summary)
  write_csv(comp |> left_join(comp_summary, by = "year"),
            file.path("output", "epw_v4_v6_comparison.csv"))
} else cat("\n(v4 panel not found; skipping v4-v6 comparison.)\n")

# =============================================================================
# STEP 10 — SAVE (all outputs _v6)
# =============================================================================
saveRDS(epw_panel,          "epw_panel_isic_v7.rds")
saveRDS(shocks,             "sectoral_shocks_isic_v7.rds")
saveRDS(shares,             "exposure_shares_isic_v7.rds")
saveRDS(exports_isic,       "exports_isic_v7.rds")
saveRDS(rais_isic,          "rais_isic_v7.rds")
saveRDS(tradable_emp_share, "tradable_emp_share_2010_v7.rds")
write_csv(epw_panel,        "epw_panel_isic_v7.csv")

cat("\n--- PROVENANCE ---\n")
cat("Flags: WEIGHT_SCHEME =", WEIGHT_SCHEME, "| RAIS_MEASURE =", RAIS_MEASURE, "\n")
print(sessionInfo())
sink(); close(log_con)
