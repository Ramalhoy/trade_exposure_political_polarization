# =============================================================================
# step4_speccurve.R — plan §6 with A3.3.5. Descriptive only; the headline is not
# chosen from it. Grid, per design (S0, S3):
#   controls   base | extended (base + urban_share, educ_share, manuf_share_of_tradable,
#              the ctrl_ext set of Code/07_regression_inference.R L123)
#   centring   recentred | uncentred: x = z / sd(z) with θ × year added
#              (S0 θ = tradable_emp_share; S3 θ = theta_r_dest of E0_frame.rds)
#   strata     primary | none (one stratum: permutation and recentring across all units)
#   sample     full | S3-exporting microregions (theta_r_dest > 0)
#   coverage   none | deputy rows with scored coverage >= 0.85 in 2010 and t (deputy only)
#   index      Dalton | ER(1.0) | ER(1.4) | centre-emptying
#   office     deputy | governor (repaired) | president
# Each point: β̂ and studentized RI p with B = 999 (first 999 step-3 draws).
# Outcomes standardised over the 1,671-row frame; x scaled by its full-frame SD,
# so every point is in the units of the headline. Dropped rows are removed by
# row dummies in the FWL projection (exact for β̂) and from the AKM X̃ regression.
# =============================================================================
source("audit/ss_core.R"); source("audit/step4_outcomes.R"); library(data.table)
NB <- 999L
ctrl_ext <- function(c) data.frame(c, urban = zs(E0$urban_share), educ = zs(E0$educ_share), manuf = zs(E0$manuf_share_of_tradable))
proj_keep <- function(ctrl, keep) {
  X <- model.matrix(~ ., data.frame(ctrl, sy = factor(paste(df$state, df$year))))
  if (any(!keep)) X <- cbind(X, diag(nrow(df))[, !keep, drop = FALSE])
  q <- qr(X); Q <- qr.Q(q)[, seq_len(q$rank)]; function(M) M - Q %*% crossprod(Q, M) }
setup <- function(W1, gt, perms, P, keep) {        # gt: units x 3 shock matrix already centred/scaled as x uses
  W <- stack3(W1); x <- rowSums(W * t(gt[, yi]))
  Xs <- matrix(0, nrow(df), NB)
  for (k in 1:3) { r <- which(yi == k); Xs[r, ] <- W1 %*% matrix(gt[perms[, 1:NB], k], nrow(gt)) }
  xp <- as.numeric(P(matrix(x))); Xs <- P(Xs)
  rows <- lapply(1:3, function(k) which(yi == k & keep)); Wk <- lapply(1:3, function(k) W1[match(df$micro[rows[[k]]], rownames(W1)), , drop = FALSE])
  cf <- function(k, M) { b <- qr.coef(qr(Wk[[k]]), M); b[is.na(b)] <- 0; b }
  list(xp = xp, Xs = Xs, rows = rows, Wk = Wk, Xt = lapply(1:3, function(k) cf(k, matrix(xp[rows[[k]]]))),
       Gp = lapply(1:3, function(k) cf(k, Xs[rows[[k]], , drop = FALSE]))) }
se2 <- function(S, U, Gl, ss) { term <- 0
  for (k in 1:3) term <- term + Gl[[k]] * crossprod(S$Wk[[k]], U[S$rows[[k]], , drop = FALSE]); sqrt(colSums(term^2)) / ss }
fitp <- function(S, yp) { ss0 <- sum(S$xp^2); bh <- sum(S$xp * yp) / ss0; se0 <- se2(S, matrix(yp - bh * S$xp), S$Xt, ss0)
  ssb <- colSums(S$Xs^2); bs <- as.numeric(crossprod(S$Xs, yp)) / ssb; U <- yp - sweep(S$Xs, 2, bs, `*`)
  ses <- se2(S, U, S$Gp, ssb); c(beta = bh, p = (1 + sum(abs(bs / ses) >= abs(bh / se0))) / (NB + 1)) }
idx <- c(dalton = "Dalton", er10 = "ER(1.0)", er14 = "ER(1.4)", centre = "Centre-emptying")
off <- c(dep = "deputy", gov = "governor", pres = "president")
exporting <- E0$theta_r_dest > 0
res <- list()
for (nm in c("S0", "S3")) {
  u <- if (nm == "S0") merge_units(W0_1, G0, sec0) else merge_units(W3_1, G3, sec3)
  th <- if (nm == "S0") df$tradable_emp_share else E0$theta_r_dest
  for (strat in c("primary", "none")) {
    st <- if (strat == "primary") u$strata else setNames(rep("all", length(u$strata)), names(u$strata))
    des <- build_design(u$W1, u$G, st)
    for (cen in c("recentred", "uncentred")) {
      gt <- if (cen == "recentred") (des$G - apply(des$G, 2, function(g) ave(g, st))) / sd(des$zt) else des$G / sd(des$z)
      for (cc in c("base", "extended")) {
        ctrl <- if (nm == "S0") ctrl_base0 else ctrl_base3; if (cc == "extended") ctrl <- ctrl_ext(ctrl)
        if (cen == "uncentred") ctrl <- data.frame(ctrl, thy = model.matrix(~ 0 + factor(df$year):th))
        for (smp in c("full", "exporting")) for (cov in c("none", "0.85")) {
          keep <- if (smp == "full") rep(TRUE, nrow(df)) else exporting
          if (cov == "0.85") keep <- keep & outc$dep_cov_ok
          P <- proj_keep(ctrl, keep); S <- setup(des$W1, gt, des$perms, P, keep)
          for (o in names(off)) { if (cov == "0.85" && o != "dep") next
            for (i in names(idx)) { y <- zs(outc[[paste(o, i, sep = "_")]]); yp <- as.numeric(P(matrix(y)))
              r <- fitp(S, yp)
              res[[length(res) + 1]] <- data.table(design = nm, controls = cc, centring = cen, strata = strat, sample = smp,
                coverage = cov, index = idx[[i]], office = off[[o]], n = sum(keep), beta = r[["beta"]], p = r[["p"]]) } }
          cat(nm, strat, cen, cc, smp, cov, "done\n") } } } }
}
tab <- rbindlist(res)
tab[, headline := controls == "base" & centring == "recentred" & strata == "primary" & sample == "full" & coverage == "none" & index == "Dalton" & office == "deputy"]
fwrite(tab, "audit/out/step4_speccurve.csv")
print(tab[headline == TRUE])
print(tab[, .(points = .N, beta_min = min(beta), beta_med = median(beta), beta_max = max(beta), share_p05 = mean(p < 0.05),
              share_p10 = mean(p < 0.10)), by = .(design, office)])
print(tab[, .(points = .N, share_p05 = mean(p < 0.05)), by = design])
