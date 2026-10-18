# A2.2: party-level check of the stored deputy panel (2010, 2014) against raw TSE candidate files.
# Nominal votes by party: candidate file (all situations) vs stored votes_nominal; plus the
# breakdown by candidacy situation, and detalhe nominal-valid totals.
library(data.table); D <- Sys.getenv("SS_DATA_DIR", "D")
pi <- as.data.table(readRDS(file.path(D, "painel_ideologico_deputado_federal.rds")))[round == 1]
for (y in c(2010, 2014)) {
  d <- fread(sprintf("tse10/dep_federal_%d.csv.gz", y))
  det <- fread(sprintf("tse10/detalhe_%d.csv.gz", y))[CD_CARGO == 6 & NR_TURNO == 1]
  cat(sprintf("\n== %d: candidate-file nominal %s | detalhe nominal valid %s | stored nominal %s | stored legenda %s | detalhe legenda valid %s\n",
      y, format(sum(d$QT_NOM), big.mark = ","), format(sum(det$QT_VOTOS_NOMINAIS_VALIDOS), big.mark = ","),
      format(pi[year == y, sum(votes_nominal)], big.mark = ","), format(pi[year == y, sum(votes_legenda)], big.mark = ","),
      format(sum(det$QT_TOTAL_VOTOS_LEG_VALIDOS), big.mark = ",")))
  print(d[, .(votes = sum(QT_NOM)), by = .(SIT_CAND, DET_SIT)][order(-votes)][1:8])
  a <- merge(d[, .(cand = sum(QT_NOM)), by = .(party = toupper(SG_PARTIDO))],
             pi[year == y, .(stored = sum(votes_nominal)), by = .(party = toupper(party))], by = "party", all = TRUE)
  a[is.na(a)] <- 0; a[, diff := stored - cand]
  cat(sprintf("party-level nominal: max |stored - candidate file| = %s over %d parties\n", format(max(abs(a$diff)), big.mark = ","), nrow(a)))
  if (any(a$diff != 0)) print(a[diff != 0])
}
