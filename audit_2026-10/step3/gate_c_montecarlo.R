# =============================================================================
# gate_c_montecarlo.R — Gate (c), as fixed in plan §5 and amendment A1.3.
# DGP: e = microregion triplets of residuals of standardised deputy ΔDalton on
# base controls + state×year FE (treatment absent), resampled with replacement
# within state; y = beta * z_tilde/sd(z_tilde) + e; 1,000 reps per beta in
# {0, Δ, 2Δ}. Test: recentred stratified RI (B = 9,999, same draws every rep).
# Pass: size at nominal 5% in [0.03, 0.07]; |mean bias at β=Δ| < 0.1Δ.
# Reported: power at Δ and 2Δ; P(EQ | β=0), EQ = 90% RI set inside [−Δ, Δ].
# Additional (not a gate): residuals in place, "true" shocks = a random
# within-stratum permutation, tested against the remaining draws.
# =============================================================================
source("audit/ss_core.R")
DELTA <- 0.038; R <- 1000L; set.seed(20261018)
u0 <- merge_units(W0_1, G0, sec0); u3 <- merge_units(W3_1, G3, sec3)
designs <- list(S0 = list(des = build_design(u0$W1, u0$G, u0$strata), ctrl = ctrl_base0),
                S3 = list(des = build_design(u3$W1, u3$G, u3$strata), ctrl = ctrl_base3))
grid_ok <- function(f, lo, hi) all(vapply(c(lo, hi), function(b) p_at(f, b) <= 0.10, TRUE))
state_r <- df$state[yi == 1]; n1 <- length(m14)
out <- list()
for (nm in names(designs)) {
  des <- designs[[nm]]$des; P <- proj_maker(designs[[nm]]$ctrl)
  sdx <- sd(des$zt); x <- des$zt / sdx; xp <- as.numeric(P(matrix(x)))
  cat(sprintf("[%s] building %d permuted treatments ...\n", nm, B)); t0 <- Sys.time()
  Xs <- perm_matrix(des, P, sdx); cat("  done in", format(Sys.time() - t0), "\n")
  e  <- as.numeric(P(matrix(y_dep)))                      # outcome residualised on controls+FE only
  E  <- matrix(e, n1, 3)                                  # rows = micros (m14 order), cols = years
  for (beta in c(0, DELTA, 2 * DELTA)) {
    res <- t(replicate(R, {
      pick <- unlist(lapply(split(seq_len(n1), state_r), function(k) k[sample.int(length(k), length(k), replace = TRUE)]))
      ord  <- unlist(split(seq_len(n1), state_r))
      eb <- E; eb[ord, ] <- E[pick, ]
      y  <- beta * x + as.numeric(eb)
      f  <- ri_fit(as.numeric(P(matrix(y))), xp, Xs)
      eq <- abs(f$beta) < DELTA && grid_ok(f, -DELTA, DELTA)
      c(beta = f$beta, p = f$p, eq = eq) }))
    out[[paste(nm, beta)]] <- data.frame(design = nm, beta_true = beta, R = R,
      reject5 = mean(res[, "p"] < 0.05), mean_bias = mean(res[, "beta"]) - beta,
      sd_beta = sd(res[, "beta"]), p_eq = mean(res[, "eq"]))
    print(out[[paste(nm, beta)]])
  }
  # additional, in-place variant: true shocks = a random permutation k
  ks <- sample.int(B, R)
  inplace <- t(sapply(ks, function(k) {
    xk <- Xs[, k]; Xr <- Xs[, -k, drop = FALSE]
    sapply(c(0, DELTA), function(beta) {
      y <- beta * xk + e
      ss <- colSums(Xr^2); bh <- sum(xk * y) / sum(xk^2); bs <- as.numeric(crossprod(Xr, y)) / ss
      (1 + sum(abs(bs) >= abs(bh))) / ncol(Xr) < 0.05 }) }))
  out[[paste(nm, "inplace")]] <- data.frame(design = nm, beta_true = c(0, DELTA), R = R,
    reject5 = colMeans(inplace), mean_bias = NA, sd_beta = NA, p_eq = NA)
  print(out[[paste(nm, "inplace")]])
}
tab <- do.call(rbind, out); rownames(tab) <- NULL
tab$variant <- ifelse(is.na(tab$mean_bias), "in-place (not a gate)", "resampled (gate)")
write.csv(tab, "audit/out/gate_c_montecarlo.csv", row.names = FALSE)
g <- tab[tab$variant == "resampled (gate)", ]
for (nm in c("S0", "S3")) {
  s <- g$reject5[g$design == nm & g$beta_true == 0]; b <- g$mean_bias[g$design == nm & g$beta_true == DELTA]
  cat(sprintf("GATE (c) %s: size %.3f in [0.03,0.07]? %s | |bias at Δ| %.4f < %.4f? %s | P(EQ|0) %.3f%s\n",
      nm, s, s >= 0.03 && s <= 0.07, abs(b), 0.1 * DELTA, abs(b) < 0.1 * DELTA,
      g$p_eq[g$design == nm & g$beta_true == 0],
      if (g$p_eq[g$design == nm & g$beta_true == 0] < 0.5) "  -> UNDERPOWERED FOR EQUIVALENCE (declared before headline)" else ""))
}
