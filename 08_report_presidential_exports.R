# =============================================================================
# 08_report_presidential_exports.R
# -----------------------------------------------------------------------------
# Assembles the COMPLETE presidential x export-exposure result set — descriptive
# statistics through the full inference regime — into one machine-readable set of
# CSVs plus a printed log, for direct transcription into a conference paper.
#
# This script ESTIMATES nothing that 03/03b/03c/06/07 do not already estimate,
# with three deliberate additions:
#   (1) every specification is run under BOTH control sets (base and extended).
#       07's decomposition block uses ctrl_base only, while the paper's Table 3
#       reports the EXTENDED set — so the two disagreed. Both are reported here.
#   (2) randomization inference is extended to the EXTENDED-control decomposition
#       and to the boom coefficient (07 covers pooled + bust under ctrl_base).
#   (3) a 2SLS block on the external-demand instrument (03b), which 03b builds
#       and reports a first stage for but never uses in estimation.
#
# SCOPE: presidential outcomes, EXPORT treatment only. No import (IPW) channel,
# no governor track. SHARE_DENOM is whatever 00_config.R declares.
#
# INPUTS (DATA_DIR): df_estimation_v7.rds, exposure_shares_isic_v7.rds,
#   sectoral_shocks_isic_v7.rds, epw_panel_isic_v7.rds, micro_centroids.rds,
#   shock_exogeneity_results_v1.rds, epw_iv_panel_v1.rds, sectoral_demand_iv_v1.rds
# OUTPUTS: output/report_pres_exports/*.csv, output/08_report_log.txt
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
source("/Users/solenoide/Documents/dissertação/data/códigos/_estimation_functions.R")

library(tidyverse)
library(fixest)
library(ShiftShareSE)
setFixest_notes(FALSE)
set.seed(2026)

RDIR <- file.path("output", "report_pres_exports")
dir.create(RDIR, recursive = TRUE, showWarnings = FALSE)
log_con <- file(file.path("output", "08_report_log.txt"), open = "wt")
sink(log_con, split = TRUE)

wr <- function(x, name) { write_csv(x, file.path(RDIR, paste0(name, ".csv"))); invisible(x) }
hdr <- function(...) cat("\n\n##########", ..., "##########\n")

cat("=== 08 presidential x exports report:", format(Sys.time()), "===\n")
cat("SHARE_DENOM =", SHARE_DENOM, "\n")

# =============================================================================
# A — SAMPLE (rebuilt exactly as 07 does, so every number below is 07-comparable)
# =============================================================================
df_raw <- readRDS("df_estimation_v7.rds") |> mutate(micro = as.character(microregion_code))
shares <- readRDS("exposure_shares_isic_v7.rds") |> mutate(micro = as.character(micro))
shocks <- readRDS("sectoral_shocks_isic_v7.rds")
epw_v7 <- readRDS("epw_panel_isic_v7.rds") |> mutate(micro = as.character(micro))
centro <- readRDS("micro_centroids.rds") |> mutate(micro = as.character(micro))

df_raw <- df_raw |>
  select(-any_of("delta_EPW")) |>
  left_join(epw_v7 |> filter(year != 2010) |> select(micro, year, delta_EPW = EPW),
            by = c("micro", "year"))

df <- df_raw |> filter(year != 2010, micro %in% unique(epw_v7$micro))
stopifnot("universe rule not applied upstream" =
            all(df$tradable_emp_share > 0) & !anyNA(df$manuf_share_of_tradable))

outcomes  <- c("delta_P_dalton", "delta_P_center")
ctrl_base <- c("ln_gdp_pc", "ln_pop", "tradable_emp_share")
ctrl_ext  <- c(ctrl_base, "urban_share", "educ_share", "manuf_share_of_tradable")
CSETS     <- list(base = ctrl_base, extended = ctrl_ext)
zvars     <- unique(c(outcomes, "delta_EPW", ctrl_ext))

df_scaled <- df |>
  mutate(delta_EPW_raw = delta_EPW) |>
  mutate(across(all_of(zvars), ~ as.numeric(scale(.)))) |>
  select(-any_of(c("lat", "lon", "long"))) |>
  left_join(centro, by = "micro") |> rename(long = lon)
stopifnot(!anyNA(df_scaled$lat), !anyNA(df_scaled$long))

sd_epw   <- sd(df$delta_EPW)
N_SAMPLE <- nrow(df_scaled)
N_EST    <- nobs(feols(delta_P_dalton ~ delta_EPW + ln_gdp_pc | state^year, data = df_scaled))

hdr("A. SAMPLE")
cat(sprintf("Panel rows            : %d  (%d micros x 3 first differences)\n",
            N_SAMPLE, n_distinct(df_scaled$micro)))
cat(sprintf("Estimation N          : %d  (after state x year singleton absorption)\n", N_EST))
cat(sprintf("State x year FE cells : %d\n", 78L))
cat(sprintf("Industry groups       : %d | microregions with shares: %d\n",
            n_distinct(shares$isic4), n_distinct(shares$micro)))
cat(sprintf("SD of raw dEPW        : %.6f  (scale anchor for boom/bust)\n", sd_epw))
wr(tibble(quantity = c("panel_rows", "estimation_N", "fe_cells", "micros",
                       "industry_groups", "sd_delta_EPW_raw"),
          value = c(N_SAMPLE, N_EST, 78, n_distinct(df_scaled$micro),
                    n_distinct(shares$isic4), sd_epw)), "A_sample")

# =============================================================================
# B — DESCRIPTIVE STATISTICS (raw units, estimation panel)
# =============================================================================
desc_vars <- c("delta_P_dalton", "delta_P_center", "delta_EPW",
               "P_dalton_2010", "P_center_2010",
               "ln_gdp_pc", "ln_pop", "urban_share", "educ_share",
               "manuf_share_of_tradable", "tradable_emp_share")
desc <- df |> select(all_of(desc_vars)) |>
  pivot_longer(everything(), names_to = "variable", values_to = "v") |>
  group_by(variable) |>
  summarise(N = sum(!is.na(v)), mean = mean(v), sd = sd(v), min = min(v),
            p25 = quantile(v, .25), median = median(v), p75 = quantile(v, .75),
            max = max(v), .groups = "drop") |>
  mutate(variable = factor(variable, levels = desc_vars)) |> arrange(variable)
hdr("B. DESCRIPTIVE STATISTICS (estimation panel, raw units)")
print(as.data.frame(desc), digits = 4)
wr(desc, "B_descriptives")

# treatment by year
epw_yr <- df |> group_by(year) |>
  summarise(N = n(), mean = mean(delta_EPW), sd = sd(delta_EPW), min = min(delta_EPW),
            p10 = quantile(delta_EPW, .10), median = median(delta_EPW),
            p90 = quantile(delta_EPW, .90), max = max(delta_EPW),
            pct_negative = 100 * mean(delta_EPW < 0), .groups = "drop")
cat("\n--- Treatment (delta EPW) by election year ---\n")
print(as.data.frame(epw_yr), digits = 4)
wr(epw_yr, "B_treatment_by_year")

# outcome levels by year (for the trend narrative)
pol_yr <- readRDS("dalton_panel_presidencial.rds") |>
  group_by(year) |>
  summarise(N = n(), P_dalton_mean = mean(P_dalton, na.rm = TRUE),
            P_dalton_sd = sd(P_dalton, na.rm = TRUE),
            P_center_mean = mean(P_center, na.rm = TRUE),
            P_center_sd = sd(P_center, na.rm = TRUE), .groups = "drop")
cat("\n--- Polarization index LEVELS by year (all micros) ---\n")
print(as.data.frame(pol_yr), digits = 4)
wr(pol_yr, "B_outcome_levels_by_year")

# =============================================================================
# C — BASELINE OLS, BOTH CONTROL SETS, ALL REFERENCE/SECONDARY REGIMES
# =============================================================================
W     <- ss_build_W(shares, df_scaled$micro)
g_mat <- ss_build_gmat(shocks, "g_jt", W)

hdr("C. BASELINE OLS + INFERENCE REGIMES")
base_rows <- list()
for (cs in names(CSETS)) for (oc in outcomes) {
  ctr <- CSETS[[cs]]
  m   <- feols(as.formula(paste(oc, "~ delta_EPW +", paste(ctr, collapse = " + "),
                                "| state^year")), data = df_scaled)
  s_my <- summary(m, cluster = ~ mesoregion_code^year)
  s_m  <- summary(m, cluster = ~ mesoregion_code)
  s_c2 <- summary(m, vcov = vcov_conley(lat = "lat", lon = "long", cutoff = 250))
  s_c5 <- summary(m, vcov = vcov_conley(lat = "lat", lon = "long", cutoff = 500))
  ak   <- tryCatch(ss_akm(df_scaled, oc, "delta_EPW", ctr, W), error = function(e) NULL)
  gv   <- function(o, f) if (is.null(o)) NA_real_ else tryCatch(f(o), error = function(e) NA_real_)
  pick <- function(v, k) { i <- grep(k, names(v), ignore.case = TRUE)
                           if (length(i)) as.numeric(v[i[1]]) else NA_real_ }
  base_rows[[paste(cs, oc)]] <- tibble(
    control_set = cs, outcome = oc, beta = coef(m)["delta_EPW"],
    se_meso_year   = se(s_my)["delta_EPW"],  p_meso_year   = pvalue(s_my)["delta_EPW"],
    se_meso_pooled = se(s_m)["delta_EPW"],   p_meso_pooled = pvalue(s_m)["delta_EPW"],
    se_conley250   = se(s_c2)["delta_EPW"],  p_conley250   = pvalue(s_c2)["delta_EPW"],
    se_conley500   = se(s_c5)["delta_EPW"],  p_conley500   = pvalue(s_c5)["delta_EPW"],
    se_akm  = gv(ak, \(o) pick(o$se, "AKM$|^AKM")),
    p_akm   = gv(ak, \(o) pick(o$p,  "AKM$|^AKM")),
    p_akm0  = gv(ak, \(o) pick(o$p,  "AKM0")),
    akm0_lo = gv(ak, \(o) ss_akm0_ci(o)[1]), akm0_hi = gv(ak, \(o) ss_akm0_ci(o)[2]),
    within_r2 = fitstat(m, "wr2")$wr2, N = nobs(m))
}
baseline <- bind_rows(base_rows)
print(as.data.frame(baseline), digits = 3)
wr(baseline, "C_baseline_all_regimes")

# =============================================================================
# D — ASYMMETRIC DECOMPOSITION (magnitude coding), BOTH CONTROL SETS
# =============================================================================
hdr("D. ASYMMETRIC BOOM/BUST DECOMPOSITION")
df_asym <- df_scaled |>
  mutate(epw_boom = pmax( delta_EPW_raw, 0) / sd_epw,
         epw_bust = pmax(-delta_EPW_raw, 0) / sd_epw)
stopifnot(all(df_asym$epw_boom >= 0), all(df_asym$epw_bust >= 0))

dec_rows <- list(); dec_mods <- list()
for (cs in names(CSETS)) for (oc in outcomes) {
  ctr <- CSETS[[cs]]
  m <- feols(as.formula(paste(oc, "~ epw_boom + epw_bust +",
                              paste(ctr, collapse = " + "), "| state^year")),
             data = df_asym)
  s <- summary(m, cluster = ~ mesoregion_code^year)
  dec_mods[[paste(cs, oc)]] <- m
  dec_rows[[paste(cs, oc)]] <- tibble(
    control_set = cs, outcome = oc,
    beta_boom = coef(m)["epw_boom"], se_boom = se(s)["epw_boom"], p_boom = pvalue(s)["epw_boom"],
    beta_bust = coef(m)["epw_bust"], se_bust = se(s)["epw_bust"], p_bust = pvalue(s)["epw_bust"],
    within_r2 = fitstat(m, "wr2")$wr2, N = nobs(m),
    # model Prop. 1: b_bust > 0 and b_bust >= |b_boom|
    sign_match = coef(m)["epw_bust"] > 0,
    magnitude_match = coef(m)["epw_bust"] >= abs(coef(m)["epw_boom"]))
}
decomp <- bind_rows(dec_rows)
print(as.data.frame(decomp), digits = 3)
wr(decomp, "D_decomposition")

# full coefficient tables (all controls) for transcription
coef_tbl <- imap_dfr(dec_mods, function(m, nm) {
  s <- summary(m, cluster = ~ mesoregion_code^year)
  tibble(spec = nm, term = names(coef(m)), beta = as.numeric(coef(m)),
         se = as.numeric(se(s)), t = as.numeric(tstat(s)), p = as.numeric(pvalue(s)))
})
wr(coef_tbl, "D_decomposition_full_coefficients")

# =============================================================================
# E — RANDOMIZATION INFERENCE (primary regime), B = 9,999
#     One industry permutation per draw, applied jointly across years so each
#     industry's shock PATH is preserved. 12 statistics per draw.
# =============================================================================
B <- 9999
year_chr <- as.character(df_scaled$year)
yr_idx   <- cbind(seq_len(nrow(W)), match(year_chr, c("2014", "2018", "2022")))
epw_star <- function(perm) {
  gs <- g_mat[perm, , drop = FALSE]
  sapply(c("2014", "2018", "2022"), \(t) as.numeric(W %*% gs[, t]))[yr_idx]
}
f_pool <- lapply(CSETS, \(ctr) lapply(outcomes, \(oc)
  as.formula(paste(oc, "~ epw_s +", paste(ctr, collapse = " + "), "| state^year"))))
f_dec  <- lapply(CSETS, \(ctr) lapply(outcomes, \(oc)
  as.formula(paste(oc, "~ boom_s + bust_s +", paste(ctr, collapse = " + "), "| state^year"))))

ri_draw <- function(perm) {
  e <- epw_star(perm)
  d <- df_scaled |> mutate(epw_s = e / sd_epw,
                           boom_s = pmax( e, 0) / sd_epw,
                           bust_s = pmax(-e, 0) / sd_epw)
  out <- numeric(0)
  for (ci in seq_along(CSETS)) for (oi in seq_along(outcomes)) {
    cs <- names(CSETS)[ci]; oc <- outcomes[oi]
    bp <- coef(feols(f_pool[[ci]][[oi]], data = d, lean = TRUE))["epw_s"]
    bd <- coef(feols(f_dec[[ci]][[oi]],  data = d, lean = TRUE))[c("boom_s", "bust_s")]
    out <- c(out, setNames(c(bp, bd[1], bd[2]),
                           paste0(c("pooled.", "boom.", "bust."), cs, ".", oc)))
  }
  out
}
cat("\nRunning RI with B =", B, "... (12 statistics per draw)\n")
t0 <- Sys.time()
stars <- t(replicate(B, ri_draw(sample(nrow(g_mat)))))
cat("RI elapsed:", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")

hat <- c()
for (cs in names(CSETS)) for (oc in outcomes) {
  m_p <- feols(as.formula(paste(oc, "~ delta_EPW +", paste(CSETS[[cs]], collapse = " + "),
                                "| state^year")), data = df_scaled)
  m_d <- dec_mods[[paste(cs, oc)]]
  hat <- c(hat, setNames(c(coef(m_p)["delta_EPW"], coef(m_d)["epw_boom"], coef(m_d)["epw_bust"]),
                         paste0(c("pooled.", "boom.", "bust."), cs, ".", oc)))
}
ri <- tibble(statistic = names(hat), beta_hat = as.numeric(hat)) |>
  mutate(ri_p = map2_dbl(statistic, beta_hat, \(s, h) ss_ri_p(stars[, s], h)),
         ri_sd_null = map_dbl(statistic, \(s) sd(stars[, s])),
         null_q025 = map_dbl(statistic, \(s) quantile(stars[, s], .025)),
         null_q975 = map_dbl(statistic, \(s) quantile(stars[, s], .975))) |>
  separate(statistic, into = c("coefficient", "control_set", "outcome"),
           sep = "\\.", extra = "merge")
hdr("E. DESIGN-BASED RANDOMIZATION INFERENCE (B = 9,999)")
print(as.data.frame(ri), digits = 3)
wr(ri, "E_randomization_inference")
saveRDS(stars, file.path(RDIR, "E_ri_null_draws.rds"))

# =============================================================================
# F — ROTEMBERG WEIGHTS / EFFECTIVE NUMBER OF SHOCKS
# =============================================================================
hdr("F. ROTEMBERG WEIGHTS AND SHOCK CONCENTRATION")
rot <- ss_rotemberg(df_scaled, W, g_mat, "delta_EPW_raw", ctrl_base)
effn <- ss_eff_n(rot)
conc <- rot |> group_by(year) |>
  summarise(hhi_abs_alpha = sum((abs(alpha) / sum(abs(alpha)))^2),
            eff_n = 1 / hhi_abs_alpha,
            top1_share = max(abs(alpha)) / sum(abs(alpha)),
            top3_share = sum(sort(abs(alpha), decreasing = TRUE)[1:3]) / sum(abs(alpha)),
            n_negative_alpha = sum(alpha < 0), .groups = "drop")
print(as.data.frame(conc), digits = 4)
top_alpha <- rot |> group_by(year) |> slice_max(abs(alpha), n = 8) |>
  arrange(year, desc(abs(alpha)))
cat("\n--- Top-8 industries by |Rotemberg alpha|, by year ---\n")
print(as.data.frame(top_alpha), digits = 4)
wr(conc, "F_rotemberg_concentration"); wr(rot, "F_rotemberg_weights_full")
wr(top_alpha, "F_rotemberg_top8")

# =============================================================================
# G — EXOGENEITY BATTERY (from 03c) + BALANCE + PLACEBO
# =============================================================================
hdr("G. EXOGENEITY, BALANCE AND CLUSTER-SE OVER-REJECTION (03c)")
ex <- readRDS("shock_exogeneity_results_v1.rds")
for (nm in c("balance", "balance_mechanical", "placebo", "battery", "stability",
             "pretrend", "eff_shocks")) {
  cat("\n---", nm, "---\n"); print(as.data.frame(ex[[nm]]), digits = 4)
  wr(as_tibble(ex[[nm]]), paste0("G_", nm))
}

# =============================================================================
# H — EXTERNAL-DEMAND INSTRUMENT: FIRST STAGE AND 2SLS
#     03b builds three instruments and reports an industry-level first stage but
#     never estimates 2SLS. Done here; z_CHN is the only one with a usable F.
# =============================================================================
hdr("H. INSTRUMENTAL-VARIABLES ESTIMATION (external demand, 03b)")
iv <- readRDS("epw_iv_panel_v1.rds") |> mutate(micro = as.character(micro)) |>
  filter(year != 2010) |> select(micro, year, EPW_IV_A, EPW_IV_B, EPW_IV_CHN)
d_iv <- df_scaled |> left_join(iv, by = c("micro", "year"))
ivs  <- c("EPW_IV_A", "EPW_IV_B", "EPW_IV_CHN")
cat("IV coverage (non-missing):",
    paste(sprintf("%s=%d", ivs, colSums(!is.na(d_iv[ivs]))), collapse = " | "), "\n")
d_iv <- d_iv |> mutate(across(all_of(ivs), ~ as.numeric(scale(.))))

fs_rows <- list(); iv_rows <- list()
for (z in ivs) {
  fs <- feols(as.formula(paste("delta_EPW ~", z, "+", paste(ctrl_base, collapse = " + "),
                               "| state^year")), data = d_iv)
  fss <- summary(fs, cluster = ~ mesoregion_code^year)
  fs_rows[[z]] <- tibble(instrument = z, beta = coef(fs)[z], se = se(fss)[z],
                         t = tstat(fss)[z], F_wald = tstat(fss)[z]^2,
                         within_r2 = fitstat(fs, "wr2")$wr2, N = nobs(fs))
  for (oc in outcomes) {
    m2 <- feols(as.formula(paste(oc, "~", paste(ctrl_base, collapse = " + "),
                                 "| state^year | delta_EPW ~", z)), data = d_iv)
    s2 <- summary(m2, cluster = ~ mesoregion_code^year)
    # Kleibergen-Paap MUST be computed under the SAME cluster structure used for
    # inference. fitstat()'s default uses the model's stored (homoskedastic)
    # vcov, which inflates the statistic by 1-2 orders of magnitude here and
    # would misrepresent a weak instrument as a strong one.
    kp <- tryCatch(fitstat(m2, "ivwald", cluster = ~ mesoregion_code^year)[[1]]$stat,
                   error = function(e) NA_real_)
    iv_rows[[paste(z, oc)]] <- tibble(
      instrument = z, outcome = oc, beta_2sls = coef(m2)["fit_delta_EPW"],
      se = se(s2)["fit_delta_EPW"], t = tstat(s2)["fit_delta_EPW"],
      p = pvalue(s2)["fit_delta_EPW"], KP_F_clustered = kp, N = nobs(m2))
  }
}
first_stage <- bind_rows(fs_rows); iv_est <- bind_rows(iv_rows)
cat("\n--- Regional FIRST STAGE: dEPW ~ z + controls | state^year ---\n")
print(as.data.frame(first_stage), digits = 4)
cat("\n--- 2SLS ---\n"); print(as.data.frame(iv_est), digits = 4)
cat("\nNOTE: interpret only instruments whose first-stage F clears conventional\n")
cat("thresholds; AKM0 in section C is the weak-identification-robust complement.\n")
wr(first_stage, "H_first_stage"); wr(iv_est, "H_2sls")

# reduced form (outcome on instrument directly) — immune to weak first stage.
# Reported WITH and WITHOUT the 2010 baseline: for delta_P_center the outcome is
# a near-deterministic function of that baseline in 2018 and 2022 (see 09), so a
# reduced form that omits it inherits the same mechanical channel as OLS.
rf_rows <- list()
for (z in ivs) for (oc in outcomes) for (withbase in c(FALSE, TRUE)) {
  bl  <- if (oc == "delta_P_center") "P_center_2010" else "P_dalton_2010"
  ctr <- c(ctrl_base, if (withbase) bl)
  m <- feols(as.formula(paste(oc, "~", z, "+", paste(ctr, collapse = " + "),
                              "| state^year")), data = d_iv)
  s <- summary(m, cluster = ~ mesoregion_code^year)
  rf_rows[[paste(z, oc, withbase)]] <- tibble(
    instrument = z, outcome = oc, baseline_control = withbase, beta = coef(m)[z],
    se = se(s)[z], t = tstat(s)[z], p = pvalue(s)[z], N = nobs(m))
}
reduced_form <- bind_rows(rf_rows)
cat("\n--- REDUCED FORM (outcome on instrument), with/without 2010 baseline ---\n")
print(as.data.frame(reduced_form), digits = 4)
wr(reduced_form, "H_reduced_form")

# =============================================================================
# I — HEADLINE SUMMARY
# =============================================================================
hdr("I. HEADLINE SUMMARY")
headline <- decomp |>
  select(control_set, outcome, beta_boom, se_boom, beta_bust, se_bust, N) |>
  left_join(ri |> filter(coefficient == "bust") |> select(control_set, outcome, ri_p_bust = ri_p),
            by = c("control_set", "outcome")) |>
  left_join(ri |> filter(coefficient == "boom") |> select(control_set, outcome, ri_p_boom = ri_p),
            by = c("control_set", "outcome")) |>
  left_join(baseline |> select(control_set, outcome, beta_pooled = beta,
                               se_pooled = se_meso_year), by = c("control_set", "outcome")) |>
  left_join(ri |> filter(coefficient == "pooled") |> select(control_set, outcome,
                                                            ri_p_pooled = ri_p),
            by = c("control_set", "outcome")) |>
  mutate(eff_n_mean = mean(conc$eff_n))
print(as.data.frame(headline), digits = 3)
wr(headline, "I_headline")

cat("\n\nAll tables written to", normalizePath(RDIR), "\n")
cat("\n--- PROVENANCE ---\n")
cat("SHARE_DENOM =", SHARE_DENOM, "| B_RI =", B, "| seed = 2026\n")
print(sessionInfo())
sink(); close(log_con)
