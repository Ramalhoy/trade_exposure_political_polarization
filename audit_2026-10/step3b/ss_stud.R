# =============================================================================
# ss_stud.R — studentized RI (amendment A2.1). Sourced after ss_core.R.
# t = beta / se_ER, se_ER^2 = sum_n ( sum_t Xtil_nt * sum_{r in t} s_rn * u_rt )^2 / (sum x_perp^2)^2
# Xtil_t = OLS coefficients of the residualised treatment (year-t rows) on the shares (AKM 2019);
# amendment A2.1a. Verified equal to ShiftShareSE::reg_ss "AKM" on a cross-section.
# Everything is vectorised over the B permutation draws.
# =============================================================================
stud_setup <- function(des, P, nperm = ncol(des$perms)) {
  sdx  <- sd(des$zt)
  gbar <- apply(des$G, 2, function(g) ave(g, des$strata))
  gt   <- (des$G - gbar) / sdx                                   # U x 3
  x    <- rowSums(des$W * t(gt[, yi])); stopifnot(max(abs(x - des$zt / sdx)) < 1e-9)
  perms <- des$perms[, seq_len(nperm), drop = FALSE]
  Gp <- lapply(1:3, function(k) matrix(gt[perms, k], nrow(gt)))  # U x B, permuted recentred shocks
  Xs <- matrix(0, nrow(des$W), nperm)
  for (k in 1:3) { r <- which(yi == k); Xs[r, ] <- des$W1 %*% Gp[[k]] }
  rows <- lapply(1:3, function(k) which(yi == k)); xp <- as.numeric(P(matrix(x))); Xs <- P(Xs)
  qrW <- qr(des$W1); stopifnot(qrW$rank == ncol(des$W1))
  Xt  <- lapply(1:3, function(k) qr.coef(qrW, matrix(xp[rows[[k]]])))          # observed X-tilde
  Xtp <- lapply(1:3, function(k) qr.coef(qrW, Xs[rows[[k]], , drop = FALSE]))  # permuted X-tilde (U x B)
  list(W1 = des$W1, gt = gt, x = x, xp = xp, Xt = Xt, Gp = Xtp, Xs = Xs, rows = rows)
}
# se for residual matrix U (n x m) and shock matrices G (list of 3, U x m)
se_er <- function(S, U, Glist, ss) {
  term <- 0
  for (k in 1:3) term <- term + Glist[[k]] * crossprod(S$W1, U[S$rows[[k]], , drop = FALSE])
  sqrt(colSums(term^2)) / ss }
stud_fit <- function(S, yp) {
  ss0 <- sum(S$xp^2); bh <- sum(S$xp * yp) / ss0; u <- yp - bh * S$xp
  se0 <- se_er(S, matrix(u), S$Xt, ss0)
  ssb <- colSums(S$Xs^2); bs <- as.numeric(crossprod(S$Xs, yp)) / ssb
  cs  <- as.numeric(crossprod(S$Xs, S$xp)) / ssb
  list(S = S, yp = yp, beta = bh, se = se0, bstar = bs, c = cs, ssb = ssb) }
# studentized RI p-value for H0: beta = b
stud_p <- function(f, b) {
  S <- f$S; y0 <- f$yp - b * S$xp
  bs <- f$bstar - b * f$c
  U  <- y0 - sweep(S$Xs, 2, bs, `*`)
  ses <- se_er(S, U, S$Gp, f$ssb)
  t0 <- (f$beta - b) / f$se
  (1 + sum(abs(bs / ses) >= abs(t0))) / (length(bs) + 1) }
stud_ci <- function(f, level = 0.90, step = 0.002, span = 0.40) {
  g <- seq(f$beta - span, f$beta + span, by = step)
  acc <- g[vapply(g, function(b) stud_p(f, b) > 1 - level, TRUE)]
  if (!length(acc)) return(c(NA, NA))
  if (min(acc) <= min(g) + step || max(acc) >= max(g) - step) warning("studentized CI touches grid edge")
  c(min(acc), max(acc)) }
