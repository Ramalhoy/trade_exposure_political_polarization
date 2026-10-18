# =============================================================================
# gate_c_studentized.R — Gate (c) rerun under amendments A2.1/A2.1a/A2.5.
# Same DGP and thresholds as step 3 (A1.3): residual triplets of standardised
# deputy ΔDalton on base controls + state×year FE, resampled within state;
# y = beta * x + e; 1,000 reps at beta in {0, 0.038, 0.076}.
# Test: studentized RI (t = beta / se_AKM), B = 999 draws per replication.
# Pass: size in [0.03, 0.07]; |mean bias at 0.038| < 0.0038.
# Reported: P(EQ | beta = 0) at each benchmark 0.038, 0.059, 0.162 (A2.4);
# a benchmark with P(EQ|0) < 0.5 is declared not attainable before the headline.
# Usage: Rscript gate_c_studentized.R S0|S3
# =============================================================================
args <- commandArgs(TRUE); nm <- args[1]
source("audit/ss_core.R"); source("audit/ss_stud.R")
R <- 1000L; BM <- c(Rettl = 0.038, DGH = 0.059, CS = 0.162); BETAS <- c(0, 0.038, 0.076)
set.seed(if (nm == "S0") 20261018 else 20261019)
des <- if (nm == "S0") { u <- merge_units(W0_1, G0, sec0); build_design(u$W1, u$G, u$strata) } else {
  u <- merge_units(W3_1, G3, sec3); build_design(u$W1, u$G, u$strata) }
P <- proj_maker(if (nm == "S0") ctrl_base0 else ctrl_base3)
S <- stud_setup(des, P, 999L)
e <- as.numeric(P(matrix(y_dep))); n1 <- length(m14); E <- matrix(e, n1, 3)
state_r <- df$state[yi == 1]; ord <- unlist(split(seq_len(n1), state_r))
out <- list()
for (beta in BETAS) {
  t0 <- Sys.time()
  res <- t(replicate(R, {
    pick <- unlist(lapply(split(seq_len(n1), state_r), function(k) k[sample.int(length(k), length(k), replace = TRUE)]))
    eb <- E; eb[ord, ] <- E[pick, ]
    yp <- as.numeric(P(matrix(beta * S$x + as.numeric(eb))))
    f  <- stud_fit(S, yp)
    eq <- if (beta == 0) sapply(BM, function(d) abs(f$beta) < d && stud_p(f, d) <= 0.10 && stud_p(f, -d) <= 0.10) else rep(NA, 3)
    c(beta = f$beta, se = f$se, p = stud_p(f, 0), eq) }))
  colnames(res)[4:6] <- paste0("eq_", names(BM))
  out[[as.character(beta)]] <- data.frame(design = nm, beta_true = beta, R = R, reject5 = mean(res[, "p"] < 0.05),
    mean_bias = mean(res[, "beta"]) - beta, sd_beta = sd(res[, "beta"]), mean_se = mean(res[, "se"]),
    p_eq_Rettl = mean(res[, 4]), p_eq_DGH = mean(res[, 5]), p_eq_CS = mean(res[, 6]))
  print(out[[as.character(beta)]]); cat("  elapsed", format(Sys.time() - t0), "\n")
}
tab <- do.call(rbind, out); rownames(tab) <- NULL
write.csv(tab, sprintf("audit/out/gate_c_studentized_%s.csv", nm), row.names = FALSE)
s <- tab$reject5[tab$beta_true == 0]; b <- tab$mean_bias[tab$beta_true == 0.038]
cat(sprintf("GATE (c, studentized) %s: size %.3f in [0.03,0.07]? %s | |bias at 0.038| %.4f < 0.0038? %s\n",
            nm, s, s >= 0.03 && s <= 0.07, abs(b), abs(b) < 0.0038))
for (k in names(BM)) { pe <- tab[[paste0("p_eq_", k)]][tab$beta_true == 0]
  cat(sprintf("  benchmark %s (%.3f): P(EQ|0) = %.3f -> %s\n", k, BM[k], pe, if (pe >= 0.5) "attainable" else "NOT attainable (declared before headline)")) }
