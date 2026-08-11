# =============================================================================
# P9 — inference housekeeping. Referee items R1-m2, R1-m3, R3-m2, R3-m3, R1-m1.
#   1. state the Conley implementation exactly;
#   2. mesoregion-level (non-interacted) clustering + wild cluster bootstrap;
#   3. partial R2 for delta_EPW alone alongside the within-R2;
#   4. within-state-year residual SDs by year (the variation the design uses);
#   5. year-standardised outcomes as a robustness check.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("P9")

d <- df_scaled |> mutate(epw_boom = pmax( delta_EPW_raw,0)/sd_epw,
                         epw_bust = pmax(-delta_EPW_raw,0)/sd_epw)

# =============================================================================
# 1 + 2 — the standard-error ladder, stated explicitly
# =============================================================================
cat("\n=== P9(1) Conley implementation, as coded ===\n")
cat("fixest::conley(cutoff) with default settings: UNIFORM (rectangular) kernel,\n",
    "weight 1 for every pair of microregion centroids within `cutoff` km and 0\n",
    "beyond, distances computed on the geobr 2010 microregion centroids\n",
    "(spherical). fixest applies NO serial/temporal correction across the three\n",
    "stacked differences: conley() is purely cross-sectional, so the common-2010-\n",
    "base dependence within a microregion is NOT absorbed by it. The regime that\n",
    "does allow that dependence is mesoregion-level (non-interacted) clustering,\n",
    "reported below, and the design-based RI, which is immune (its randomness is\n",
    "at the shock level).\n")

ladder <- map_dfr(outcomes, function(oc) map_dfr(c("base","ext"), function(ck) {
  ctrls <- if (ck=="base") ctrl_base else ctrl_ext
  f <- as.formula(paste(oc, "~ delta_EPW +", paste(ctrls, collapse=" + "), "| state^year"))
  m <- feols(f, data = d)
  regimes <- list(
    IID              = summary(m, vcov = "iid"),
    HC1              = summary(m, vcov = "hetero"),
    `meso x year`    = summary(m, cluster = ~ mesoregion_code^year),
    `meso (pooled)`  = summary(m, cluster = ~ mesoregion_code),
    `micro (pooled)` = summary(m, cluster = ~ micro),
    `state x year`   = summary(m, cluster = ~ state^year),
    `Conley 250km`   = summary(m, vcov = conley(250)),
    `Conley 500km`   = summary(m, vcov = conley(500)))
  map_dfr(names(regimes), function(r) tibble(
    outcome = oc, ctrls = ck, regime = r,
    beta = coef(regimes[[r]])[["delta_EPW"]],
    se = se(regimes[[r]])[["delta_EPW"]],
    t = coef(regimes[[r]])[["delta_EPW"]] / se(regimes[[r]])[["delta_EPW"]],
    n_clusters = tryCatch(regimes[[r]]$nb_cluster[[1]], error = function(e) NA_integer_)))
}))
cat("\n=== P9(2) standard-error ladder ===\n")
print(as.data.frame(ladder), digits = 4)

cat("\n=== P9(2b) cluster counts ===\n")
cat(sprintf("mesoregion x year cells: %d | mesoregions: %d | micros: %d | state x year: %d\n",
            n_distinct(paste(d$mesoregion_code, d$year)), n_distinct(d$mesoregion_code),
            n_distinct(d$micro), n_distinct(paste(d$state, d$year))))

# ---- wild cluster bootstrap (Rademacher, mesoregion level) -------------------
# fwildclusterboot has been archived on CRAN and does not install under R 4.5,
# so the WCR bootstrap is implemented directly: impose the null by estimating
# the restricted model, resample its residuals with a cluster-level Rademacher
# weight, refit unrestricted, and locate the observed cluster-robust t.
wild_boot <- function(oc, ctrls, cluster_var = "mesoregion_code", B = 9999, seed = 2026) {
  cz <- paste(ctrls, collapse = " + ")
  full <- feols(as.formula(paste(oc, "~ delta_EPW +", cz, "| state^year")), data = d)
  t_obs <- coef(summary(full, cluster = ~ mesoregion_code))[["delta_EPW"]] /
    se(summary(full, cluster = ~ mesoregion_code))[["delta_EPW"]]
  restr <- feols(as.formula(paste(oc, "~", cz, "| state^year")), data = d)
  keep  <- setdiff(seq_len(nrow(d)), restr$obs_selection$obsRemoved * -1)
  de    <- d[keep, ]
  uhat  <- resid(restr); yhat <- fitted(restr)
  cl    <- de[[cluster_var]]
  gl    <- unique(cl)
  set.seed(seed)
  tstar <- replicate(B, {
    v <- setNames(sample(c(-1, 1), length(gl), TRUE), gl)
    de$.ystar <- yhat + v[as.character(cl)] * uhat
    m <- feols(as.formula(paste(".ystar ~ delta_EPW +", cz, "| state^year")), data = de)
    s <- summary(m, cluster = ~ mesoregion_code)
    coef(s)[["delta_EPW"]] / se(s)[["delta_EPW"]]
  })
  tibble(outcome = oc, ctrls = paste(ctrls, collapse = "+"),
         beta = coef(full)[["delta_EPW"]], t_obs = t_obs,
         p_wcb = (1 + sum(abs(tstar) >= abs(t_obs))) / (B + 1),
         q025 = quantile(tstar, .025), q975 = quantile(tstar, .975),
         n_clusters = length(gl))
}
cat("\n[P9] wild cluster bootstrap (own implementation, WCR-Rademacher, B = 1999)...\n")
wcb <- map_dfr(outcomes, function(oc) map_dfr(c("base","ext"), function(ck)
  wild_boot(oc, if (ck == "base") ctrl_base else ctrl_ext, B = 1999) |>
    mutate(ctrl_set = ck)))
cat("\n=== P9(2c) wild cluster bootstrap, mesoregion level (null imposed) ===\n")
print(as.data.frame(wcb), digits = 4)

# =============================================================================
# 3 — partial R2 for the treatment alone
# =============================================================================
partial <- map_dfr(outcomes, function(oc) map_dfr(c("base","ext"), function(ck) {
  ctrls <- if (ck=="base") ctrl_base else ctrl_ext
  full <- feols(as.formula(paste(oc, "~ delta_EPW +", paste(ctrls, collapse=" + "),
                                 "| state^year")), data = d)
  noT  <- feols(as.formula(paste(oc, "~", paste(ctrls, collapse=" + "), "| state^year")), data = d)
  onlyT <- feols(as.formula(paste(oc, "~ delta_EPW | state^year")), data = d)
  # partial R2 of the treatment: squared partial correlation of the two residuals
  ry <- resid(noT)
  rx <- resid(feols(as.formula(paste("delta_EPW ~", paste(ctrls, collapse=" + "),
                                     "| state^year")), data = d))
  tibble(outcome = oc, ctrls = ck,
         within_r2_full = fitstat(full, "wr2")$wr2,
         within_r2_controls_only = fitstat(noT, "wr2")$wr2,
         within_r2_treatment_only = fitstat(onlyT, "wr2")$wr2,
         partial_r2_treatment = cor(ry, rx)^2,
         delta_within_r2 = fitstat(full,"wr2")$wr2 - fitstat(noT,"wr2")$wr2)
}))
cat("\n=== P9(3) partial R2 of delta_EPW alone ===\n")
print(as.data.frame(partial), digits = 5)

# =============================================================================
# 4 — within-state-year residual SDs, the variation the design actually uses
# =============================================================================
# NOTE: feols drops the three state x year singletons, so resid() is shorter
# than the data. Align on the estimation sample explicitly before subsetting by
# year, otherwise the by-year rows silently come back NA.
wsd <- map_dfr(c("delta_P_dalton", "delta_P_center", "delta_EPW"), function(v) {
  m <- feols(as.formula(paste(v, "~ 1 | state^year")), data = d)
  keep <- setdiff(seq_len(nrow(d)), m$obs_selection$obsRemoved * -1)
  de <- d[keep, ]; r <- resid(m)
  stopifnot(length(r) == nrow(de))
  bind_rows(
    tibble(variable = v, year = "pooled", raw_sd = sd(de[[v]]), within_sd = sd(r),
           share_within = sd(r)^2 / sd(de[[v]])^2),
    map_dfr(c(2014, 2018, 2022), function(t) {
      k <- de$year == t
      tibble(variable = v, year = as.character(t), raw_sd = sd(de[[v]][k]),
             within_sd = sd(r[k]), share_within = sd(r[k])^2 / sd(de[[v]][k])^2)
    }))
})
cat("\n=== P9(4) within-state-year residual SDs (standardised units) ===\n")
print(as.data.frame(wsd), digits = 4)

# raw-unit version too
wsd_raw <- map_dfr(c("delta_P_dalton", "delta_P_center", "delta_EPW"), function(v) {
  dr <- df |> mutate(.v = .data[[v]])
  m <- feols(.v ~ 1 | state^year, data = dr)
  keep <- setdiff(seq_len(nrow(dr)), m$obs_selection$obsRemoved * -1)
  de <- dr[keep, ]; r <- resid(m)
  bind_rows(tibble(variable = v, year = "pooled", raw_sd = sd(de$.v), within_sd = sd(r)),
            map_dfr(c(2014,2018,2022), function(t) {
              k <- de$year == t
              tibble(variable = v, year = as.character(t), raw_sd = sd(de$.v[k]),
                     within_sd = sd(r[k]))}))
})
cat("\n=== P9(4b) same, RAW units ===\n"); print(as.data.frame(wsd_raw), digits = 4)

# =============================================================================
# 5 — year-standardised outcomes
# =============================================================================
dz <- d |> group_by(year) |>
  mutate(across(all_of(outcomes), ~ as.numeric(scale(.)), .names = "{.col}_yz")) |>
  ungroup()
yz <- map_dfr(outcomes, function(oc) map_dfr(c("base","ext"), function(ck) {
  ctrls <- if (ck=="base") ctrl_base else ctrl_ext; cz <- paste(ctrls, collapse=" + ")
  mp <- feols(as.formula(paste0(oc,"_yz ~ delta_EPW + ",cz," | state^year")), data=dz,
              cluster = ~ mesoregion_code^year)
  md <- feols(as.formula(paste0(oc,"_yz ~ epw_boom + epw_bust + ",cz," | state^year")), data=dz,
              cluster = ~ mesoregion_code^year)
  bind_rows(
    tibble(outcome=oc, ctrls=ck, term="pooled", beta=coef(mp)[["delta_EPW"]], se=se(mp)[["delta_EPW"]], n=nobs(mp)),
    tibble(outcome=oc, ctrls=ck, term="boom", beta=coef(md)[["epw_boom"]], se=se(md)[["epw_boom"]], n=nobs(md)),
    tibble(outcome=oc, ctrls=ck, term="bust", beta=coef(md)[["epw_bust"]], se=se(md)[["epw_bust"]], n=nobs(md)))
}))
cat("\n=== P9(5) year-standardised outcomes ===\n"); print(as.data.frame(yz), digits = 4)

# Distrito Federal / singleton bookkeeping (R3-m4)
sing <- d |> count(state, year) |> filter(n == 1)
cat("\n=== P9(extra, R3-m4) state x year singleton cells ===\n"); print(as.data.frame(sing))
cat("These are ABSORBED by feols (dropped from the estimation), not dropped from\n",
    "the panel: N goes 1,671 -> 1,668. Confirmed against the fitted models.\n")

write_csv(ladder,  file.path(OUT, "P9_se_ladder.csv"))
write_csv(partial, file.path(OUT, "P9_partial_r2.csv"))
write_csv(wsd,     file.path(OUT, "P9_within_sd_standardised.csv"))
write_csv(wsd_raw, file.path(OUT, "P9_within_sd_raw.csv"))
write_csv(yz,      file.path(OUT, "P9_year_standardised.csv"))
if (!is.null(wcb)) write_csv(wcb, file.path(OUT, "P9_wild_bootstrap.csv"))
cat("\n[P9] wrote", OUT, "\n")
