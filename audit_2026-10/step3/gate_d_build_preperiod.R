# =============================================================================
# gate_d_build_preperiod.R — federal-deputy Dalton index for 2002 and 2006
# from raw TSE files (votacao_partido_munzona_{2002,2006}, SHA-256 verified),
# built by the rules fixed in amendment A1.2. Also reconciles the party-file
# totals to the TSE detalhe file (official valid votes, same release).
# Canary: the same function rebuilds the stored 2010 deputy Dalton from
# painel_ideologico_deputado_federal.rds.
# =============================================================================
D <- Sys.getenv("SS_DATA_DIR", "D"); TSE <- Sys.getenv("SS_TSE_DIR", "tse")
rd <- function(f) as.data.frame(data.table::fread(file.path(TSE, f), sep = ";", encoding = "Latin-1",
                                                 colClasses = "character", showProgress = FALSE))
num <- function(v) as.numeric(v)

xw <- as.data.frame(haven::read_dta(file.path(TSE, "mun_ibge_tse.dta")))
mun <- as.data.frame(readRDS(file.path(D, "municipios_ibge.rds")))
xw$micro <- mun$microregion_code[match(as.integer(xw$cod_mun), as.integer(mun$municipality_code_ibge))]
bls <- as.data.frame(readRDS(file.path(D, "bls9_estimates_partiespresidents_long.rds")))

dalton <- function(v, y) { w <- v / sum(v); yb <- sum(w * y); sqrt(sum(w * (y - yb)^2)) }

# canary on the stored 2010 panel
pi <- as.data.frame(readRDS(file.path(D, "painel_ideologico_deputado_federal.rds")))
pi <- pi[pi$round == 1 & pi$year == 2010 & !is.na(pi$ideo) & pi$votes > 0, ]
can <- sapply(split(pi, pi$microregion_code), function(d) { a <- tapply(d$votes, d$party, sum)
  dalton(a, tapply(d$ideo, d$party, `[`, 1)[names(a)]) })
dep <- as.data.frame(readRDS(file.path(D, "dalton_panel_deputado_federal.rds")))
st <- dep$P_dalton[dep$year == 2010][match(names(can), as.character(dep$microregion_code[dep$year == 2010]))]
cat(sprintf("Canary 2010: rebuilt vs stored deputy Dalton, max|diff| = %.3e over %d micros\n",
            max(abs(can - st)), length(can)))

relabel <- c("PFL" = "DEM", "PMDB" = "MDB", "PPS" = "CID", "PC DO B" = "PCDOB", "PCDOB" = "PCDOB",
             "PPB" = "PP", "PP" = "PP", "PL" = "PL", "PT" = "PT", "PSDB" = "PSDB", "PTB" = "PTB",
             "PSB" = "PSB", "PDT" = "PDT")
out <- list(); rec <- list()
for (y in c(2002, 2006)) {
  p <- rd(sprintf("votacao_partido_munzona_%d_BRASIL.csv", y))
  p <- p[p$NR_TURNO == "1" & p$DS_CARGO == "Deputado Federal" & p$SG_UF != "ZZ", ]
  p$v <- num(p$QT_VOTOS_NOMINAIS) + num(p$QT_VOTOS_LEGENDA)
  d <- rd(sprintf("detalhe_votacao_munzona_%d_BRASIL.csv", y))
  d <- d[d$NR_TURNO == "1" & d$DS_CARGO == "Deputado Federal" & d$SG_UF != "ZZ", ]
  rec[[as.character(y)]] <- data.frame(year = y, party_file_total = sum(p$v),
    detalhe_valid = sum(num(d$QT_VOTOS_NOMINAIS_VALIDOS) + num(d$QT_TOTAL_VOTOS_LEG_VALIDOS)),
    detalhe_QT_TOTAL_VOTOS_VALIDOS_field = sum(num(d$QT_TOTAL_VOTOS_VALIDOS)),
    rel_diff = sum(p$v) / sum(num(d$QT_VOTOS_NOMINAIS_VALIDOS) + num(d$QT_TOTAL_VOTOS_LEG_VALIDOS)) - 1)
  p$micro <- xw$micro[match(as.integer(p$CD_MUNICIPIO), as.integer(xw$CD_UE))]
  # the crosswalk has no TSE code for these two; mapped by name to their IBGE-2010 microregion
  p$micro[is.na(p$micro) & p$SG_UF == "DF"] <- 53001L
  p$micro[is.na(p$micro) & p$SG_UF == "PE" & grepl("NORONHA", p$NM_MUNICIPIO)] <- 26019L
  miss <- sum(p$v[is.na(p$micro)]) / sum(p$v)
  um <- unique(p[is.na(p$micro), c("SG_UF", "CD_MUNICIPIO", "NM_MUNICIPIO")])
  cat(sprintf("%d: %d TSE municipalities unmatched: %s\n", y, nrow(um), paste(head(paste(um$SG_UF, um$NM_MUNICIPIO), 12), collapse = "; ")))
  lab <- toupper(trimws(p$SG_PARTIDO)); p$bls <- relabel[lab]
  wave <- if (y == 2002) 2001 else 2005
  sc <- setNames(bls$ideo[bls$year == wave], bls$party.or.pres[bls$year == wave])
  p$ideo <- sc[p$bls]
  cov <- sum(p$v[!is.na(p$ideo)]) / sum(p$v)
  q <- p[!is.na(p$micro) & !is.na(p$ideo), ]
  P <- sapply(split(q, q$micro), function(dd) { a <- tapply(dd$v, dd$bls, sum); dalton(a, sc[names(a)]) })
  out[[as.character(y)]] <- data.frame(micro = names(P), year = y, P_dalton = as.numeric(P))
  cat(sprintf("%d: votes unmatched to a microregion %.4f%% | scored coverage %.4f | micros %d | parties scored: %s\n",
              y, 100 * miss, cov, length(P), paste(sort(unique(q$bls)), collapse = ",")))
  cat(sprintf("%d: unscored labels with >0.5%% of votes: %s\n", y,
      paste(names(which(tapply(p$v, lab, sum)[is.na(relabel[names(tapply(p$v, lab, sum))])] / sum(p$v) > 0.005)), collapse = ",")))
}
pre <- do.call(rbind, out); rec <- do.call(rbind, rec)
print(rec)
dir.create("audit/out", showWarnings = FALSE)
saveRDS(pre, "audit/out/dalton_deputado_2002_2006.rds")
write.csv(rec, "audit/out/gate_a_tse_2002_2006_internal.csv", row.names = FALSE)
