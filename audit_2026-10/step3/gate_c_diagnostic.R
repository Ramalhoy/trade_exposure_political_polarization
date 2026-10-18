# Diagnostic (not a gate): why does RI over-reject conditional on the realised shocks?
# Compares the residual norm of the observed recentred treatment with the permutation
# distribution of that norm, and the observed vs permuted correlation of the treatment
# with the outcome residual's microregion structure is NOT used (no outcome here).
source("audit/ss_core.R")
u0 <- merge_units(W0_1, G0, sec0); u3 <- merge_units(W3_1, G3, sec3)
for (nm in c("S0", "S3")) {
  des <- if (nm == "S0") build_design(u0$W1, u0$G, u0$strata) else build_design(u3$W1, u3$G, u3$strata)
  P <- proj_maker(if (nm == "S0") ctrl_base0 else ctrl_base3)
  sdx <- sd(des$zt); xp <- as.numeric(P(matrix(des$zt / sdx)))
  Xs <- perm_matrix(des, P, sdx); n2 <- colSums(Xs^2)
  # Herfindahl of the residualised treatment across microregions (leverage concentration)
  h <- function(v) { a <- tapply(v^2, rep(m14, 3), sum); sum((a / sum(a))^2) }
  hs <- apply(Xs[, 1:2000], 2, h)
  cat(sprintf("%s: ||x_perp||^2 observed %.1f | permutation median %.1f | share of draws below observed %.3f\n",
              nm, sum(xp^2), median(n2), mean(n2 < sum(xp^2))))
  cat(sprintf("%s: leverage HHI over microregions observed %.3f (eff. micros %.1f) | permutation median %.3f (eff. %.1f) | share of draws more concentrated %.3f\n",
              nm, h(xp), 1 / h(xp), median(hs), 1 / median(hs), mean(hs > h(xp))))
}
