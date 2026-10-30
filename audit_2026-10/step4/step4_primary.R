# =============================================================================
# step4_primary.R — headline under the plan (02) and amendments A1, A2, A2.1a, A3.
# Primary family: {S0, S3_N2ex} x standardised deputy ΔDalton (2010 -> t), pooled β.
# Statistic: studentized RI, t = β / se_AKM (A2.1/A2.1a), B = 9,999 within-stratum
# permutations of whole shock paths (seed 2026, the step-3 draws).
# Sets: 90% and 95%, inverted by bisection on each side (tolerance 0.0005), with a
# 0.002 grid scan over β ± 0.4 checking that the acceptance region is an interval (A3.3.1).
# Holm across the two designs; equivalence at 0.038 / 0.059 / 0.162 (A2.4);
# decision-table class and abstract-sentence row (plan §4 as amended by A2.4).
# Also reported, labelled: coefficient-based RI p (failed gate (c) in step 3).
# =============================================================================
source("audit/ss_core.R"); source("audit/ss_stud.R")
BM <- c(Rettl = 0.038, DGH = 0.059, CS = 0.162)
design_of <- function(nm) if (nm == "S0") { u <- merge_units(W0_1, G0, sec0); build_design(u$W1, u$G, u$strata) } else {
  u <- merge_units(W3_1, G3, sec3); build_design(u$W1, u$G, u$strata) }
ctrl_of <- function(nm) if (nm == "S0") ctrl_base0 else ctrl_base3
edge <- function(f, inside, outside, a, tol = 0.0005) {
  if (stud_p(f, outside) > a) return(NA_real_)          # set unbounded within ±0.4
  while (abs(outside - inside) > tol) { mid <- (inside + outside) / 2
    if (stud_p(f, mid) > a) inside <- mid else outside <- mid }
  inside }
res <- list(); grids <- list()
for (nm in c("S0", "S3")) {
  t0 <- Sys.time()
  des <- design_of(nm); P <- proj_maker(ctrl_of(nm)); S <- stud_setup(des, P, B)
  yp <- as.numeric(P(matrix(y_dep))); f <- stud_fit(S, yp)
  fc <- ri_fit(yp, S$xp, S$Xs)                          # coefficient statistic (failed gate c, step 3)
  p0 <- stud_p(f, 0)
  ci <- sapply(c(0.90, 0.95), function(l) { a <- 1 - l; c(edge(f, f$beta, f$beta - 0.4, a), edge(f, f$beta, f$beta + 0.4, a)) })
  g <- round(seq(f$beta - 0.4, f$beta + 0.4, by = 0.002), 6); pg <- vapply(g, function(b) stud_p(f, b), 0)
  grids[[nm]] <- data.frame(design = nm, b = g, p = pg)
  chk <- sapply(c(0.10, 0.05), function(a) { acc <- which(pg > a)
    c(interval = length(acc) > 0 && all(diff(acc) == 1), lo = g[min(acc)], hi = g[max(acc)]) })
  eq <- sapply(BM, function(d) { lo <- ci[1, 1]; hi <- ci[2, 1]; !is.na(lo) && !is.na(hi) && lo > -d && hi < d })
  res[[nm]] <- data.frame(design = nm, n = nrow(df), n_units = ncol(des$W1), beta = f$beta, se_akm = f$se,
    t = f$beta / f$se, p_stud = p0, p_coef_failed_gate_c = fc$p,
    ci90_lo = ci[1, 1], ci90_hi = ci[2, 1], ci95_lo = ci[1, 2], ci95_hi = ci[2, 2],
    grid_interval90 = chk["interval", 1] == 1, grid90_lo = chk["lo", 1], grid90_hi = chk["hi", 1],
    grid_interval95 = chk["interval", 2] == 1, grid95_lo = chk["lo", 2], grid95_hi = chk["hi", 2],
    delta_star = max(abs(ci[, 1])), eq_Rettl = eq[1], eq_DGH = eq[2], eq_CS = eq[3],
    p_at_m162 = stud_p(f, -0.162), p_at_p162 = stud_p(f, 0.162))
  print(res[[nm]]); cat(nm, "elapsed", format(Sys.time() - t0), "\n")
  rm(S, f, des); gc()
}
tab <- do.call(rbind, res); rownames(tab) <- NULL
ph <- p.adjust(tab$p_stud, "holm"); tab$p_holm <- ph
# classes (plan §4 as amended by A2.4): EQ = 90% set inside ±0.162 (largest benchmark)
tab$class <- with(tab, ifelse(eq_CS & p_holm < 0.05, "EQ+sig", ifelse(eq_CS, "EQ",
  ifelse(p_holm < 0.05, ifelse(beta > 0, "POS", "NEG"), "INC"))))
tab$excluded_benchmarks <- apply(tab[, c("eq_Rettl", "eq_DGH", "eq_CS")], 1, function(v) paste(names(BM)[v], collapse = ","))
write.csv(tab, "audit/out/step4_primary.csv", row.names = FALSE)
write.csv(do.call(rbind, grids), "audit/out/step4_primary_grid.csv", row.names = FALSE)
cat("\nHolm-adjusted studentized p:", sprintf("%s %.4f", tab$design, tab$p_holm), "\n")
cat("Classes:", sprintf("%s=%s", tab$design, tab$class), "\n")
for (i in 1:2) with(tab[i, ], cat(sprintf("%s: beta %.4f | 90%% [%.4f, %.4f] | 95%% [%.4f, %.4f] | Delta* %.4f | excludes: %s\n",
  design, beta, ci90_lo, ci90_hi, ci95_lo, ci95_hi, delta_star, ifelse(excluded_benchmarks == "", "none", excluded_benchmarks))))
