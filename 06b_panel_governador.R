# =============================================================================
# 06b_panel_governador.R  (pipeline stage 6b — GOVERNOR panel consolidation)
# -----------------------------------------------------------------------------
# Mirrors 06_panel_consolidation.R but with the GOVERNOR Dalton/center panel as
# the outcome source, joining the SAME (common-share) EPW/IPW treatments, the
# SAME controls_micro.rds, the SAME 2010 baseline differencing. Every output
# carries a _gov suffix.
#
# The governor branch has more severe MEASUREMENT issues than the presidential
# one (see B.1); the two most consequential are handled HERE so 07b can act on
# them:
#   (1) IDEOLOGY COVERAGE. State races carry many small parties with no BLS
#       score. Coverage (share of votes cast for scored parties) is computed
#       per STATE-YEAR, saved, and carried into the panel as a column so 07b can
#       apply a sample rule (drop state-years below a threshold) and show
#       sensitivity to the threshold. Currently 02 computes this and throws it
#       away.
#   (2) NATIONAL PARTY SCORES ON STATE CANDIDATES. BLS scores measure national
#       party positions; regional-machine governors deviate more than
#       presidential candidates. As a robustness we also build a Dalton index
#       restricted to the ~8 largest NATIONAL parties (delta_P_dalton_gov_big).
#
# Other B.1 points, verified/handled:
#   (3) COALITIONS: 01 attributes each candidate's votes to the candidate's OWN
#       registered party (SG_PARTIDO), NOT split across the coalition — the
#       correct choice; stated + asserted below.
#   (5) ROUND FILTER: 02 keeps round == 1 only (second rounds exist in some
#       states and would break comparability); inherited here.
#   (6) DISTRITO FEDERAL: single microregion => a state^year singleton, dropped
#       by feols, exactly as on the presidential side; the estimation N is
#       asserted in 07b rather than discovered.
#
# INPUTS (DATA_DIR): dalton_panel_governador.rds, painel_ideologico_governador.rds,
#   epw_common_panel_v8.rds, ipw_panel_isic_v1.rds, controls_micro.rds,
#   tradable_emp_share_2010_v7.rds
# OUTPUTS (DATA_DIR): df_estimation_gov_v1.rds (+ .csv), df_raw_gov_v1.rds,
#   governor_coverage_stateyear.rds, output/governor_coverage_stateyear.csv
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
source("/Users/solenoide/Documents/dissertação/data/códigos/_estimation_functions.R")
library(tidyverse)

# =============================================================================
# STEP 1 — LOAD
# =============================================================================
dalton_gov <- readRDS("dalton_panel_governador.rds") |>
  mutate(microregion_code = as.character(microregion_code))
epw_common <- readRDS("epw_common_panel_v8.rds") |>
  mutate(microregion_code = as.character(micro)) |> select(-micro)
ipw        <- readRDS("ipw_panel_isic_v1.rds") |>
  mutate(microregion_code = as.character(micro)) |> select(-micro)
controls   <- readRDS("controls_micro.rds") |>
  mutate(microregion_code = as.character(micro)) |> select(-micro)
# BHJ sum-of-shares control. The governor track runs on the COMMON (full
# tradable) shares from 03a, so the control must be measured over that same
# numerator set -- see ss_bhj_control() and CODE_CHANGES_TODO.md 1b ("THE
# TRAP"). Under SHARE_DENOM="tradable" this resolves to the same
# tradable-intensity variable used to date; under "total" it resolves to the
# realized sum_j s_rj over the full tradable universe.
sumsh      <- ss_bhj_control("common") |>
  rename(microregion_code = micro)

cat("Governor Dalton panel:", nrow(dalton_gov), "rows |",
    n_distinct(dalton_gov$microregion_code), "micros\n")

# =============================================================================
# STEP 2 — IDEOLOGY COVERAGE PER STATE-YEAR  (B.1.1 — save, don't discard)
# =============================================================================
pig <- readRDS("painel_ideologico_governador.rds")
stopifnot("coalition check: votes are per candidate's own party (SG_PARTIDO)" =
            all(c("party", "candidato", "votes") %in% names(pig)))
# round==1 was already imposed by 02 before building painel_ideologico_governador.

coverage_sy <- pig |>
  group_by(state, year) |>
  summarise(total_votes  = sum(votes, na.rm = TRUE),
            scored_votes = sum(votes * (!is.na(ideo)), na.rm = TRUE),
            n_parties    = n_distinct(party),
            n_scored     = n_distinct(party[!is.na(ideo)]),
            coverage     = scored_votes / total_votes, .groups = "drop") |>
  arrange(year, desc(coverage))
saveRDS(coverage_sy, "governor_coverage_stateyear.rds")
write_csv(coverage_sy, file.path("output", "governor_coverage_stateyear.csv"))

cat("\n--- GOVERNOR IDEOLOGY COVERAGE (state-year) ---\n")
cat(sprintf("state-years: %d | median coverage: %.3f\n",
            nrow(coverage_sy), median(coverage_sy$coverage)))
for (thr in c(0.90, 0.85, 0.80)) {
  cat(sprintf("  threshold %.2f -> %d of %d state-years dropped (%.0f%%)\n",
              thr, sum(coverage_sy$coverage < thr), nrow(coverage_sy),
              100 * mean(coverage_sy$coverage < thr)))
}
coverage_sy |> group_by(year) |>
  summarise(median_cov = round(median(coverage), 3),
            below_85 = sum(coverage < 0.85), n = n(), .groups = "drop") |>
  as.data.frame() |> print()

# =============================================================================
# STEP 3 — BIG-PARTY ROBUSTNESS DALTON  (B.1.2 — national-party restriction)
#   Recompute the Dalton dispersion restricting to the ~8 largest NATIONAL
#   parties (by total national governor vote, among BLS-scored parties). Same
#   formula as 02, renormalized over the restricted menu.
# =============================================================================
big_parties <- pig |> filter(!is.na(ideo)) |>
  group_by(party) |> summarise(v = sum(votes, na.rm = TRUE), .groups = "drop") |>
  slice_max(v, n = 8) |> pull(party)
cat("\n8 largest national (scored) parties:", paste(big_parties, collapse = ", "), "\n")

dalton_big <- pig |> filter(!is.na(ideo), party %in% big_parties) |>
  group_by(microregion_code, year) |>
  mutate(microregion_code = as.character(microregion_code),
         total_votes = sum(votes, na.rm = TRUE),
         v_rpt = votes / total_votes,
         y_bar = sum(v_rpt * ideo, na.rm = TRUE)) |>
  summarise(P_dalton_big = sqrt(sum(v_rpt * (ideo - y_bar)^2, na.rm = TRUE)),
            .groups = "drop") |>
  mutate(microregion_code = as.character(microregion_code))

# =============================================================================
# STEP 4 — LEVELS PANEL + 2010 BASELINE + FIRST DIFFERENCES
# =============================================================================
panel_levels <- dalton_gov |>
  left_join(dalton_big, by = c("microregion_code", "year")) |>
  left_join(epw_common |> select(microregion_code, year, EPW_common,
                                 any_of(c("state", "mesoregion_code", "mesoregion_name"))),
            by = c("microregion_code", "year")) |>
  left_join(ipw |> select(microregion_code, year,
                          IPW_total, IPW_final, IPW_interm, IPW_capital, IPW_china, IPW_IV),
            by = c("microregion_code", "year")) |>
  # attach the state-year coverage of the outcome
  left_join(coverage_sy |> select(state, year, coverage), by = c("state", "year"))

baseline_pol <- panel_levels |> filter(year == 2010) |>
  select(microregion_code,
         P_dalton_gov_2010 = P_dalton, P_center_gov_2010 = P_center,
         P_dalton_big_2010 = P_dalton_big)

df_raw <- panel_levels |>
  filter(year %in% c(2014, 2018, 2022)) |>
  left_join(baseline_pol, by = "microregion_code") |>
  mutate(delta_P_dalton_gov = P_dalton     - P_dalton_gov_2010,
         delta_P_center_gov = P_center     - P_center_gov_2010,
         delta_P_dalton_big = P_dalton_big - P_dalton_big_2010,
         delta_EPW          = EPW_common)          # cumulative change from 2010
saveRDS(df_raw, "df_raw_gov_v1.rds")

# =============================================================================
# STEP 5 — JOIN CONTROLS + tradable_emp_share; assemble estimation frame
# =============================================================================
df <- df_raw |>
  left_join(controls |> select(microregion_code, ln_pop, urban_share, educ_share,
                               ln_gdp_pc, manuf_share_of_tradable), by = "microregion_code") |>
  left_join(sumsh, by = "microregion_code") |>
  mutate(tradable_emp_share = replace_na(tradable_emp_share, 0)) |>
  select(microregion_code,
         any_of(c("state", "mesoregion_code", "mesoregion_name")), year,
         P_dalton, P_center, P_dalton_big,
         delta_P_dalton_gov, delta_P_center_gov, delta_P_dalton_big,
         delta_EPW, IPW_total, IPW_final, IPW_interm, IPW_capital, IPW_china, IPW_IV,
         coverage,
         P_dalton_gov_2010, P_center_gov_2010,
         ln_pop, urban_share, educ_share, ln_gdp_pc, manuf_share_of_tradable, tradable_emp_share) |>
  arrange(microregion_code, year)

# ---- ESTIMATION-UNIVERSE RULE — identical to 06 -----------------------------
# A microregion with zero base-year tradable employment has an undefined
# tradable composition (0/0) and no exposure share. Dropped, so the governor
# and presidential tracks share one sample rule and the two N's are comparable.
undefined_micro <- df |>
  filter(tradable_emp_share <= 0 | is.na(manuf_share_of_tradable)) |>
  distinct(microregion_code) |> pull(microregion_code)
cat("\nDropped (no base-year tradable employment):",
    if (length(undefined_micro)) paste(undefined_micro, collapse = ", ") else "none", "\n")
df <- df |> filter(!microregion_code %in% undefined_micro)
stopifnot("zero-tradable micros survived the universe rule" =
            all(df$tradable_emp_share > 0))

# =============================================================================
# STEP 6 — QUALITY CHECKS
# =============================================================================
cat("\n=== Governor estimation frame ===\n")
cat("Rows:", nrow(df), "| micros:", n_distinct(df$microregion_code),
    "| years:", paste(sort(unique(df$year)), collapse = ", "), "\n")
miss <- df |> summarise(across(c(delta_P_dalton_gov, delta_EPW, IPW_total,
                                 ln_gdp_pc, ln_pop, coverage), ~ sum(is.na(.)))) |>
  pivot_longer(everything(), names_to = "var", values_to = "n_na")
cat("--- key-variable NA counts ---\n"); print(as.data.frame(miss))
cat("\nCoverage distribution across estimation rows:\n")
print(round(quantile(df$coverage, c(0, .1, .25, .5, .75, 1), na.rm = TRUE), 3))

saveRDS(df, "df_estimation_gov_v1.rds")
write_csv(df, "df_estimation_gov_v1.csv")
cat("\nSaved df_estimation_gov_v1.rds\n")
