# =============================================================================
# packet_I/I1_canary.R  —  [I-1] CANARY. Nothing in this packet is believed
# until this passes.
#
# Reproduces the PUBLISHED Table 3 under V0 (the ideology join exactly as
# 02_polarization_indices.R performs it today), in the pattern of
# revision/H2_baseline_repro.R: 12 treatment coefficients and 12 standard errors
# at three decimals, N = 1,668. Adds one check H2 does not make, because Packet I
# moves the OUTCOME rather than the treatment: that the outcome rebuilt from the
# raw vote panel through V0 -> index -> 2010 differencing -> standardisation is
# numerically identical to the outcome carried in df_estimation_v7.rds. That
# identity is what licenses estimating the ladder in-script instead of
# overwriting the canonical 02/06 artefacts ([I-7]).
#
# If either half fails, STOP and report.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/packet_I/I0_setup.R")
OUT <- I_DIR("I1")
log_con <- file(file.path(OUT, "I1_canary_log.txt"), open = "wt"); sink(log_con, split = TRUE)
cat("=== I1 canary:", format(Sys.time()), "===\n")
cat("SHARE_DENOM =", SHARE_DENOM, "| N_SAMPLE =", N_SAMPLE, "\n\n")

# =============================================================================
# PART A — Table 3, reproduced from the shared estimation frame
# =============================================================================
df_asym <- df_scaled |>
  mutate(epw_boom = pmax( delta_EPW_raw, 0) / sd_epw,
         epw_bust = pmax(-delta_EPW_raw, 0) / sd_epw)

fit_pooled <- function(oc, ctrls, d = df_scaled)
  feols(as.formula(paste(oc, "~ delta_EPW +", paste(ctrls, collapse = " + "),
                         "| state^year")), data = d, cluster = ~ mesoregion_code^year)
fit_decomp <- function(oc, ctrls, d = df_asym)
  feols(as.formula(paste(oc, "~ epw_boom + epw_bust +", paste(ctrls, collapse = " + "),
                         "| state^year")), data = d, cluster = ~ mesoregion_code^year)

ctrl_of <- function(k) if (k == "base") ctrl_base else ctrl_ext
res <- pmap_dfr(expand_grid(outcome = outcomes, ctrls = c("base", "ext")),
                function(outcome, ctrls) {
  mp <- fit_pooled(outcome, ctrl_of(ctrls)); md <- fit_decomp(outcome, ctrl_of(ctrls))
  b  <- coef(md)[c("epw_boom", "epw_bust")]
  V  <- vcov(md)[c("epw_boom", "epw_bust"), c("epw_boom", "epw_bust")]
  cc <- sum(b); s <- sqrt(sum(V))
  bind_rows(
    tibble(outcome, ctrls, coefficient = "pooled",
           beta = coef(mp)[["delta_EPW"]], se = se(mp)[["delta_EPW"]], n = nobs(mp)),
    tibble(outcome, ctrls, coefficient = "boom",
           beta = b[["epw_boom"]], se = se(md)[["epw_boom"]], n = nobs(md)),
    tibble(outcome, ctrls, coefficient = "bust",
           beta = b[["epw_bust"]], se = se(md)[["epw_bust"]], n = nobs(md)),
    tibble(outcome, ctrls, coefficient = "symmetry_p", beta = cc, se = s, n = nobs(md),
           p_sym = 2 * pt(-abs(cc / s), df = fixest::degrees_freedom(md, type = "t"))))
})

# published Table 3 (main_anpec.tex), identical to revision/H2's tribble
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
  "delta_P_center", "ext",  "bust",       -0.047,  0.015)

# [D-69], already on the record: ONE printed cell is a double-rounding artefact
# of the manuscript, not of the pipeline. delta_P_center / base / bust estimates
# -0.04047594, which is -0.0405 at 4 dp (RESULTS_MANIFEST) and was rounded a
# second time to -0.041 in print; a direct round gives -0.040. The canary is
# evaluated against the CORRECTED table and reports both, so that this packet
# neither re-flags a known manuscript defect as a reproduction failure nor
# silently relaxes the criterion.
published <- published |>
  mutate(pub_beta_corrected = if_else(outcome == "delta_P_center" &
                                        ctrls == "base" & coefficient == "bust",
                                      -0.040, pub_beta),
         D69 = pub_beta_corrected != pub_beta)

cmp <- res |> inner_join(published, by = c("outcome", "ctrls", "coefficient")) |>
  mutate(d_beta_printed = round(beta, 3) - pub_beta,
         d_beta         = round(beta, 3) - pub_beta_corrected,
         d_se           = round(se, 3) - pub_se,
         match_printed  = abs(d_beta_printed) < 1e-9 & abs(d_se) < 1e-9,
         match          = abs(d_beta) < 1e-9 & abs(d_se) < 1e-9)

cat("=== I1(A) Table 3 reproduction under V0 ===\n")
print(as.data.frame(cmp |> select(outcome, ctrls, coefficient, beta, pub_beta,
                                  pub_beta_corrected, se, pub_se, match)), digits = 4)
cat(sprintf("\n12 coefficients AND 12 SEs match published at 3 dp: %s (%d of 12)\n",
            all(cmp$match_printed), sum(cmp$match_printed)))
cat(sprintf("...against the [D-69]-corrected table:              %s (%d of 12)\n",
            all(cmp$match), sum(cmp$match)))
if (any(cmp$D69))
  cat(sprintf("[D-69] cell delta_P_center/base/bust: estimated %.8f | printed %.3f | correct %.3f\n",
              cmp$beta[cmp$D69], cmp$pub_beta[cmp$D69], cmp$pub_beta_corrected[cmp$D69]))
cat(sprintf("Estimation N: %s (published 1,668)\n", paste(unique(res$n), collapse = "/")))
cat("\nSymmetry Wald p:\n")
print(as.data.frame(res |> filter(coefficient == "symmetry_p") |>
                      select(outcome, ctrls, sum_b = beta, se, p_sym)), digits = 4)

# =============================================================================
# PART B — the 02 -> 06 chain, rebuilt from raw votes under V0
# =============================================================================
pi_V0  <- attach_ideo(votes_pres, build_ideo("V0"))
idx_V0 <- build_index(pi_V0)
dlt_V0 <- build_delta(idx_V0)

cat("\n=== I1(B) V0 rebuild of the presidential index ===\n")
cat(sprintf("max |sum_p v_rpt - 1| over %d micro-year cells = %.3e\n",
            nrow(idx_V0), max(abs(idx_V0$sum_v - 1))))
print(as.data.frame(coverage_by_year(pi_V0)), digits = 6)

# canonical panel, for comparison
dal_canon <- readRDS(paths$dalton_pres) |>
  mutate(microregion_code = as.integer(microregion_code))
lvl <- idx_V0 |> select(microregion_code, year, P_dalton, P_center) |>
  inner_join(dal_canon |> select(microregion_code, year,
                                 P_dalton_c = P_dalton, P_center_c = P_center),
             by = c("microregion_code", "year"))
cat(sprintf("levels vs dalton_panel_presidencial.rds: n = %d | max|dP^D| = %.3e | max|dP^N| = %.3e\n",
            nrow(lvl), max(abs(lvl$P_dalton - lvl$P_dalton_c)),
            max(abs(lvl$P_center - lvl$P_center_c))))

# differenced + standardised, against the estimation frame's own outcome
chk <- df_scaled |> select(micro, year, delta_P_dalton, delta_P_center) |>
  left_join(dlt_V0, by = c("micro", "year")) |>
  mutate(zD = as.numeric(scale(dPD)), zN = as.numeric(scale(dPN)))
d_D <- max(abs(chk$zD - chk$delta_P_dalton)); d_N <- max(abs(chk$zN - chk$delta_P_center))
cat(sprintf("max |z(rebuilt dP^D) - panel dP^D| = %.3e\nmax |z(rebuilt dP^N) - panel dP^N| = %.3e\n",
            d_D, d_N))

pass_A <- all(cmp$match) && all(res$n == 1668)
pass_B <- (d_D < 1e-10) && (d_N < 1e-10) &&
  max(abs(lvl$P_dalton - lvl$P_dalton_c)) < 1e-12
cat(sprintf("\n[I-1] PART A (published Table 3): %s\n[I-1] PART B (02->06 rebuild): %s\n",
            if (pass_A) "PASS" else "FAIL", if (pass_B) "PASS" else "FAIL"))

write_csv(res, file.path(OUT, "I1_table3_V0.csv"))
write_csv(cmp, file.path(OUT, "I1_published_diff.csv"))
write_csv(tibble(check = c("max_abs_dPD", "max_abs_dPN", "max_abs_level_PD",
                           "max_abs_level_PN", "N", "n_coef_matched"),
                 value = c(d_D, d_N, max(abs(lvl$P_dalton - lvl$P_dalton_c)),
                           max(abs(lvl$P_center - lvl$P_center_c)),
                           unique(res$n)[1], sum(cmp$match))),
          file.path(OUT, "I1_rebuild_checks.csv"))
saveRDS(list(res = res, cmp = cmp, idx_V0 = idx_V0), file.path(OUT, "I1.rds"))
cat("\n[I1] wrote", OUT, "\n")
if (!(pass_A && pass_B)) stop("[I-1] CANARY FAILED — stop and report.")
sink(); close(log_con)
