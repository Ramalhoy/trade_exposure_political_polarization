# Outcome-only construct diagnostic (no treatment): how much of each office's Dalton
# index is a function of the leading party's scored vote share, and scored coverage.
D <- Sys.getenv("SS_DATA_DIR", "D")
rd <- function(f) as.data.frame(readRDS(file.path(D, f)))
offices <- list(
  president = list(p = rd("painel_ideologico_presidencial.rds"),   d = rd("dalton_panel_presidencial.rds")),
  governor  = list(p = rd("painel_ideologico_governador_ajustado.rds"), d = rd("dalton_panel_governador_ajustado.rds")),
  deputy    = list(p = rd("painel_ideologico_deputado_federal.rds"),    d = rd("dalton_panel_deputado_federal.rds")))
for (o in names(offices)) {
  p <- offices[[o]]$p; p <- p[p$round == 1, ]
  key <- paste(p$microregion_code, p$year)
  cov <- tapply(p$votes * !is.na(p$ideo), p$year, sum) / tapply(p$votes, p$year, sum)
  ps <- p[!is.na(p$ideo), ]; ps$k <- paste(ps$microregion_code, ps$year)
  # aggregate to party (deputy rows are party x micro already; president/governor candidate = party)
  agg <- aggregate(votes ~ k + party + year, ps, sum)
  tot <- tapply(agg$votes, agg$k, sum); agg$v <- agg$votes / tot[agg$k]
  top1 <- tapply(agg$v, agg$k, max); npar <- tapply(agg$v > 0, agg$k, sum)
  d <- offices[[o]]$d; d$k <- paste(d$microregion_code, d$year)
  d$top1 <- top1[d$k]; d$npar <- npar[d$k]
  cat(sprintf("\n== %s ==\n", o))
  for (y in c(2010, 2014, 2018, 2022)) {
    dy <- d[d$year == y & !is.na(d$top1), ]
    r2 <- summary(lm(P_dalton ~ top1 + I(top1^2), dy))$r.squared
    cat(sprintf("%d  scored-vote coverage %.4f | R2(Dalton ~ top1 + top1^2) %.3f | median scored parties/cell %g | cells %d\n",
                y, cov[as.character(y)], r2, median(dy$npar), nrow(dy)))
  }
}

cat("\nWithin state-year (what the design uses): R2 of FE-residualised Dalton on FE-residualised top1, top1^2\n")
mun <- as.data.frame(readRDS(file.path(D, "dalton_panel_presidencial.rds")))
for (o in names(offices)) {
  p <- offices[[o]]$p; p <- p[p$round == 1 & !is.na(p$ideo), ]
  st <- unique(p[, c("microregion_code", "state")])
  p$k <- paste(p$microregion_code, p$year)
  agg <- aggregate(votes ~ k + party, p, sum); tot <- tapply(agg$votes, agg$k, sum); agg$v <- agg$votes / tot[agg$k]
  top1 <- tapply(agg$v, agg$k, max)
  d <- offices[[o]]$d; d$k <- paste(d$microregion_code, d$year); d$top1 <- top1[d$k]
  d$state <- st$state[match(d$microregion_code, st$microregion_code)]
  out <- sapply(c(2010, 2014, 2018, 2022), function(y) { dy <- d[d$year == y & !is.na(d$top1) & !is.na(d$state), ]
    f <- factor(dy$state); r <- function(v) resid(lm(v ~ f))
    yv <- r(dy$P_dalton); X <- cbind(r(dy$top1), r(dy$top1^2)); summary(lm(yv ~ X))$r.squared })
  cat(sprintf("%-9s %s\n", o, paste(sprintf("%d: %.3f", c(2010, 2014, 2018, 2022), out), collapse = " | ")))
}
