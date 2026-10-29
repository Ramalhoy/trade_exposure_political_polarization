# =============================================================================
# repair_governor_2022.R — amendment A3.2. Drops 2022 governor candidates whose
# votes TSE marks as annulled (NM_TIPO_DESTINACAO_VOTOS != "Válido"), matched by
# state + party (one governor candidate per party per state), rebuilds the 2022
# governor indices with the stored formulas (canary on 2010 first), and checks
# state totals against raw TSE detalhe. Writes a repaired copy in audit/out;
# the pipeline file is not overwritten.
# =============================================================================
invisible(Sys.setlocale("LC_ALL", "C.UTF-8")); library(data.table)
D <- Sys.getenv("SS_DATA_DIR", "D")
g <- as.data.table(readRDS(file.path(D, "painel_ideologico_governador_ajustado.rds")))
d <- as.data.table(readRDS(file.path(D, "dalton_panel_governador_ajustado.rds")))
idx <- function(s) s[, { w <- votes / sum(votes); yb <- sum(w * ideo)
  .(P_dalton = sqrt(sum(w * (ideo - yb)^2)), y_bar = yb, P_center = sum(w * (abs(ideo) > 0.25))) }, by = microregion_code]
can <- merge(idx(g[round == 1 & year == 2010 & scored == TRUE]), d[year == 2010], by = "microregion_code")
cat(sprintf("canary 2010 max|diff|: Dalton %.1e, y_bar %.1e, P_center %.1e\n", max(abs(can$P_dalton.x - can$P_dalton.y)),
            max(abs(can$y_bar.x - can$y_bar.y)), max(abs(can$P_center.x - can$P_center.y))))
an <- fread("tse10/gov2022.csv")[DESTINACAO != "Válido"]
print(an[, .(SG_UF, SG_PARTIDO, NM_URNA, DESTINACAO, QT_NOM)])
g[, drop := year == 2022 & round == 1 & paste(state, toupper(party)) %in% paste(an$SG_UF, toupper(an$SG_PARTIDO))]
cat("panel rows dropped:", g[drop == TRUE, .N], "| votes dropped:", g[drop == TRUE, sum(votes)], "| annulled in TSE:", sum(an$QT_NOM), "\n")
det <- fread("tse10/detalhe_2022.csv.gz")[NR_TURNO == 1 & CD_CARGO == 3, .(official = sum(as.numeric(QT_VOTOS_NOMINAIS_VALIDOS))), by = .(state = SG_UF)]
chk <- merge(g[year == 2022 & round == 1 & drop == FALSE, .(panel = sum(votes)), by = state], det, by = "state")
chk[, rel := panel / official - 1]
cat(sprintf("after repair: max |state rel diff| %.5f%% | national rel diff %+.5f%% | states over 0.1%%: %d\n",
            100 * max(abs(chk$rel)), 100 * (sum(chk$panel) / sum(chk$official) - 1), sum(abs(chk$rel) > 0.001)))
new22 <- idx(g[year == 2022 & round == 1 & drop == FALSE & scored == TRUE])
rep <- copy(d)[, c("P_dalton", "y_bar", "P_center") := .(P_dalton, y_bar, P_center)]
m <- match(paste(rep$microregion_code, rep$year), paste(new22$microregion_code, 2022))
ch <- which(!is.na(m))
cat(sprintf("2022 cells changed: Dalton %d, y_bar %d (max |change| y_bar %.4f)\n",
            sum(abs(rep$P_dalton[ch] - new22$P_dalton[m[ch]]) > 1e-12), sum(abs(rep$y_bar[ch] - new22$y_bar[m[ch]]) > 1e-12),
            max(abs(rep$y_bar[ch] - new22$y_bar[m[ch]]))))
rep$P_dalton[ch] <- new22$P_dalton[m[ch]]; rep$y_bar[ch] <- new22$y_bar[m[ch]]; rep$P_center[ch] <- new22$P_center[m[ch]]
saveRDS(rep, "audit/out/dalton_panel_governador_repaired.rds")
saveRDS(g[drop == FALSE, !"drop"], "audit/out/painel_ideologico_governador_repaired.rds")
fwrite(chk, "audit/out/governor_2022_repair_check.csv")
