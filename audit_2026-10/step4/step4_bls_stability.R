# =============================================================================
# step4_bls_stability.R — plan §2.4 with A2.3 and A3.3.2.
# For each of the 500 BLS bootstrap draws (bls_bootstrap_draws.rds), party scores
# replace the stored ones (same wave and label the panel used, incl. carried rows),
# the deputy Dalton index is rebuilt, ΔDalton 2010 -> t standardised, and the
# primary classification recomputed for both designs with B = 999 (first 999 of
# the step-3 draws). Classification: EQ if p(±0.162) <= 0.10 and |β| < 0.162
# (= 90% inverted set inside ±0.162 when the set is an interval); POS/NEG if Holm p < 0.05.
# Rule (pre-registered): a design whose class changes in > 5% of draws takes the row-4 sentence.
# Pre-registered version: draws as mapped (A2.3). Labelled sensitivity (not part of the
# rule): stored score + (draw − full-sample ALS score), which removes the ALS-vs-stored
# level difference and keeps only resampling noise.
# =============================================================================
source("audit/ss_core.R"); source("audit/ss_stud.R"); library(data.table)
NB <- 999L
dr <- as.data.table(readRDS("audit/out/bls_bootstrap_draws.rds"))
als0 <- fread("audit/out/bls_scaling_repro_items.csv")             # full-sample ALS on stored scale (pi_s)
pan <- as.data.table(readRDS(file.path(D, "painel_ideologico_deputado_federal.rds")))[round == 1 & !is.na(ideo) & votes > 0]
pan[, cell := paste(microregion_code, year)]
dal <- function(y) { pan[, yy := y]; pan[, { w <- votes / sum(votes); yb <- sum(w * yy); .(d = sqrt(sum(w * (yy - yb)^2))) }, by = .(microregion_code, year)] }
toy <- function(dt) { b0 <- dt[year == 2010]; cur <- dt[match(paste(df$micro, df$year), paste(microregion_code, year)), d]
  zs(cur - b0[match(df$micro, as.character(microregion_code)), d]) }
stopifnot(max(abs(toy(dal(pan$ideo)) - y_dep)) < 1e-10)              # canary: stored scores reproduce y_dep
classify <- function(f) { p0 <- stud_p(f, 0); eq <- abs(f$beta) < 0.162 && stud_p(f, 0.162) <= 0.10 && stud_p(f, -0.162) <= 0.10
  c(beta = f$beta, p = p0, eq = eq) }
cls <- function(m) { ph <- p.adjust(m[, "p"], "holm")
  ifelse(m[, "eq"] == 1 & ph < 0.05, "EQ+sig", ifelse(m[, "eq"] == 1, "EQ", ifelse(ph < 0.05, ifelse(m[, "beta"] > 0, "POS", "NEG"), "INC"))) }
SS <- lapply(c(S0 = "S0", S3 = "S3"), function(nm) {
  des <- if (nm == "S0") { u <- merge_units(W0_1, G0, sec0); build_design(u$W1, u$G, u$strata) } else {
    u <- merge_units(W3_1, G3, sec3); build_design(u$W1, u$G, u$strata) }
  P <- proj_maker(if (nm == "S0") ctrl_base0 else ctrl_base3); list(S = stud_setup(des, P, NB), P = P) })
run <- function(y) { m <- t(sapply(SS, function(s) classify(stud_fit(s$S, as.numeric(s$P(matrix(y))))))); data.frame(design = rownames(m), m, class = cls(m)) }
base <- run(y_dep); cat("Stored scores, B = 999:\n"); print(base)
key <- pan[, .(ideo_wave, bls_label)]
out <- list()
if (file.exists("audit/out/step4_bls_stability_draws.csv")) o <- fread("audit/out/step4_bls_stability_draws.csv") else {
for (v in c("prereg", "centred")) {
  for (k in 1:500) {
    d <- dr[draw == k]
    sc <- d$ideo_draw[match(paste(key$ideo_wave, key$bls_label), paste(d$year, d$label))]
    if (v == "centred") sc <- pan$ideo + sc - als0$pi_s[match(paste(key$ideo_wave, key$bls_label), paste(als0$year, als0$label))]
    stopifnot(!anyNA(sc))
    r <- run(toy(dal(sc))); r$draw <- k; r$version <- v; out[[paste(v, k)]] <- r
  }
  cat(v, "done\n")
}
o <- rbindlist(out); fwrite(o, "audit/out/step4_bls_stability_draws.csv") }
prim <- fread("audit/out/step4_primary.csv")
sm <- o[, .(beta_med = median(beta), beta_p05 = quantile(beta, 0.05), beta_p95 = quantile(beta, 0.95),
            share_EQ = mean(class %in% c("EQ", "EQ+sig")), share_POSNEG = mean(class %in% c("POS", "NEG")),
            share_INC = mean(class == "INC")), by = .(version, design)]
sm$headline_class <- prim$class[match(sm$design, prim$design)]
sm$share_changed <- o[, .(ch = mean(class != prim$class[match(design[1], prim$design)])), by = .(version, design)]$ch
sm$rule_row4 <- sm$share_changed > 0.05
print(sm); fwrite(sm, "audit/out/step4_bls_stability.csv")
