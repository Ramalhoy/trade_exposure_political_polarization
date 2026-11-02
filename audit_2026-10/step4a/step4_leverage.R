# =============================================================================
invisible(Sys.setlocale("LC_ALL", "C.UTF-8"))
# step4_leverage.R — A3.3.7. Top-10 microregions by share of Σ x⊥·x (x = recentred,
# standardised treatment; x⊥ = x residualised on controls + state×year FE), summed
# over the three stacked years. Each is inspected in the raw records:
#   RAIS 2010 FTE (rais_fte.rds): top three CNAE classes, share of microregion FTE;
#   Comex 2010 municipal exports (EXP_2010_MUN.csv): top municipality and top three
#     SH4 lines, shares of microregion exports (municipality -> microregion as cr_s3.R);
#   TSE detalhe 2010 (deputy, round 1): valid votes (nominal + party list) vs the
#     stored panel total, and scored coverage of the panel.
# β̂ re-estimated without the ten (fixest, same x and y scaling): descriptive only.
# =============================================================================
source("audit/ss_core.R"); suppressMessages({ library(data.table); library(fixest) })
nrm <- function(s) { s <- chartr("ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç",
  "AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc", enc2utf8(s)); toupper(gsub("[^A-Za-z]", "", s)) }
mun <- as.data.table(readRDS(file.path(D, "municipios_ibge.rds")))
# ---- raw sources ----
rais <- as.data.table(readRDS(file.path(D, "rais_fte.rds")))
ex <- fread(file.path(D, "EXP_2010_MUN.csv"), colClasses = list(character = c("CO_PAIS", "CO_MUN", "SH4")))
umun <- as.data.table(readxl::read_excel("tab_aux.xlsx", sheet = "13"))
mun[, key := paste(state, nrm(municipality_name))]; umun[, key := paste(SG_UF, nrm(NO_MUN_MIN))]
umun[key == "SP EMBU", key := "SP EMBUDASARTES"]
umun[, ibge := as.integer(mun$municipality_code_ibge[match(key, mun$key)])]
ex[, ibge := fifelse(as.integer(CO_MUN) %in% as.integer(mun$municipality_code_ibge), as.integer(CO_MUN),
                     umun$ibge[match(as.integer(CO_MUN), as.integer(umun$CO_MUN_GEO))])]
ex[, micro := mun$microregion_code[match(ibge, as.integer(mun$municipality_code_ibge))]]
ex[, mname := mun$municipality_name[match(ibge, as.integer(mun$municipality_code_ibge))]]
det <- fread("tse10/detalhe_2010.csv.gz", encoding = "Latin-1")[NR_TURNO == 1 & CD_CARGO == 6 & SG_UF != "ZZ"]
xw <- as.data.table(haven::read_dta("tse/mun_ibge_tse.dta"))
det[, ibge := xw$cod_mun[match(paste(SG_UF, as.integer(CD_MUNICIPIO)), paste(xw$uf, xw$CD_UE))]]
cat(sprintf("TSE 2010 deputy valid votes with no IBGE match: %d\n", det[is.na(ibge), sum(QT_VOTOS_NOMINAIS_VALIDOS + QT_TOTAL_VOTOS_LEG_VALIDOS)]))
det[, micro := mun$microregion_code[match(ibge, as.integer(mun$municipality_code_ibge))]]
tse <- det[, .(tse_valid = sum(as.numeric(QT_VOTOS_NOMINAIS_VALIDOS) + as.numeric(QT_TOTAL_VOTOS_LEG_VALIDOS))), by = micro]
pan <- as.data.table(readRDS(file.path(D, "painel_ideologico_deputado_federal.rds")))[round == 1 & year == 2010]
pv <- pan[, .(panel_votes = sum(votes), scored = sum(votes[!is.na(ideo)]) / sum(votes)), by = .(micro = microregion_code)]
# ---- leverage ----
out <- list(); bet <- list()
for (nm in c("S0", "S3")) {
  des <- if (nm == "S0") { u <- merge_units(W0_1, G0, sec0); build_design(u$W1, u$G, u$strata) } else {
    u <- merge_units(W3_1, G3, sec3); build_design(u$W1, u$G, u$strata) }
  ctrl <- if (nm == "S0") ctrl_base0 else ctrl_base3; P <- proj_maker(ctrl)
  x <- des$zt / sd(des$zt); xp <- as.numeric(P(matrix(x)))
  lev <- tapply(xp * x, df$micro, sum) / sum(xp * x); top <- names(sort(lev, decreasing = TRUE))[1:10]
  d <- data.table(df[, c("micro", "state", "year")], ctrl, y = y_dep, x = x)
  f_all <- feols(as.formula(paste("y ~ x +", paste(names(ctrl), collapse = "+"), "| state^year")), d)
  f_no <- feols(as.formula(paste("y ~ x +", paste(names(ctrl), collapse = "+"), "| state^year")), d[!micro %in% top])
  bet[[nm]] <- data.table(design = nm, beta_all = coef(f_all)[["x"]], beta_without_top10 = coef(f_no)[["x"]],
                          top10_share_of_leverage = sum(lev[top]), n_without = nobs(f_no))
  for (r in top) {
    ri <- as.integer(r)
    ra <- rais[microregion_code == ri][order(-total_fte)]; tf <- sum(ra$total_fte)
    e <- ex[micro == ri]; te <- sum(e$VL_FOB)
    em <- e[, .(v = sum(VL_FOB)), by = mname][order(-v)]; es <- e[, .(v = sum(VL_FOB)), by = SH4][order(-v)]
    out[[paste(nm, r)]] <- data.table(design = nm, rank = match(r, top), micro = r,
      name = mun$microregion_name[match(ri, mun$microregion_code)], state = df$state[match(r, df$micro)],
      lev_share = lev[[r]], x_2014 = x[df$micro == r & df$year == 2014], x_2018 = x[df$micro == r & df$year == 2018],
      x_2022 = x[df$micro == r & df$year == 2022], y_mean = mean(y_dep[df$micro == r]),
      rais_fte = tf, rais_top3 = paste(sprintf("%s %.1f%%", ra$cnae_2[1:3], 100 * ra$total_fte[1:3] / tf), collapse = "; "),
      exp2010_usd = te, exp_top_mun = if (te > 0) sprintf("%s %.1f%%", em$mname[1], 100 * em$v[1] / te) else "none",
      exp_top3_sh4 = if (te > 0) paste(sprintf("%s %.1f%%", es$SH4[1:min(3, nrow(es))], 100 * es$v[1:min(3, nrow(es))] / te), collapse = "; ") else "none",
      tse_valid_2010 = tse[micro == ri, tse_valid], panel_votes_2010 = pv[micro == ri, panel_votes], scored_2010 = pv[micro == ri, scored])
  }
}
tab <- rbindlist(out); tab[, tse_vs_panel := panel_votes_2010 / tse_valid_2010 - 1]
fwrite(tab, "audit/out/step4_leverage_top10.csv"); fwrite(rbindlist(bet), "audit/out/step4_leverage_beta.csv")
print(tab[, .(design, rank, name, state, lev = round(lev_share, 3), rais_top3, exp_top_mun, exp_top3_sh4, tse_vs_panel = signif(tse_vs_panel, 3), scored = round(scored_2010, 3))])
print(rbindlist(bet))
