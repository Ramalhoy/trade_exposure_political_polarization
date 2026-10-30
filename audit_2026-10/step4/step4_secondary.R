# =============================================================================
# step4_secondary.R — secondary family (plan §3; A3.3.3) and AKM0 (A3.3.4).
# Ten tests, BH at q = 0.05:
#   per design: deputy ΔER(α=1); Δȳ president, governor (repaired, A3.2), deputy:
#               studentized RI p (B = 9,999), as for the primary;
#   per design: bust coefficient on deputy ΔDalton (H1b) from y ~ boom + bust,
#               boom = max(z,0)/sd(z), bust = max(-z,0)/sd(z) (07_regression_inference.R
#               convention), each recentred by its mean over the B permutation draws
#               (simulated recentring, Borusyak & Hull 2023); statistic = bust coefficient /
#               microregion-clustered SE; RI over the same draws. NOT VALIDATED by gate (c).
# AKM0: ShiftShareSE::reg_ss(method = "akm0"), block-diagonal share matrix (one column per
#   unit-year) with sector_cvar = unit, i.e. shocks clustered by unit across years; the
#   "akm" SE from the same call must equal the studentized statistic's se (canary).
# All outcomes standardised over the 1,671 rows.
# =============================================================================
source("audit/ss_core.R"); source("audit/ss_stud.R"); source("audit/step4_outcomes.R")
suppressMessages(library(ShiftShareSE))
OUTS <- c(dep_er10 = "Deputy ΔER(α=1)", pres_ybar = "President Δȳ", gov_ybar = "Governor Δȳ (repaired)", dep_ybar = "Deputy Δȳ")
res <- list(); akm <- list()
for (nm in c("S0", "S3")) {
  des <- if (nm == "S0") { u <- merge_units(W0_1, G0, sec0); build_design(u$W1, u$G, u$strata) } else {
    u <- merge_units(W3_1, G3, sec3); build_design(u$W1, u$G, u$strata) }
  ctrl <- if (nm == "S0") ctrl_base0 else ctrl_base3
  P <- proj_maker(ctrl); S <- stud_setup(des, P, B)
  for (o in names(OUTS)) {
    yp <- as.numeric(P(matrix(zs(outc[[o]])))); f <- stud_fit(S, yp)
    res[[paste(nm, o)]] <- data.frame(design = nm, test = OUTS[[o]], beta = f$beta, se_akm = f$se, p = stud_p(f, 0), validated = TRUE)
    print(res[[paste(nm, o)]])
  }
  # ---- bust coefficient, simulated recentring ----
  sdz <- sd(des$z); NC <- 1000L; ch <- split(seq_len(B), ceiling(seq_len(B) / NC))
  zstar <- function(cols) { Z <- matrix(0, nrow(des$W), length(cols))
    for (j in seq_along(cols)) Z[, j] <- rowSums(des$W * t(des$G[des$perms[, cols[j]], yi, drop = FALSE])); Z }
  mb <- rep(0, nrow(df)); mu_b <- rep(0, nrow(df))
  for (cc in ch) { Z <- zstar(cc); mb <- mb + rowSums(pmax(Z, 0)); mu_b <- mu_b + rowSums(pmax(-Z, 0)) }
  mb <- mb / B / sdz; mu_b <- mu_b / B / sdz
  cl <- df$micro; yp <- as.numeric(P(matrix(y_dep))); G_ <- length(unique(cl))
  tstat <- function(Bo, Bu) {             # columns = draws; returns bust coef and CR1-type t (G/(G-1))
    Bo <- P(Bo); Bu <- P(Bu)
    a <- colSums(Bo^2); c_ <- colSums(Bu^2); d <- colSums(Bo * Bu); r1 <- colSums(Bo * yp); r2 <- colSums(Bu * yp)
    det <- a * c_ - d^2; b1 <- (c_ * r1 - d * r2) / det; b2 <- (a * r2 - d * r1) / det
    U <- yp - sweep(Bo, 2, b1, `*`) - sweep(Bu, 2, b2, `*`)
    s1 <- rowsum(Bo * U, cl); s2 <- rowsum(Bu * U, cl)
    w1 <- -d / det; w2 <- a / det
    v <- (w1^2 * colSums(s1^2) + 2 * w1 * w2 * colSums(s1 * s2) + w2^2 * colSums(s2^2)) * G_ / (G_ - 1)
    cbind(b_bust = b2, b_boom = b1, t = b2 / sqrt(v)) }
  obs <- tstat(matrix(pmax(des$z, 0) / sdz - mb), matrix(pmax(-des$z, 0) / sdz - mu_b))
  tt <- unlist(lapply(ch, function(cc) { Z <- zstar(cc); tstat(pmax(Z, 0) / sdz - mb, pmax(-Z, 0) / sdz - mu_b)[, "t"] }))
  pb <- (1 + sum(abs(tt) >= abs(obs[, "t"]))) / (B + 1)
  res[[paste(nm, "bust")]] <- data.frame(design = nm, test = "Bust coefficient, deputy ΔDalton (H1b)", beta = obs[, "b_bust"],
    se_akm = NA, p = pb, validated = FALSE)
  cat(sprintf("%s bust: b_bust %.4f, b_boom %.4f, t_cl %.3f, RI p %.4f [NOT VALIDATED]\n", nm, obs[, "b_bust"], obs[, "b_boom"], obs[, "t"], pb))
  # ---- AKM0 (A3.3.4) ----
  W1 <- des$W1; N <- ncol(W1); n1 <- nrow(W1)
  Wbd <- matrix(0, nrow(df), 3 * N); for (k in 1:3) Wbd[yi == k, (k - 1) * N + seq_len(N)] <- W1
  scv <- rep(seq_len(N), 3)
  dd <- data.frame(ctrl, sy = factor(paste(df$state, df$year)), x = des$zt / sd(des$zt))
  fml <- as.formula(paste("y ~", paste(c(names(ctrl), "sy"), collapse = " + ")))
  for (o in c("dep_dalton", names(OUTS))) {
    dd$y <- if (o == "dep_dalton") y_dep else zs(outc[[o]])
    r <- reg_ss(fml, X = dd$x, data = dd, W = Wbd, method = c("akm", "akm0"), sector_cvar = scv)
    akm[[paste(nm, o)]] <- data.frame(design = nm, outcome = o, beta = r$beta, se_akm = r$se[["AKM"]],
      akm0_lo = r$ci.l[["AKM0"]], akm0_hi = r$ci.r[["AKM0"]], p_akm0 = r$p[["AKM0"]])
    print(akm[[paste(nm, o)]])
  }
  rm(S); gc()
}
tab <- do.call(rbind, res); rownames(tab) <- NULL
tab$q_BH <- p.adjust(tab$p, "BH"); tab$survives_BH <- tab$q_BH < 0.05
write.csv(tab, "audit/out/step4_secondary.csv", row.names = FALSE)
ak <- do.call(rbind, akm); rownames(ak) <- NULL
write.csv(ak, "audit/out/step4_akm0.csv", row.names = FALSE)
print(tab); print(ak)
