# =============================================================================
# s5_votes.R — Step 5 checks of every electoral number in the dissertation text
# (§3.2 coverage, Table 2 BLS waves, the PSL rule, the 2018 centre band, Tables A1/A2),
# from the raw TSE files:
#   tse_pres/pres_cand_YYYY.csv.gz  = votacao_candidato_munzona_YYYY_BR.csv (president),
#                                     unzipped from the device's raw TSE zips (SHA256SUMS.txt)
#   tse10/detalhe_YYYY.csv.gz       = detalhe_votacao_munzona (all offices, incl. ZZ/VT)
# and the stored BLS scores (bls9_estimates_partiespresidents_long.rds) and the stored
# presidential panels (painel_ideologico_presidencial.rds, dalton_panel_presidencial.rds).
# =============================================================================
invisible(Sys.setlocale("LC_ALL", "C.UTF-8")); suppressMessages(library(data.table))
out <- list(); add <- function(item, value, source) out[[length(out) + 1]] <<- data.table(item, value = as.character(value), source)
rd <- function(f) fread(f, encoding = "Latin-1", showProgress = FALSE)
for (y in c(2010, 2014, 2018, 2022)) {
  pc <- rd(sprintf("tse_pres/pres_cand_%d.csv.gz", y))[NR_TURNO == 1 & CD_CARGO == 1]
  vcol <- if ("QT_VOTOS_NOMINAIS_VALIDOS" %in% names(pc)) "QT_VOTOS_NOMINAIS_VALIDOS" else "QT_VOTOS_NOMINAIS"
  pc[, v := as.numeric(get(vcol))]
  if (vcol == "QT_VOTOS_NOMINAIS") add(sprintf("%d raw file has no _VALIDOS column; candidate statuses", y),
      paste(unique(pc$DS_SITUACAO_CANDIDATURA), collapse = "|"), "pres_cand")
  tot <- sum(pc$v); zz <- pc[SG_UF == "ZZ", sum(v)]; vt <- if ("ST_VOTO_EM_TRANSITO" %in% names(pc)) pc[ST_VOTO_EM_TRANSITO == "S", sum(v)] else NA
  de <- rd(sprintf("tse10/detalhe_%d.csv.gz", y))[NR_TURNO == 1 & CD_CARGO == 1]
  add(sprintf("%d president r1 national valid votes (cand file, incl. abroad)", y), tot, sprintf("pres_cand_%d %s", y, vcol))
  add(sprintf("%d president r1 valid votes (detalhe QT_TOTAL_VOTOS_VALIDOS)", y), sum(de$QT_TOTAL_VOTOS_VALIDOS), sprintf("detalhe_%d", y))
  add(sprintf("%d ZZ (abroad) valid votes", y), zz, sprintf("pres_cand_%d SG_UF=='ZZ'", y))
  add(sprintf("%d ZZ share of national (pct)", y), round(100 * zz / tot, 3), "")
  add(sprintf("%d VT (in-transit, ST_VOTO_EM_TRANSITO=='S') valid votes", y), vt, sprintf("pres_cand_%d", y))
  add(sprintf("%d detalhe rows SG_UF=='VT'", y), de[SG_UF == "VT", sum(QT_TOTAL_VOTOS_VALIDOS)], sprintf("detalhe_%d", y))
  pp <- pc[, .(votes = sum(v)), by = .(party = SG_PARTIDO)][order(-votes)]
  bls_wave <- c(`2010` = 2009, `2014` = 2013, `2018` = 2017, `2022` = 2021)[[as.character(y)]]
  B <- as.data.table(readRDS("D/bls9_estimates_partiespresidents_long.rds"))[year == bls_wave]
  pp[, share := 100 * votes / tot]
  pp[, scored_in_wave := party %in% B$party.or.pres]
  fwrite(pp, sprintf("step5/out/pres_party_votes_%d.csv", y))
  add(sprintf("%d parties with no score in BLS wave %d (raw)", y, bls_wave), paste(pp[scored_in_wave == FALSE, sprintf("%s %s (%.2f%%)", party, format(votes, big.mark = ","), share)], collapse = "; "), sprintf("pres_cand_%d + BLS long, wave %d", y, bls_wave))
  add(sprintf("%d unscored share of national valid (pct, raw)", y), round(pp[scored_in_wave == FALSE, sum(share)], 2), "")
  # stored panel: scored share among microregion-assigned votes, round 1
  P <- as.data.table(readRDS("D/painel_ideologico_presidencial.rds"))[year == y & round == 1]
  add(sprintf("%d stored panel: scored share of microregion-assigned votes (pct)", y), round(100 * P[!is.na(ideo), sum(votes)] / P[, sum(votes)], 2), "painel_ideologico_presidencial.rds")
  add(sprintf("%d stored panel: microregions", y), uniqueN(P$microregion_code), "painel_ideologico_presidencial.rds")
  add(sprintf("%d stored panel total votes vs raw national minus ZZ minus VT", y), P[, sum(votes)] - (tot - zz - ifelse(is.na(vt), 0, vt)), "panel minus raw")
  add(sprintf("%d stored panel: party scores used", y), paste(unique(P[!is.na(ideo), sprintf("%s=%.3f", party, ideo)]), collapse = " "), "painel_ideologico_presidencial.rds")
}
# BLS scores: PSL / Bolsonaro and the centre band [-0.25, 0.25]
B <- as.data.table(readRDS("D/bls9_estimates_partiespresidents_long.rds"))
add("Waves in the BLS file", paste(sort(unique(B$year)), collapse = ","), "bls9_estimates_partiespresidents_long.rds")
add("BLS 2017 (wave 8) contains PSL?", "PSL" %in% B[year == 2017]$party.or.pres, "same")
add("BLS 2017 (wave 8) contains BOLSONARO?", "BOLSONARO" %in% B[year == 2017]$party.or.pres, "same")
add("Waves containing BOLSONARO", paste(B[party.or.pres == "BOLSONARO", year], collapse = ","), "same")
D <- as.data.table(readRDS("D/dalton_panel_presidencial.rds"))
add("P_center 2018: min / max across microregions", paste(range(D[year == 2018]$P_center), collapse = " / "), "dalton_panel_presidencial.rds")
add("P_center == 1 in 2018: microregions", D[year == 2018, sum(abs(P_center - 1) < 1e-12)], "same")
fwrite(rbindlist(out), "step5/out/s5_votes.csv"); print(rbindlist(out), nrows = 200)
# Stored-panel party totals (microregion-assigned, round 1) for Table A2
P <- as.data.table(readRDS("D/painel_ideologico_presidencial.rds"))[round == 1, .(votes = sum(votes), scored = !anyNA(ideo)), by = .(year, party)][order(year, -votes)]
fwrite(P, "step5/out/pres_party_votes_panel.csv")
