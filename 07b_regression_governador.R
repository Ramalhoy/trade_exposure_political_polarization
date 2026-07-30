# =============================================================================
# 07b_regression_governador.R  (pipeline stage 7b — GOVERNOR regressions)
# -----------------------------------------------------------------------------
# Mirrors 07_regression_inference.R for the GOVERNOR outcome, calling the shared
# machinery in _estimation_functions.R so the two scripts cannot drift. Same
# control sets, same state^year FE, same four-regime inference (RI primary,
# AKM/AKM0 secondary, Conley + meso^year cluster reference), same asymmetric
# boom/bust decomposition, same Rotemberg + effective-# -shocks diagnostics.
#
# WHAT THE GOVERNOR TRACK BUYS (B.3): a falsification-flavored comparison. If
# trade shocks polarize through NATIONAL ideological conflict, the effect should
# be WEAKER in state races; if through LOCAL economic grievance, it could be
# equally strong or stronger. It DOUBLES the outcome variation but adds NO
# treatment variation — the effective-shock problem (eff_n ~ 2.4 under per-worker
# scaling) is unchanged. Interpretive note (B.1.4): every microregion in a state
# faces the SAME candidate menu, so P_dalton_gov varies WITHIN state only through
# vote-share allocation (a cleaner voter-side dispersion measure), whereas the
# presidential outcome mixes menu and allocation.
#
# EVERY headline table reports: N, effective # shocks, RI p-value, AKM0 interval
# — never a lone cluster-SE t-stat, given the documented ~7x over-rejection.
#
# INPUTS (DATA_DIR): df_estimation_gov_v1.rds, exposure_shares_common_v8.rds,
#   sectoral_shocks_isic_v7.rds, sectoral_import_shocks_v1.rds,
#   epw_common_panel_v8.rds, micro_centroids.rds
# OUTPUTS: tables/tab_governor_*.tex, output/07b_governor_log.txt,
#   output/07b_coverage_sensitivity.csv, output/07b_governor_headline.csv
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
source("/Users/solenoide/Documents/dissertação/data/códigos/_estimation_functions.R")
library(tidyverse)
library(fixest)
setFixest_notes(FALSE)     # silence per-call singleton NOTEs (RI loop -> log spam)
set.seed(2026)

B_RI <- 4999   # governor RI draws (four-regime; kept < 07's 9999 for runtime)
dir.create("output", showWarnings = FALSE)
log_con <- file(file.path("output", "07b_governor_log.txt"), open = "wt")
sink(log_con, split = TRUE)
cat("=== 07b governor regressions:", format(Sys.time()), "===\n\n")

# =============================================================================
# LOAD + ESTIMATION SAMPLE (mirror 07 [A-10]: restrict to the EPW universe)
# =============================================================================
df_raw     <- readRDS("df_estimation_gov_v1.rds") |> mutate(micro = as.character(microregion_code))
shares     <- readRDS("exposure_shares_common_v8.rds") |> mutate(micro = as.character(micro))
g_shocks   <- readRDS("sectoral_shocks_isic_v7.rds")           # export g_jt
m_shocks   <- readRDS("sectoral_import_shocks_v1.rds")         # import m_lev etc.
epw_common <- readRDS("epw_common_panel_v8.rds") |> mutate(micro = as.character(micro))
centroids  <- readRDS("micro_centroids.rds") |> mutate(micro = as.character(micro))

epw_micros <- unique(epw_common$micro)
excluded   <- setdiff(unique(df_raw$micro), epw_micros)
cat("Excluded (not in EPW universe):",
    if (length(excluded)) paste(excluded, collapse = ", ") else "none", "\n")

df <- df_raw |>
  filter(year %in% c(2014, 2018, 2022), micro %in% epw_micros) |>
  mutate(delta_EPW = replace_na(delta_EPW, 0),
         across(starts_with("IPW_"), ~ replace_na(., 0)))
stopifnot("state label missing" = !anyNA(df$state))
N_SAMPLE <- nrow(df)

outcomes  <- c("delta_P_dalton_gov", "delta_P_center_gov")
ctrl_base <- c("ln_gdp_pc", "ln_pop", "tradable_emp_share")

# standardize outcomes, treatment, controls (mirror 07); keep raw treatment
sd_epw <- sd(df$delta_EPW)
sd_ipw <- sd(df$IPW_total)
df_scaled <- df |>
  mutate(delta_EPW_raw = delta_EPW, IPW_total_raw = IPW_total) |>
  mutate(across(all_of(c(outcomes, "delta_P_dalton_big", "delta_EPW", "IPW_total",
                         ctrl_base)), ~ as.numeric(scale(.)))) |>
  select(-any_of(c("lat", "lon", "long"))) |>
  left_join(centroids, by = "micro")

# =============================================================================
# SHARE + SHOCK MATRICES (common shares; export g and import m on ONE index)
# =============================================================================
W     <- ss_build_W(shares, df_scaled$micro)
g_mat <- ss_build_gmat(g_shocks, "g_jt",  W)     # export shocks (152 -> 163, zeros)
m_mat <- ss_build_gmat(m_shocks, "m_lev", W)     # import shocks (153 -> 163, zeros)
stopifnot(nrow(W) == nrow(df_scaled),
          identical(rownames(g_mat), rownames(m_mat)))   # same industry index
# exact reconstruction of the export treatment on the estimation rows:
epw_recon <- ss_epw_from(W, g_mat, df_scaled$year)
cat(sprintf("[recon] max|W%%*%%g - delta_EPW_raw| = %.2e\n",
            max(abs(epw_recon - df_scaled$delta_EPW_raw))))

export_universe <- unique(g_shocks$isic4)
import_universe <- setdiff(colnames(W)[colSums(abs(m_mat)) > 0], character(0))

# =============================================================================
# 1. BASELINE OLS (EPW) + JOINT EPW+IPW + NET EXPOSURE (reference cluster SEs)
# =============================================================================
cat("\n########## [1] BASELINE / JOINT / NET (governor) ##########\n")
df_scaled <- df_scaled |>
  mutate(epw_z = delta_EPW, ipw_z = IPW_total,
         net_z = as.numeric(scale(delta_EPW_raw - IPW_total_raw)))
mods <- list()
for (oc in outcomes) {
  mods[[paste0(oc, "_epw")]]  <- ss_baseline(df_scaled, oc, "epw_z", ctrl_base)
  mods[[paste0(oc, "_joint")]] <- ss_baseline(df_scaled, oc, c("epw_z", "ipw_z"), ctrl_base)
  mods[[paste0(oc, "_net")]]  <- ss_baseline(df_scaled, oc, "net_z", ctrl_base)
}
N_EST <- unique(map_int(mods, ~ .x$n))
stopifnot("models differ in estimation N" = length(N_EST) == 1L)
cat("Estimation N (post state^year singleton drop):", N_EST, "of", N_SAMPLE, "raw\n")
for (nm in names(mods)) {
  s <- mods[[nm]]$summary
  co <- coef(s); se <- s$se
  cat(sprintf("%-30s | %s\n", nm,
      paste(sprintf("%s=%.4f(t=%.2f)", names(co)[1:min(2,length(co))],
                    co[1:min(2,length(co))], (co/se)[1:min(2,length(co))]),
            collapse = " | ")))
}

# =============================================================================
# 2. CONLEY SPATIAL SEs (reference regime)
# =============================================================================
cat("\n########## [2] CONLEY (250km/500km) ##########\n")
for (cut in c(250, 500)) {
  m <- feols(delta_P_dalton_gov ~ epw_z + ln_gdp_pc + ln_pop + tradable_emp_share |
               state^year, data = df_scaled, vcov = conley(cut))
  cat(sprintf("  %dkm: epw beta=%.4f t=%.2f\n", cut, coef(m)["epw_z"], tstat(m)["epw_z"]))
}

# =============================================================================
# 3. AKM / AKM0 (secondary regime)
# =============================================================================
cat("\n########## [3] AKM / AKM0 ##########\n")
library(ShiftShareSE)
akm_dalton <- ss_akm(df_scaled, "delta_P_dalton_gov", "delta_EPW_raw", ctrl_base, W)
print(akm_dalton)
akm0_ci_dalton <- ss_akm0_ci(akm_dalton)

# =============================================================================
# 4. ROTEMBERG / EFFECTIVE # SHOCKS (same treatment, so ~ export 2.4)
# =============================================================================
cat("\n########## [4] ROTEMBERG / eff_n ##########\n")
rot_exp <- ss_rotemberg(df_scaled, W, g_mat, "delta_EPW_raw", ctrl_base)
effn_exp <- ss_eff_n(rot_exp)
cat("Export-treatment eff_n by year (governor sample):\n"); print(as.data.frame(effn_exp), digits = 3)
eff_n_mean <- mean(effn_exp$eff_n)

# =============================================================================
# 5. DESIGN-BASED RI (primary) — pooled EPW, bust EPW, and JOINT EPW+IPW
#    Permute industry shock PATHS; the joint spec permutes BOTH g and m with the
#    SAME industry permutation (preserving cross-treatment structure).
# =============================================================================
cat(sprintf("\n########## [5] RANDOMIZATION INFERENCE (B=%d) ##########\n", B_RI))
yv <- df_scaled$year
refit <- function(treats) {
  epw_raw <- treats$EPW; ipw_raw <- treats$IPW
  d <- df_scaled |>
    mutate(epw_s  = epw_raw / sd_epw,
           ipw_s  = ipw_raw / sd_ipw,
           bust_s = pmax(-epw_raw, 0) / sd_epw,
           boom_s = pmax( epw_raw, 0) / sd_epw)
  m_pool  <- feols(delta_P_dalton_gov ~ epw_s + ln_gdp_pc + ln_pop +
                     tradable_emp_share | state^year, data = d, lean = TRUE)
  m_bust  <- feols(delta_P_dalton_gov ~ bust_s + boom_s + ln_gdp_pc + ln_pop +
                     tradable_emp_share | state^year, data = d, lean = TRUE)
  m_jt    <- feols(delta_P_dalton_gov ~ epw_s + ipw_s + ln_gdp_pc + ln_pop +
                     tradable_emp_share | state^year, data = d, lean = TRUE)  # fit once
  c(pooled = unname(coef(m_pool)["epw_s"]), bust = unname(coef(m_bust)["bust_s"]),
    joint_epw = unname(coef(m_jt)["epw_s"]), joint_ipw = unname(coef(m_jt)["ipw_s"]))
}
beta_star <- ss_ri(list(EPW = W, IPW = W), list(EPW = g_mat, IPW = m_mat), yv,
                   refit, B = B_RI)
colnames(beta_star) <- c("pooled", "bust", "joint_epw", "joint_ipw")

# observed statistics (same refit on the identity permutation)
obs <- refit(list(EPW = ss_epw_from(W, g_mat, yv), IPW = ss_epw_from(W, m_mat, yv)))
ri_p <- setNames(map_dbl(colnames(beta_star), ~ ss_ri_p(beta_star[, .x], obs[.x])),
                 colnames(beta_star))
cat("Design-based RI p-values (governor Dalton):\n")
for (nm in names(ri_p))
  cat(sprintf("  %-10s: beta=%+.4f | p=%.4f\n", nm, obs[nm], ri_p[nm]))

# =============================================================================
# 6. ASYMMETRIC DECOMPOSITION (boom/bust magnitudes) — EPW and IPW
# =============================================================================
cat("\n########## [6] ASYMMETRIC DECOMPOSITION ##########\n")
for (oc in outcomes) {
  a_epw <- ss_asym(df_scaled, oc, "delta_EPW_raw", ctrl_base, sd_epw, prefix = "epw")
  a_ipw <- ss_asym(df_scaled, oc, "IPW_total_raw", ctrl_base, sd_ipw, prefix = "ipw")
  cat(sprintf("%-20s | EPW bust=%+.4f boom=%+.4f | IPW bust=%+.4f boom=%+.4f\n",
              oc, a_epw$beta_bust, a_epw$beta_boom, a_ipw$beta_bust, a_ipw$beta_boom))
}

# =============================================================================
# 7. COVERAGE SAMPLE-RULE SENSITIVITY (B.1.1) — threshold sweep
# =============================================================================
cat("\n########## [7] IDEOLOGY-COVERAGE SAMPLE-RULE SENSITIVITY ##########\n")
cov_sens <- map_dfr(c(0, 0.80, 0.85, 0.90), function(thr) {
  d <- filter(df_scaled, coverage >= thr)
  n_drop_sy <- df_scaled |> filter(coverage < thr) |> distinct(state, year) |> nrow()
  m <- feols(delta_P_dalton_gov ~ epw_z + ln_gdp_pc + ln_pop + tradable_emp_share |
               state^year, data = d, cluster = ~ mesoregion_code^year)
  tibble(threshold = thr, n_obs = nobs(m), n_state_years_dropped = n_drop_sy,
         beta_epw = coef(m)["epw_z"], t_epw = tstat(m)["epw_z"])
})
print(as.data.frame(cov_sens), digits = 4)
write_csv(cov_sens, file.path("output", "07b_coverage_sensitivity.csv"))

# =============================================================================
# 8. BIG-PARTY ROBUSTNESS (B.1.2) — Dalton over the 8 largest national parties
# =============================================================================
cat("\n########## [8] BIG-PARTY (national-line) ROBUSTNESS ##########\n")
m_big <- feols(delta_P_dalton_big ~ epw_z + ln_gdp_pc + ln_pop + tradable_emp_share |
                 state^year, data = df_scaled, cluster = ~ mesoregion_code^year)
cat(sprintf("delta_P_dalton_big ~ EPW: beta=%.4f t=%.2f n=%d\n",
            coef(m_big)["epw_z"], tstat(m_big)["epw_z"], nobs(m_big)))

# =============================================================================
# 9. HEADLINE REPORTING ROWS (N | eff_n | RI p | AKM0 CI) + tables
# =============================================================================
cat("\n########## [9] HEADLINE (required reporting format) ##########\n")
headline <- c(
  ss_report_row("gov Dalton ~ EPW (pooled)", N_EST, eff_n_mean, ri_p["pooled"], akm0_ci_dalton),
  ss_report_row("gov Dalton ~ EPW (bust)",   N_EST, eff_n_mean, ri_p["bust"],   akm0_ci_dalton),
  ss_report_row("gov Dalton ~ EPW|IPW joint", N_EST, eff_n_mean, ri_p["joint_epw"], akm0_ci_dalton)
)
cat(paste(headline, collapse = "\n"), "\n")
tibble(row = headline) |> write_csv(file.path("output", "07b_governor_headline.csv"))

dict <- c(epw_z = "$\\Delta$ EPW", ipw_z = "$\\Delta$ IPW", net_z = "Net exposure",
          delta_P_dalton_gov = "$\\Delta P^{D}_{gov}$",
          delta_P_center_gov = "$\\Delta P^{N}_{gov}$",
          ln_gdp_pc = "Log GDP pc", ln_pop = "Log pop",
          tradable_emp_share = "Tradable emp share", "state^year" = "State $\\times$ year")
etable(map(mods, "model"), dict = dict, digits = 3, fitstat = ~ n + war2,
       tex = TRUE, title = "Trade exposure and GOVERNOR-race polarization",
       label = "tab:governor", cluster = ~ mesoregion_code^year,
       notes = sprintf("Design-based RI p (EPW, gov Dalton): %.3f. AKM0 CI: [%s, %s].",
                       ri_p["pooled"], akm0_ci_dalton[1], akm0_ci_dalton[2]),
       file = file.path("tables", "tab_governor_baseline.tex"), replace = TRUE)

cat("\n--- PROVENANCE ---\n"); print(sessionInfo())
sink(); close(log_con)
