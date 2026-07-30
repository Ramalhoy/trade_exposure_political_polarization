# =============================================================================
# 03a_shares_common.R  (pipeline stage 3a — COMMON share denominator)
# -----------------------------------------------------------------------------
# WHY THIS SCRIPT EXISTS
#   In 03_epw_construction.R the exposure shares s_rj are formed AFTER the
#   export-bilateral restriction (STEP 6: isic_bilateral = intersect(exports,
#   rais)), so they sum to 1 over the EXPORT-bilateral industry set. An import
#   treatment built on its own intersect(imports, rais) set would have shares
#   summing to 1 over a DIFFERENT denominator, making EPW and IPW non-
#   commensurable and their sum (or difference) meaningless.
#
#   Fix (this script): compute exposure shares ONCE, over the FULL tradable
#   RAIS universe —
#       s_rj = L_rj,2010 / D_r,2010 ,   numerator = ALL tradable ISIC in RAIS
#   Each treatment then uses its own shock vector with EXPLICIT ZEROS for
#   industries outside its own bilateral set. Nothing about the crosswalk
#   changes; only the set over which shares are normalized.
#
#   The DENOMINATOR D_r is set by SHARE_DENOM in _config.R ("tradable" =
#   within-tradable shares summing to 1; "total" = total formal employment, so
#   shares are incomplete and sum to theta_r). That flag is orthogonal to the
#   common-numerator fix above and is applied identically in 03.
#
# MANDATORY REGRESSION GUARD (re-baselined on SHARE_DENOM — see STEP 5)
#   Rebuild EPW under the common shares (export shocks g_jt, zeros outside the
#   export-bilateral set) and compare against EPW_v7 BY YEAR, reporting mean/sd
#   side by side.
#     SHARE_DENOM="tradable": assert cor > 0.99. The two scripts normalize over
#       different numerator sets, so they differ by a per-micro rescaling. A
#       materially lower correlation means the treatment has MOVED and every
#       03c result would need re-running — the script STOPS with a diagnostic.
#     SHARE_DENOM="total": the two panels are algebraically IDENTICAL, so assert
#       equality to machine precision instead. Stronger, not looser.
#
# INPUTS (DATA_DIR):
#   rais_fte.rds / rais_2010_micro.rds     (employment; same as 03)
#   CNAE20_ISIC4.xls                       (employment-side crosswalk)
#   un_hs2012_isic4_weighted.csv           (export-side crosswalk -> composite sig)
#   ncm_isic_match_v7.rds  composite_map_v7.rds   (if absent, replayed & saved)
#   sectoral_shocks_isic_v7.rds            (export shocks g_jt for the guard)
#   epw_panel_isic_v7.rds                  (v7 EPW for the guard)
#   manual_residual_assignments.csv        (optional [F-2] hook; mirrors 03)
#
# OUTPUTS (DATA_DIR):
#   exposure_shares_common_v8.rds          (micro x isic4: s_rj over full tradable)
#   share_sum_theta_common_v9.rds          (realized sum_j s_rj = BHJ control for
#                                           anything estimated on THESE shares)
#   rais_isic_full_tradable_v8.rds         (full tradable employment, pre-restrict)
#   epw_common_panel_v8.rds                (EPW rebuilt on common shares)
#   ncm_isic_match_v7.rds / composite_map_v7.rds  (materialized if missing)
#   output/03a_shares_common_log.txt
#   output/03a_epw_common_vs_v7.csv        (the guard table)
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")

library(tidyverse)
library(readxl)
library(janitor)

dir.create("output", showWarnings = FALSE)
log_con <- file(file.path("output", "03a_shares_common_log.txt"), open = "wt")
sink(log_con, split = TRUE)
cat("=== 03a shares-common run:", format(Sys.time()), "===\n\n")

RAIS_MEASURE  <- "fte"     # must match 03 ("fte" | "head")
WEIGHT_SCHEME <- "share"   # must match 03

# ---- helpers (identical to 03) ----------------------------------------------
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
# STEP 1 — NCM6->ISIC4 MATCH TABLE + COMPOSITE MAP
#   Read the persisted tables saved by 03; if absent (03 not yet re-run),
#   REPLAY the identical construction and save them (materializing the two
#   files the Part-0 refactor requires). The replay is the same logic 03b
#   already validates against the saved v7 universe.
# =============================================================================
if (file.exists("ncm_isic_match_v7.rds") && file.exists("composite_map_v7.rds")) {
  ncm_isic_v7   <- readRDS("ncm_isic_match_v7.rds")
  composite_map <- readRDS("composite_map_v7.rds")
  cat("STEP 1: read persisted ncm_isic_match_v7.rds + composite_map_v7.rds\n")
} else {
  cat("STEP 1: persisted match tables absent — replaying crosswalk & saving.\n")
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

  if (file.exists("manual_residual_assignments.csv")) {
    man <- read_csv("manual_residual_assignments.csv", col_types = cols(.default = "c")) |>
      mutate(ncm6 = str_pad(ncm6, 6, pad = "0"), w_ncm = as.numeric(coalesce(w_ncm, "1")))
    ncm_isic_v7 <- bind_rows(ncm_isic_v7, man |> select(ncm6, isic4, w_ncm))
    cat("[F-2] manual residual assignments appended:", nrow(man), "rows\n")
  }
  stopifnot(all(abs(
    ncm_isic_v7 |> group_by(ncm6) |> summarise(s = sum(w_ncm)) |> pull(s) - 1) < 1e-9))

  isic_signature <- ncm_isic_v7 |> arrange(ncm6) |> group_by(isic4) |>
    summarise(sig = paste(ncm6, round(w_ncm, 4), collapse = "|"), .groups = "drop")
  composite_map <- isic_signature |> group_by(sig) |>
    mutate(isic_composite = min(isic4), n_in_group = n()) |> ungroup() |>
    select(isic4, isic_composite, n_in_group)

  saveRDS(ncm_isic_v7,   "ncm_isic_match_v7.rds")
  saveRDS(composite_map, "composite_map_v7.rds")
}

# =============================================================================
# STEP 2 — EMPLOYMENT SIDE: RAIS CNAE-5 -> CNAE-4 -> ISIC-4 (full tradable)
#   Identical to 03 STEP 3b + STEP 5, but WITHOUT the bilateral restriction.
# =============================================================================
if (RAIS_MEASURE == "fte") {
  rais_raw <- readRDS("rais_fte.rds") |>
    rename(micro = microregion_code, cnae5 = cnae_2, workers = total_fte)
} else {
  rais_raw <- readRDS("rais_2010_micro.rds") |>
    rename(micro = microregion_code, cnae5 = cnae_2, workers = total_vinculos)
}
rais <- rais_raw |> mutate(cnae5 = clean_code(cnae5))
cat("RAIS measure:", RAIS_MEASURE, "| total workers:",
    format(round(sum(rais$workers)), big.mark = ","), "\n")

cnae_isic_raw <- read_excel("CNAE20_ISIC4.xls", skip = 1) |> clean_names()
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
cnae_isic_w <- cnae_isic |> group_by(cnae4) |> mutate(w_cnae = 1 / n()) |> ungroup()

rais_cnae4 <- rais |>
  mutate(cnae4 = str_sub(cnae5, 1, 4)) |>
  group_by(micro, cnae4,
           across(any_of(c("state", "mesoregion_code", "mesoregion_name")))) |>
  summarise(workers = sum(workers, na.rm = TRUE), .groups = "drop")

rais_isic <- rais_cnae4 |>
  inner_join(cnae_isic_w, by = "cnae4", relationship = "many-to-many") |>
  mutate(workers_isic = workers * w_cnae) |>
  group_by(micro, isic4,
           across(any_of(c("state", "mesoregion_code", "mesoregion_name")))) |>
  summarise(workers = sum(workers_isic, na.rm = TRUE), .groups = "drop") |>
  filter(is_tradable_isic(isic4))          # ALL tradable ISIC — NO bilateral cut

# composite-aggregate with the SAME map as the export side (self-map otherwise)
work_before <- sum(rais_isic$workers)
rais_isic <- rais_isic |>
  left_join(composite_map |> select(isic4, isic_composite), by = "isic4") |>
  mutate(isic_composite = coalesce(isic_composite, isic4)) |>
  group_by(micro, isic4 = isic_composite,
           across(any_of(c("state", "mesoregion_code", "mesoregion_name")))) |>
  summarise(workers = sum(workers), .groups = "drop")
stopifnot("employment not conserved through composite aggregation" =
            abs(sum(rais_isic$workers) - work_before) < 1e-6 * max(work_before, 1))

cat("Full tradable RAIS universe: ", n_distinct(rais_isic$isic4), "ISIC industries |",
    n_distinct(rais_isic$micro), "micros\n")
saveRDS(rais_isic, "rais_isic_full_tradable_v8.rds")

# =============================================================================
# STEP 3 — COMMON EXPOSURE SHARES  s_rj = L_rj,2010 / D_r,2010
#
#   D_r = L_r_2010 (FULL tradable employment)  if SHARE_DENOM = "tradable"
#   D_r = L_r_all  (TOTAL formal employment)   if SHARE_DENOM = "total"
#
# "Common" refers to the NUMERATOR set (full tradable RAIS universe, not the
# export-bilateral cut), which is what makes EPW and IPW commensurable. That is
# orthogonal to SHARE_DENOM, which fixes the denominator; see _config.R.
#
# The full-tradable numerator is kept and the explicit g_jt = 0 outside each
# bilateral set is kept -- that part was always right.
# =============================================================================
L_r_2010 <- rais_isic |> group_by(micro) |>
  summarise(L_r_2010 = sum(workers, na.rm = TRUE), .groups = "drop")

# total formal employment, ALL sectors -- same source and measure as 03
if (RAIS_MEASURE == "fte") {
  L_r_total <- readRDS("rais_fte.rds") |>
    rename(micro = microregion_code, workers = total_fte)
} else {
  L_r_total <- readRDS("rais_2010_micro.rds") |>
    rename(micro = microregion_code, workers = total_vinculos)
}
L_r_total <- L_r_total |> group_by(micro) |>
  summarise(L_r_all = sum(workers, na.rm = TRUE), .groups = "drop")

shares_common <- rais_isic |>
  rename(L_rj_2010 = workers) |>
  left_join(L_r_2010,  by = "micro") |>
  left_join(L_r_total, by = "micro") |>
  filter(L_r_2010 > 0, L_r_all > 0) |>
  mutate(
    theta_r   = L_r_2010 / L_r_all,                 # FULL-tradable intensity
    s_rj_trad = L_rj_2010 / L_r_2010,
    s_rj      = if (SHARE_DENOM == "total") L_rj_2010 / L_r_all else s_rj_trad
  )

stopifnot(
  "share identity s_total != theta_r * s_tradable" =
    max(abs(shares_common$s_rj - (if (SHARE_DENOM == "total")
                                    shares_common$theta_r * shares_common$s_rj_trad
                                  else shares_common$s_rj_trad))) < 1e-12,
  "s_rj is NA/NaN" = !anyNA(shares_common$s_rj)
)

# ---- realized sum of shares over the FULL-TRADABLE numerator ----------------
# THE TRAP (CODE_CHANGES_TODO.md 1b): this is NOT the same object as
# tradable_emp_share_2010_v7.rds, which is measured over the narrower
# export-bilateral numerator. Anything estimated on THESE shares must use THIS
# control. Hence a separate file.
share_sum_common <- shares_common |> group_by(micro) |>
  summarise(sum_s_rj = sum(s_rj), .groups = "drop")

if (SHARE_DENOM == "tradable") {
  stopifnot("common shares do not sum to 1 per micro" =
              all(abs(share_sum_common$sum_s_rj - 1) < 1e-6))
} else {
  stopifnot("common share sum outside (0, 1]" =
              all(share_sum_common$sum_s_rj > 0 &
                  share_sum_common$sum_s_rj <= 1 + 1e-9))
}
cat(sprintf("SHARE_DENOM = %s | sum_j s_rj (full-tradable numerator): mean %.4f | min %.4f | max %.4f\n",
            SHARE_DENOM, mean(share_sum_common$sum_s_rj),
            min(share_sum_common$sum_s_rj), max(share_sum_common$sum_s_rj)))
saveRDS(share_sum_common, paths$share_sum_com)

attr(shares_common, "share_denom") <- SHARE_DENOM
saveRDS(shares_common, "exposure_shares_common_v8.rds")
cat("Saved exposure_shares_common_v8.rds:", nrow(shares_common), "rows |",
    n_distinct(shares_common$micro), "micros\n")

# =============================================================================
# STEP 4 — REBUILD EPW UNDER COMMON SHARES (export shocks, zeros outside set)
# =============================================================================
shocks <- readRDS("sectoral_shocks_isic_v7.rds")     # isic4 x year: g_jt (export)
epw_common <- shares_common |>
  select(micro, isic4, s_rj,
         any_of(c("state", "mesoregion_code", "mesoregion_name"))) |>
  crossing(year = election_years) |>
  left_join(shocks |> select(isic4, year, g_jt), by = c("isic4", "year")) |>
  mutate(g_jt = replace_na(g_jt, 0),                 # EXPLICIT zeros outside export set
         epw_component = s_rj * g_jt) |>
  group_by(micro, year,
           across(any_of(c("state", "mesoregion_code", "mesoregion_name")))) |>
  summarise(EPW_common = sum(epw_component, na.rm = TRUE), .groups = "drop")
attr(epw_common, "share_denom") <- SHARE_DENOM
saveRDS(epw_common, "epw_common_panel_v8.rds")

stopifnot("EPW_common != 0 in 2010" =
            all(abs(filter(epw_common, year == 2010)$EPW_common) < 1e-12))

# =============================================================================
# STEP 5 — MANDATORY REGRESSION GUARD  EPW_common vs EPW_v7, by year
#
# The guard is RE-BASELINED on SHARE_DENOM, because what "no unintended
# movement" means differs between the two conventions:
#
#   "tradable"  The two scripts normalise over DIFFERENT numerator sets
#               (export-bilateral in 03, full tradable here), so
#               EPW_common = (L_r^bilat / L_r^trad) * EPW_v7 -- a per-micro
#               rescaling. Correlation should be high but not exact:
#               assert cor > 0.99 by year, as before.
#
#   "total"     Both scripts divide by the SAME L_r_all, and industries outside
#               the export-bilateral set carry g_jt = 0, so they contribute
#               nothing. The two panels are therefore ALGEBRAICALLY IDENTICAL:
#               assert EQUALITY to machine precision, which is a far stronger
#               check than any correlation threshold.
#
# The 0.99 threshold is kept for future refactors under "tradable"; it is not
# silently loosened. (CODE_CHANGES_TODO.md 1b, "Also re-baseline the 03a guard".)
# =============================================================================
epw_v7 <- readRDS("epw_panel_isic_v7.rds") |> mutate(micro = as.character(micro))

# Mixed-vintage detector: 03 stamps its share convention onto the saved panel.
v7_denom <- attr(readRDS("epw_panel_isic_v7.rds"), "share_denom")
if (is.null(v7_denom)) {
  cat("\n[!] epw_panel_isic_v7.rds carries no share_denom stamp -- it predates the\n",
      "    SHARE_DENOM refactor. Re-run 03_epw_construction.R before trusting\n",
      "    the guard below.\n")
} else if (!identical(v7_denom, SHARE_DENOM)) {
  stop(sprintf(paste0("MIXED-VINTAGE BUILD: epw_panel_isic_v7.rds was built under ",
                      "SHARE_DENOM='%s' but this run uses '%s'. Re-run ",
                      "03_epw_construction.R first."), v7_denom, SHARE_DENOM))
}

guard <- epw_common |> mutate(micro = as.character(micro)) |>
  inner_join(epw_v7 |> select(micro, year, EPW_v7 = EPW), by = c("micro", "year")) |>
  filter(year != 2010) |>
  group_by(year) |>
  summarise(n = n(),
            cor_common_v7 = cor(EPW_common, EPW_v7),
            max_abs_gap = max(abs(EPW_common - EPW_v7)),
            mean_common = mean(EPW_common), sd_common = sd(EPW_common),
            mean_v7 = mean(EPW_v7), sd_v7 = sd(EPW_v7),
            .groups = "drop")
cat("\n--- GUARD: EPW_common vs EPW_v7 (by year) | SHARE_DENOM =", SHARE_DENOM, "---\n")
print(as.data.frame(guard), digits = 5)
write_csv(guard, file.path("output", "03a_epw_common_vs_v7.csv"))

if (SHARE_DENOM == "total") {
  max_gap <- max(guard$max_abs_gap)
  if (max_gap >= 1e-10) {
    cat(sprintf("\n>>> STOP: max |EPW_common - EPW_v7| = %.3e, expected 0.\n", max_gap))
    cat(">>> Under a common L_r_all denominator the two panels must coincide\n")
    cat(">>> exactly; a gap means the NUMERATOR sets or the composite map have\n")
    cat(">>> drifted apart between 03 and 03a.\n")
    stopifnot("GUARD FAILED: EPW_common != EPW_v7 under SHARE_DENOM='total'" =
                max_gap < 1e-10)
  }
  cat(sprintf("\nGUARD PASS: EPW_common == EPW_v7 exactly (max gap %.2e). With a\n",
              max_gap))
  cat("common total-employment denominator the export-bilateral restriction on\n")
  cat("the numerator is irrelevant -- industries outside it carry g_jt = 0 --\n")
  cat("so EPW and IPW are commensurable by construction.\n")
} else {
  min_cor <- min(guard$cor_common_v7)
  if (min_cor <= 0.99) {
    cat(sprintf("\n>>> STOP: min by-year cor(EPW_common, EPW_v7) = %.4f <= 0.99.\n", min_cor))
    cat(">>> The common-denominator change has MOVED the treatment; every 03c\n")
    cat(">>> result must be re-run on the common shares before trusting IPW.\n")
    stopifnot("GUARD FAILED: EPW_common does not reproduce EPW_v7 (cor <= 0.99)" =
                min_cor > 0.99)
  } else {
    cat(sprintf("\nGUARD PASS: min by-year cor = %.4f > 0.99. The denominator change is\n",
                min_cor))
    cat("a per-micro rescaling that leaves the export treatment's cross-sectional\n")
    cat("pattern intact; 03c results stand and EPW/IPW are now commensurable.\n")
  }
}

cat("\n--- PROVENANCE ---\n"); print(sessionInfo())
sink(); close(log_con)
