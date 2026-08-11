# =============================================================================
# H2 — baseline reproduction check.
# Re-estimates Table 3 (both panels, both outcomes, both control sets) from the
# shared bootstrap and compares to the published values in main.tex. Also
# recomputes the symmetry Wald test and re-reads the STORED RI placebo matrices
# (the 9,999-draw distributions from 07) rather than re-permuting, so this check
# is fast and tests the estimation frame, not the RNG.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("H2")

df_asym <- df_scaled |>
  mutate(epw_boom = pmax( delta_EPW_raw, 0) / sd_epw,
         epw_bust = pmax(-delta_EPW_raw, 0) / sd_epw)

fit_pooled <- function(oc, ctrls)
  feols(as.formula(paste(oc, "~ delta_EPW +", paste(ctrls, collapse = " + "),
                         "| state^year")), data = df_scaled,
        cluster = ~ mesoregion_code^year)
fit_decomp <- function(oc, ctrls)
  feols(as.formula(paste(oc, "~ epw_boom + epw_bust +", paste(ctrls, collapse = " + "),
                         "| state^year")), data = df_asym,
        cluster = ~ mesoregion_code^year)

grid <- expand_grid(outcome = outcomes, ctrls = c("base", "ext"))
ctrl_of <- function(k) if (k == "base") ctrl_base else ctrl_ext

res <- pmap_dfr(grid, function(outcome, ctrls) {
  mp <- fit_pooled(outcome, ctrl_of(ctrls))
  md <- fit_decomp(outcome, ctrl_of(ctrls))
  b  <- coef(md)[c("epw_boom", "epw_bust")]
  V  <- vcov(md)[c("epw_boom", "epw_bust"), c("epw_boom", "epw_bust")]
  cc <- sum(b); se <- sqrt(sum(V))
  dof <- fixest::degrees_freedom(md, type = "t")
  bind_rows(
    tibble(outcome, ctrls, coefficient = "pooled",
           beta = coef(mp)[["delta_EPW"]], se = se(mp)[["delta_EPW"]], n = nobs(mp)),
    tibble(outcome, ctrls, coefficient = "boom",
           beta = b[["epw_boom"]], se = se(md)[["epw_boom"]], n = nobs(md)),
    tibble(outcome, ctrls, coefficient = "bust",
           beta = b[["epw_bust"]], se = se(md)[["epw_bust"]], n = nobs(md)),
    tibble(outcome, ctrls, coefficient = "symmetry_p",
           beta = cc, se = se, n = nobs(md)) |>
      mutate(p_sym = 2 * pt(-abs(cc / se), df = dof))
  )
})

# ---- attach RI p-values from the stored placebo matrices --------------------
ri_files <- c(base = sprintf("output/ri_beta_distribution_%s_base.rds", SHARE_DENOM),
              ext  = sprintf("output/ri_beta_distribution_%s_ext.rds",  SHARE_DENOM))
ri_key <- c("delta_P_dalton_pooled" = "pooled_D", "delta_P_center_pooled" = "pooled_N",
            "delta_P_dalton_boom"   = "boom_D",   "delta_P_center_boom"   = "boom_N",
            "delta_P_dalton_bust"   = "bust_D",   "delta_P_center_bust"   = "bust_N")

res <- res |> rowwise() |>
  mutate(ri_p = {
    k <- paste0(outcome, "_", coefficient)
    if (!k %in% names(ri_key) || !file.exists(ri_files[[ctrls]])) NA_real_
    else {
      m <- readRDS(ri_files[[ctrls]])
      p_ri(m[, ri_key[[k]]], beta)
    }
  },
  ri_placebo_sd = {
    k <- paste0(outcome, "_", coefficient)
    if (!k %in% names(ri_key) || !file.exists(ri_files[[ctrls]])) NA_real_
    else sd(readRDS(ri_files[[ctrls]])[, ri_key[[k]]])
  }) |> ungroup() |>
  mutate(sd_ratio = ri_placebo_sd / se)

# ---- published Table 3 values (main.tex) for the diff -----------------------
published <- tribble(
  ~outcome,         ~ctrls, ~coefficient, ~pub_beta, ~pub_se,
  "delta_P_dalton", "base", "pooled",      0.001,  0.005,
  "delta_P_dalton", "ext",  "pooled",     -0.003,  0.005,
  "delta_P_center", "base", "pooled",      0.002,  0.009,
  "delta_P_center", "ext",  "pooled",      0.001,  0.009,
  "delta_P_dalton", "base", "boom",        0.003,  0.007,
  "delta_P_dalton", "ext",  "boom",        0.002,  0.007,
  "delta_P_dalton", "base", "bust",        0.005,  0.009,
  "delta_P_dalton", "ext",  "bust",        0.015,  0.008,
  "delta_P_center", "base", "boom",       -0.013,  0.008,
  "delta_P_center", "ext",  "boom",       -0.018,  0.009,
  "delta_P_center", "base", "bust",       -0.041,  0.015,
  "delta_P_center", "ext",  "bust",       -0.047,  0.015
)

cmp <- res |> inner_join(published, by = c("outcome", "ctrls", "coefficient")) |>
  mutate(d_beta = round(beta, 3) - pub_beta, d_se = round(se, 3) - pub_se,
         match = abs(d_beta) < 1e-9 & abs(d_se) < 1e-9)

cat("\n=== H2: Table 3 reproduction ===\n")
print(as.data.frame(cmp |> select(outcome, ctrls, coefficient, beta, pub_beta,
                                  se, pub_se, ri_p, sd_ratio, match)), digits = 4)
cat(sprintf("\nAll 12 treatment coefficients match published (3 dp): %s\n",
            all(cmp$match)))
cat(sprintf("Estimation N: %s (published 1,668)\n", paste(unique(res$n), collapse = "/")))
cat("\nSymmetry Wald p:\n")
print(as.data.frame(res |> filter(coefficient == "symmetry_p") |>
                      select(outcome, ctrls, sum_b = beta, se, p_sym)), digits = 4)

write_csv(res, file.path(OUT, "H2_table3_reproduction.csv"))
write_csv(cmp, file.path(OUT, "H2_published_diff.csv"))
saveRDS(list(res = res, cmp = cmp), file.path(OUT, "H2.rds"))
cat("\n[H2] wrote", OUT, "\n")
