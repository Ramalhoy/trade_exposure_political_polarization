# =============================================================================
# step7_ri_draws.R — saves the studentized randomization draws t* behind Table 4
# (same designs, controls, permutations and statistic as step4_primary.R under A4).
# Canary: the p-value recomputed from the saved draws equals step4_primary.csv p_stud.
# =============================================================================
source("audit/ss_core.R"); source("audit/ss_stud.R"); suppressMessages(library(data.table))
pr <- fread("audit/out/step4_primary.csv")
out <- list()
for (nm in c("S0", "S3")) {
  u <- if (nm == "S0") merge_units(W0_1, G0, sec0) else merge_units(W3_1, G3, sec3)
  des <- build_design(u$W1, u$G, u$strata); P <- proj_maker(if (nm == "S0") ctrl_base0 else ctrl_base3)
  S <- stud_setup(des, P, B); yp <- as.numeric(P(matrix(y_dep))); f <- stud_fit(S, yp)
  U <- yp - sweep(S$Xs, 2, f$bstar, `*`); ses <- se_er(S, U, S$Gp, f$ssb)
  tstar <- f$bstar / ses; t0 <- f$beta / f$se
  p <- (1 + sum(abs(tstar) >= abs(t0))) / (length(tstar) + 1)
  stopifnot(abs(p - pr[design == nm, p_stud]) < 1e-12, abs(f$beta - pr[design == nm, beta]) < 1e-12)
  cat(sprintf("%s: beta %.5f t %.3f p %.4f (matches step4_primary.csv)\n", nm, f$beta, t0, p))
  out[[nm]] <- data.table(design = nm, draw = seq_along(tstar), tstar = tstar, t_obs = t0)
}
fwrite(rbindlist(out), "audit/out/step7_ri_draws.csv")
