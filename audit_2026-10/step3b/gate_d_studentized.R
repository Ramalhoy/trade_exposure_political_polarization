# =============================================================================
# gate_d_studentized.R — Gate (d) rerun under A2.5: same outcomes, regressor,
# controls and pass rule as A1.2, with the studentized statistic (A2.1/A2.1a).
# Cross-section of 557 microregions; regressor = mean over t of recentred z̃,
# standardised; AKM shock term X̃ = coefficients of the residualised regressor on
# the shares; B = 9,999 within-stratum permutations.
# =============================================================================
source("audit/ss_core.R")
pre <- readRDS("audit/out/dalton_deputado_2002_2006.rds"); pre$micro <- as.character(pre$micro)
r1 <- which(yi == 1)
X1 <- function(ctrl) model.matrix(~ ., data.frame(ctrl[r1, , drop = FALSE], st = factor(df$state[r1])))
res <- list()
for (nm in c("S0", "S3")) {
  des <- if (nm == "S0") { u <- merge_units(W0_1, G0, sec0); build_design(u$W1, u$G, u$strata) } else {
    u <- merge_units(W3_1, G3, sec3); build_design(u$W1, u$G, u$strata) }
  Q <- qr.Q(qr(X1(if (nm == "S0") ctrl_base0 else ctrl_base3))); P1 <- function(M) M - Q %*% crossprod(Q, M)
  gbar <- apply(des$G, 2, function(g) ave(g, des$strata)); gm <- rowMeans(des$G - gbar)   # mean recentred shock path
  zbar <- as.numeric(des$W1 %*% gm); s <- sd(zbar)
  xp <- as.numeric(P1(matrix(zbar / s)))
  Xs <- P1(des$W1 %*% matrix(gm[des$perms] / s, nrow(des$G)))                        # n x B
  qrW <- qr(des$W1); Xt <- qr.coef(qrW, xp); Xtp <- qr.coef(qrW, Xs)
  ss0 <- sum(xp^2); ssb <- colSums(Xs^2)
  sefun <- function(Xtl, U, ss) sqrt(colSums((Xtl * crossprod(des$W1, U))^2)) / ss
  for (y0 in c(2002, 2006)) {
    d0 <- setNames(pre$P_dalton[pre$year == y0], pre$micro[pre$year == y0])
    yp <- as.numeric(P1(matrix(zs(as.numeric(b10[m14] - d0[m14])))))
    pfun <- function(b) {
      y0b <- yp - b * xp; bh <- sum(xp * y0b) / ss0; se <- sefun(matrix(Xt), matrix(y0b - bh * xp), ss0)
      bs <- as.numeric(crossprod(Xs, y0b)) / ssb; U <- y0b - sweep(Xs, 2, bs, `*`); ses <- sefun(Xtp, U, ssb)
      (1 + sum(abs(bs / ses) >= abs(bh / se))) / (ncol(Xs) + 1) }
    bh <- sum(xp * yp) / ss0; p <- pfun(0)
    # confidence-set ends by bisection on each side (assumes the acceptance region is an interval)
    edge <- function(inside, outside) { if (pfun(outside) > 0.05) return(NA)
      for (k in 1:12) { mid <- (inside + outside) / 2; if (pfun(mid) > 0.05) inside <- mid else outside <- mid }; inside }
    acc <- c(edge(bh, bh - 0.4), edge(bh, bh + 0.4))
    res[[paste(nm, y0)]] <- data.frame(design = nm, pre_period = paste0(y0, "->2010"), beta = bh,
      se_akm = sefun(matrix(Xt), matrix(yp - bh * xp), ss0), stud_ri_p = p,
      ci95_lo = min(acc), ci95_hi = max(acc), pass = p >= 0.05)
    print(res[[paste(nm, y0)]])
  }
}
tab <- do.call(rbind, res); rownames(tab) <- NULL
write.csv(tab, "audit/out/gate_d_studentized.csv", row.names = FALSE)
for (nm in c("S0", "S3")) cat(sprintf("GATE (d, studentized) %s: %s\n", nm, if (all(tab$pass[tab$design == nm])) "PASS" else "FAIL"))
