# =============================================================================
# bls_scaling_repro.R — prerequisite A1.5: can the stored party scores
# (bls9_estimates_partiespresidents_long.rds) be reproduced from the
# legislator-level placements in BLS9_full?
# Model (Zucco & Power, eq. 1): P_ijt = a_i + b_i * pi_jt + e, respondent
# shift/stretch fixed across waves (uniqueid). Estimated here by alternating
# least squares (the Bayesian version in the paper uses rjags with weak priors,
# which is not available in this workspace). Identification: one global affine
# map onto the stored scale, then per-wave correlation and max |diff|.
# Pass: every wave 2001-2021 has corr >= 0.99 and max|diff| <= 0.05.
# =============================================================================
D <- Sys.getenv("SS_DATA_DIR", "D")
e <- new.env(); load(Sys.getenv("SS_BLS_FULL", "bls9_full.RData"), e); b <- e$bls
st <- as.data.frame(readRDS(file.path(D, "bls9_estimates_partiespresidents_long.rds")))
map <- list(
  `1990` = c(CID = "lrpcb", DEM = "lrpfl", MDB = "lrpmdb", PCDOB = "lrpcdob", PDC = "lrpdc", PDT = "lrpdt",
             PL = "lrpl", PP = "lrpds", PRN = "lrprn", PSB = "lrpsb", PSDB = "lrpsdb", PT = "lrpt", PTB = "lrptb"),
  `1993` = c(CID = "lrpps", DEM = "lrpfl", MDB = "lrpmdb", PCDOB = "lrpcdob", PDT = "lrpdt", PL = "lrpl",
             PP = "lrppr", PPold = "lrpp", PRN = "lrprn", PSB = "lrpsb", PSDB = "lrpsdb", PSTU = "lrpstu",
             PT = "lrpt", PTB = "lrptb"),
  `1997` = c(CID = "lrpps", DEM = "lrpfl", MDB = "lrpmdb", PCDOB = "lrpcdob", PDT = "lrpdt", PL = "lrpl",
             PP = "lrpp_ppb", PSB = "lrpsb", PSDB = "lrpsdb", PT = "lrpt", PTB = "lrptb"),
  `2009` = c(CID = "lrpps", DEM = "lrdem", MDB = "lrpmdb", PCDOB = "lrpcdob", PDT = "lrpdt", PL = "lrpr",
             PP = "lrpp_ppb", PSB = "lrpsb", PSDB = "lrpsdb", PSOL = "lrpsol", PT = "lrpt", PTB = "lrptb", PV = "lrpv"),
  `2013` = c(CID = "lrpps", DEM = "lrdem", MDB = "lrpmdb", PCDOB = "lrpcdob", PDT = "lrpdt", PL = "lrpr",
             PP = "lrpp_ppb", PSB = "lrpsb", PSD = "lrpsd", PSDB = "lrpsdb", PSOL = "lrpsol", PT = "lrpt",
             PTB = "lrptb", PV = "lrpv", SARNEY = "lrsarney", COLLOR = "lrcollor", ITAMAR = "lritamar",
             FHC = "lrfhc", LULA = "lrlula", DILMA = "lrdilma"),
  `2017` = c(CID = "lrpps", DEM = "lrdem", MDB = "lrpmdb", PCDOB = "lrpcdob", PDT = "lrpdt", PL = "lrpr",
             PODE = "lrptn", PP = "lrpp_ppb", PROS = "lrpros", PSB = "lrpsb", PSC = "lrpsc", PSD = "lrpsd",
             PSDB = "lrpsdb", PSOL = "lrpsol", PT = "lrpt", PTB = "lrptb", PV = "lrpv", REDE = "lrrede",
             REP = "lrprb", SD = "lrsd", SARNEY = "lrsarney", COLLOR = "lrcollor", ITAMAR = "lritamar",
             FHC = "lrfhc", LULA = "lrlula", DILMA = "lrdilma", TEMER = "lrtemer"),
  `2021` = c(BOLSONARO = "lrbolsonaro", CID = "lrcid", DEM = "lrdem", MDB = "lrmdb", NOVO = "lrnovo",
             PCDOB = "lrpcdob", PDT = "lrpdt", PL = "lrpl", PODE = "lrpode", PP = "lrpp_ppb", PROS = "lrpros",
             PSB = "lrpsb", PSC = "lrpsc", PSD = "lrpsd", PSDB = "lrpsdb", PSL = "lrpsl", PSOL = "lrpsol",
             PT = "lrpt", PTB = "lrptb", REP = "lrrep", SD = "lrsd"))
map$`2001` <- map$`1997`; map$`2005` <- map$`1997`
long <- do.call(rbind, lapply(names(map), function(w) { bw <- b[b$wave == as.integer(w), ]
  do.call(rbind, lapply(names(map[[w]]), function(lab) {
    v <- bw[[map[[w]][[lab]]]]; ok <- !is.na(v) & v >= 1 & v <= 10
    if (!any(ok)) return(NULL)
    data.frame(id = bw$uniqueid[ok], item = paste(w, lab), P = as.numeric(v[ok])) })) }))
# respondents need >= 3 placements with variation to identify a_i, b_i
keep <- names(which(tapply(long$P, long$id, function(x) length(x) >= 3 && sd(x) > 0)))
long <- long[long$id %in% keep, ]
items <- sort(unique(long$item)); ids <- sort(unique(long$id))
ii <- match(long$item, items); rr <- match(long$id, ids)
pi <- tapply(long$P, long$item, mean)[items]; pi <- (pi - mean(pi)) / sd(pi)
for (it in 1:500) {
  # respondent regressions P = a + b*pi
  x <- pi[ii]; mx <- tapply(x, rr, mean); my <- tapply(long$P, rr, mean)
  bb <- tapply((x - mx[rr]) * (long$P - my[rr]), rr, sum) / tapply((x - mx[rr])^2, rr, sum)
  aa <- my - bb * mx
  new <- tapply(bb[rr] * (long$P - aa[rr]), ii, sum) / tapply(bb[rr]^2, ii, sum)
  new <- (new - mean(new)) / sd(new)
  if (max(abs(new - pi)) < 1e-10) { pi <- new; break }; pi <- new }
cat("ALS iterations:", it, "| respondents:", length(ids), "| item-waves:", length(items), "\n")
est <- data.frame(year = as.integer(sub(" .*", "", items)), label = sub("^[0-9]+ ", "", items), pi = as.numeric(pi))
m <- merge(est, st, by.x = c("year", "label"), by.y = c("year", "party.or.pres"))
fit <- lm(ideo ~ pi, m); m$pi_s <- fitted(fit)
cat(sprintf("Matched %d of %d stored party/president-waves\n", nrow(m), nrow(st)))
res <- do.call(rbind, lapply(split(m, m$year), function(d) data.frame(year = d$year[1], n = nrow(d),
  corr = cor(d$pi, d$ideo), max_abs_diff = max(abs(d$pi_s - d$ideo)))))
res$pass <- res$corr >= 0.99 & res$max_abs_diff <= 0.05
print(res, row.names = FALSE)
gate <- all(res$pass[res$year >= 2001])
cat("A1.5 BLS scaling reproduction (waves 2001-2021):", if (gate) "PASS" else "FAIL", "\n")
write.csv(res, "audit/out/bls_scaling_repro.csv", row.names = FALSE)
write.csv(m[, c("year", "label", "ideo", "pi_s")], "audit/out/bls_scaling_repro_items.csv", row.names = FALSE)
