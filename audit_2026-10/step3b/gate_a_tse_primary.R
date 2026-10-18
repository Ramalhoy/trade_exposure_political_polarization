# Gate (a), TSE rows, rerun against the agency's raw detalhe_votacao_munzona files
# (SHA-256 verified; amendment A2.2). Valid = QT_VOTOS_NOMINAIS_VALIDOS + QT_TOTAL_VOTOS_LEG_VALIDOS,
# round 1, Brazil only (SG_UF != "ZZ"), compared with the round-1 totals of the stored panels.
library(data.table)
D <- Sys.getenv("SS_DATA_DIR", "D")
pv <- function(f) { p <- as.data.table(readRDS(file.path(D, f))); p[round == 1, .(v = sum(votes)), by = year] }
panels <- list(`1` = pv("painel_ideologico_presidencial.rds"), `3` = pv("painel_ideologico_governador_ajustado.rds"),
               `6` = pv("painel_ideologico_deputado_federal.rds"))
nm <- c(`1` = "president", `3` = "governor", `6` = "deputy")
out <- rbindlist(lapply(c(2010, 2014, 2018, 2022), function(y) {
  det <- fread(sprintf("tse10/detalhe_%d.csv.gz", y))[NR_TURNO == 1 & SG_UF != "ZZ" & CD_CARGO %in% c(1, 3, 6)]
  det[, .(official = sum(as.numeric(QT_VOTOS_NOMINAIS_VALIDOS)) + sum(as.numeric(QT_TOTAL_VOTOS_LEG_VALIDOS))), by = CD_CARGO][
    , .(item = paste("TSE", nm[as.character(CD_CARGO)], y, "R1 valid, Brazil"), year = y, cargo = CD_CARGO,
        pipeline = sapply(as.character(CD_CARGO), function(k) panels[[k]][year == y, v]), official)] }))
out[, rel_diff := pipeline / official - 1][, pass := abs(rel_diff) <= 0.001]
print(out[, .(item, pipeline, official, rel_diff = sprintf("%+.5f%%", 100 * rel_diff), pass)])
fwrite(out, "audit/out/gate_a_tse_primary.csv")
