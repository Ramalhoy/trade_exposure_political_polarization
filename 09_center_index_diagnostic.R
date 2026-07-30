# =============================================================================
# 09_center_index_diagnostic.R
# -----------------------------------------------------------------------------
# WHY THIS SCRIPT EXISTS
#   The centre-emptying index is
#       P_center[r,t] = 1 - (vote share to parties with ideo in [-0.25, +0.25])
#   Because every microregion in a presidential election faces the SAME national
#   candidate menu, P_center can only vary across microregions through vote
#   ALLOCATION, and only if at least one party actually sits inside the centre
#   band. Whether the band is occupied is a national, year-level fact.
#
#   In 2018 NO party in the presidential field fell inside the band (the closest
#   was PODE at ideo = 0.269, just outside +0.25). P_center is therefore exactly
#   1.000 in every microregion, so
#       delta_P_center[r,2018] = 1 - P_center[r,2010]
#   which is a DETERMINISTIC AFFINE FUNCTION OF THE 2010 BASELINE and carries no
#   post-2010 information at all. In 2022 only MDB (4.2% of the vote,
#   ideo = 0.137) occupies the band, so the same near-degeneracy holds
#   (R^2 on the baseline = 0.99).
#
#   CONSEQUENCE. For two of the three stacked first differences, regressing
#   delta_P_center on the treatment is — up to sign and an additive year
#   constant absorbed by the state x year fixed effects — regressing
#   -P_center[r,2010] on the treatment. That is a pure CROSS-SECTIONAL baseline
#   correlation, not an effect on a change. The panel already carries
#   P_center_2010 (06 labels it a pre-trend control) but 07 never conditions on
#   it, so the mechanical channel is left open.
#
#   This script quantifies the degeneracy and reports the treatment coefficients
#   with and without the 2010 baseline, for both outcomes. delta_P_dalton is
#   included as the control case: its baseline R^2 is small, and its
#   coefficients are unaffected.
#
# INPUTS  (DATA_DIR): df_estimation_v7.rds, painel_ideologico_presidencial.rds
# OUTPUTS (DATA_DIR): output/report_pres_exports/J_*.csv, output/09_center_log.txt
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")

library(tidyverse)
library(fixest)
setFixest_notes(FALSE)

RDIR <- file.path("output", "report_pres_exports")
dir.create(RDIR, recursive = TRUE, showWarnings = FALSE)
log_con <- file(file.path("output", "09_center_log.txt"), open = "wt")
sink(log_con, split = TRUE)
wr <- function(x, n) { write_csv(x, file.path(RDIR, paste0(n, ".csv"))); invisible(x) }

cat("=== 09 centre-index diagnostic:", format(Sys.time()), "===\n")

CENTRE_LO <- -0.25
CENTRE_HI <-  0.25

# =============================================================================
# J1 — IS THE CENTRE BAND OCCUPIED? (national candidate menu, by year)
# =============================================================================
pig <- readRDS("painel_ideologico_presidencial.rds")
menu <- pig |> filter(!is.na(ideo)) |>
  group_by(year, party) |>
  summarise(votes = sum(votes, na.rm = TRUE), ideo = first(ideo), .groups = "drop_last") |>
  mutate(vote_share = votes / sum(votes)) |> ungroup() |>
  mutate(in_centre_band = ideo >= CENTRE_LO & ideo <= CENTRE_HI) |>
  arrange(year, desc(vote_share))

band <- menu |> group_by(year) |>
  summarise(n_parties_scored = n(),
            n_in_band = sum(in_centre_band),
            centre_vote_share = sum(vote_share[in_centre_band]),
            parties_in_band = paste(party[in_centre_band], collapse = ", "),
            closest_outside = party[!in_centre_band][which.min(
              abs(ideo[!in_centre_band]))],
            closest_outside_ideo = ideo[!in_centre_band][which.min(
              abs(ideo[!in_centre_band]))],
            .groups = "drop")
cat("\n##### J1. CENTRE-BAND OCCUPANCY BY YEAR (band = [", CENTRE_LO, ",", CENTRE_HI, "]) #####\n")
print(as.data.frame(band), digits = 4)
cat("\nP_center = 1 - centre_vote_share, so centre_vote_share = 0 forces P_center = 1\n")
cat("identically across ALL microregions (common national menu).\n")
wr(menu, "J1_candidate_menu"); wr(band, "J1_centre_band_occupancy")

# =============================================================================
# J2 — DEGENERACY OF THE OUTCOME: variance and baseline R^2 by stack
# =============================================================================
d <- readRDS("df_estimation_v7.rds") |> mutate(micro = as.character(microregion_code))
lev <- readRDS("dalton_panel_presidencial.rds")

degen <- d |> group_by(year) |>
  summarise(n = n(),
            sd_delta_P_center = sd(delta_P_center),
            sd_delta_P_dalton = sd(delta_P_dalton),
            r2_center_on_baseline = summary(lm(delta_P_center ~ P_center_2010))$r.squared,
            r2_dalton_on_baseline = summary(lm(delta_P_dalton ~ P_dalton_2010))$r.squared,
            .groups = "drop")
lev_sd <- lev |> group_by(year) |>
  summarise(n = n(), P_center_mean = mean(P_center), P_center_sd = sd(P_center),
            P_center_n_distinct = n_distinct(round(P_center, 10)),
            P_dalton_mean = mean(P_dalton), P_dalton_sd = sd(P_dalton), .groups = "drop")
cat("\n##### J2a. LEVELS of the indices by year #####\n"); print(as.data.frame(lev_sd), digits = 5)
cat("\n##### J2b. First differences: sd and R^2 on the 2010 baseline #####\n")
print(as.data.frame(degen), digits = 5)
cat("\nR^2 = 1.000 in 2018 and 0.990 in 2022 for the centre index: those two\n")
cat("stacks contain (almost) no information beyond the 2010 cross-section.\n")
wr(degen, "J2_degeneracy_by_stack"); wr(lev_sd, "J2_index_levels")

# =============================================================================
# J3 — DOES THE RESULT SURVIVE CONDITIONING ON THE 2010 BASELINE?
# =============================================================================
sd_epw <- sd(d$delta_EPW)
d <- d |> mutate(epw_boom = pmax( delta_EPW, 0) / sd_epw,
                 epw_bust = pmax(-delta_EPW, 0) / sd_epw)
ctrl_base <- c("ln_gdp_pc", "ln_pop", "tradable_emp_share")
ctrl_ext  <- c(ctrl_base, "urban_share", "educ_share", "manuf_share_of_tradable")
CSETS <- list(base = ctrl_base, extended = ctrl_ext)
zv <- unique(c("delta_P_dalton", "delta_P_center", ctrl_ext,
               "P_center_2010", "P_dalton_2010"))
ds <- d |> mutate(across(all_of(zv), ~ as.numeric(scale(.))))

rows <- list()
for (oc in c("delta_P_center", "delta_P_dalton")) {
  bl <- if (oc == "delta_P_center") "P_center_2010" else "P_dalton_2010"
  for (cs in names(CSETS)) for (withbase in c(FALSE, TRUE)) {
    ctr <- c(CSETS[[cs]], if (withbase) bl)
    m <- feols(as.formula(paste(oc, "~ epw_boom + epw_bust +",
                                paste(ctr, collapse = " + "), "| state^year")), data = ds)
    s <- summary(m, cluster = ~ mesoregion_code^year)
    rows[[paste(oc, cs, withbase)]] <- tibble(
      outcome = oc, control_set = cs, baseline_control = withbase,
      beta_boom = coef(m)["epw_boom"], se_boom = se(s)["epw_boom"],
      p_boom = pvalue(s)["epw_boom"],
      beta_bust = coef(m)["epw_bust"], se_bust = se(s)["epw_bust"],
      p_bust = pvalue(s)["epw_bust"],
      beta_baseline = if (withbase) coef(m)[bl] else NA_real_,
      within_r2 = fitstat(m, "wr2")$wr2, N = nobs(m))
  }
}
surv <- bind_rows(rows)
cat("\n##### J3. TREATMENT COEFFICIENTS WITH AND WITHOUT THE 2010 BASELINE #####\n")
print(as.data.frame(surv), digits = 3)
wr(surv, "J3_baseline_conditioning")

# =============================================================================
# J4 — WHICH STACK CARRIES THE CENTRE RESULT? (single-difference regressions)
# =============================================================================
single <- map_dfr(c(2014, 2018, 2022), function(y) {
  dy <- ds |> filter(year == y)
  m <- feols(delta_P_center ~ epw_boom + epw_bust + ln_gdp_pc + ln_pop +
               tradable_emp_share | state, data = dy)
  s <- summary(m, cluster = ~ mesoregion_code)
  tibble(year = y, beta_boom = coef(m)["epw_boom"], se_boom = se(s)["epw_boom"],
         beta_bust = coef(m)["epw_bust"], se_bust = se(s)["epw_bust"],
         p_bust = pvalue(s)["epw_bust"], N = nobs(m))
})
cat("\n##### J4. delta_P_center, stack by stack #####\n")
print(as.data.frame(single), digits = 3)
wr(single, "J4_center_by_stack")

cat("\n--- PROVENANCE ---\n"); print(sessionInfo())
sink(); close(log_con)
