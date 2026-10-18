# =============================================================================
# gate_d_falsification.R — Gate (d) as fixed in plan §5 and amendment A1.2.
# Outcomes: ΔD_r(2002→2010), ΔD_r(2006→2010), D = federal-deputy Dalton
# (2010 from the canonical panel; 2002/2006 from gate_d_build_preperiod.R).
# Regressor: mean over t of the recentred treatment z̃_rt, standardised.
# State FE + base controls (2010 values). Stratified RI, B = 9,999.
# Pass (per design): p >= 0.05 in BOTH pre-period tests.
# =============================================================================
source("audit/ss_core.R")
pre <- readRDS("audit/out/dalton_deputado_2002_2006.rds"); pre$micro <- as.character(pre$micro)
u0 <- merge_units(W0_1, G0, sec0); u3 <- merge_units(W3_1, G3, sec3)
designs <- list(S0 = list(des = build_design(u0$W1, u0$G, u0$strata), ctrl = ctrl_base0),
                S3 = list(des = build_design(u3$W1, u3$G, u3$strata), ctrl = ctrl_base3))
r1 <- which(yi == 1)                                     # one row per microregion (2014 rows; m14 order)
X1 <- function(ctrl) model.matrix(~ ., data.frame(ctrl[r1, , drop = FALSE], st = factor(df$state[r1])))
res <- list()
for (nm in names(designs)) {
  des <- designs[[nm]]$des
  Q <- qr.Q(qr(X1(designs[[nm]]$ctrl))); P1 <- function(M) M - Q %*% crossprod(Q, M)
  zbar <- (des$zt[yi == 1] + des$zt[yi == 2] + des$zt[yi == 3]) / 3
  s <- sd(zbar); xp <- as.numeric(P1(matrix(zbar / s)))
  Zs <- matrix(0, length(r1), B)
  for (b in seq_len(B)) { Gp <- des$G[des$perms[, b], , drop = FALSE]
    zb <- rowSums(des$W * t(Gp[, yi])) - des$mu
    Zs[, b] <- (zb[yi == 1] + zb[yi == 2] + zb[yi == 3]) / 3 / s }
  Xs <- P1(Zs)
  for (y0 in c(2002, 2006)) {
    d0 <- setNames(pre$P_dalton[pre$year == y0], pre$micro[pre$year == y0])
    dy <- b10[m14] - d0[m14]; ok <- !is.na(dy)
    stopifnot(sum(!ok) == 0)
    yv <- zs(as.numeric(dy)); f <- ri_fit(as.numeric(P1(matrix(yv))), xp, Xs)
    ci <- ci_inv(f, 0.95)
    res[[paste(nm, y0)]] <- data.frame(design = nm, pre_period = paste0(y0, "->2010"), n = length(yv),
      beta = f$beta, ri_p = f$p, ci95_lo = ci[1], ci95_hi = ci[2], pass = f$p >= 0.05)
    print(res[[paste(nm, y0)]])
  }
}
tab <- do.call(rbind, res); rownames(tab) <- NULL
write.csv(tab, "audit/out/gate_d_falsification.csv", row.names = FALSE)
for (nm in c("S0", "S3")) cat(sprintf("GATE (d) %s: %s\n", nm, if (all(tab$pass[tab$design == nm])) "PASS" else "FAIL"))
