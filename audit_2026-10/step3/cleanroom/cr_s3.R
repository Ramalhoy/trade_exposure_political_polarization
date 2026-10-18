# =============================================================================
# cr_s3.R — CLEAN-ROOM rebuild of the S3_N2ex treatment (gate e). Imports no
# project code. From the written spec (packet_D_spec.md D.2, D.4.1, D.4.2;
# amendment A1.4) and raw files:
#   EXP_2010_MUN.csv (Comex Stat, municipality x SH4 x destination, 2010)
#   BACI_HS07_Y{2010,2014,2018,2022}_V202601.csv (CEPII), country_codes
#   TABELAS_AUXILIARES.xlsx (Comex PAIS and UF_MUN tables)
#   rais_fte.rds (total formal FTE per microregion = L_r^ALL), municipios_ibge.rds
#   cpi_us.rds; decision tables kept in D1_s_rd.rds: comex_baci_area_map,
#   panel_persistent_fold (country-code harmonisation, documented as [D-20]).
# Spec choices:
#   (T1) Comex municipality codes not in the IBGE list are matched by
#        (UF, accent-free name) through the Comex UF_MUN table.
#   (T2) X_rd,2010 in current 2010 USD; s_rd = X_rd / L_r^ALL (N2).
#   (T3) Brazil (BACI 76) removed as exporter from every m_dpt; omega_pd from
#        BACI Brazil rows (i == 76), 2010, HS6.
#   (T4) BACI values deflated by US CPI (2010 = 100) before the arc operator;
#        arc(a, b) = (a - b) / ((a + b) / 2), 0 when both are 0.
#   (T5) Entrepots NLD SGP HKG ARE LCA dropped as columns, no renormalisation.
# =============================================================================
invisible(Sys.setlocale("LC_ALL", "C.UTF-8")); library(data.table)
D <- Sys.getenv("SS_DATA_DIR", "D"); PD <- file.path(D, "output", "packet_D")
nrm <- function(s) { s <- chartr("ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç",
                                 "AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc", enc2utf8(s))
  toupper(gsub("[^A-Za-z]", "", s)) }
# (T1b) names changed between the Comex table and IBGE-2010 list, matched by hand:
renamed <- c("SP EMBU" = "SP EMBUDASARTES")
ex  <- fread(file.path(D, "EXP_2010_MUN.csv"), colClasses = list(character = c("CO_PAIS", "CO_MUN", "SH4")))
pais <- as.data.table(readxl::read_excel(Sys.getenv("SS_TABAUX", "tab_aux.xlsx"), sheet = "10"))
umun <- as.data.table(readxl::read_excel(Sys.getenv("SS_TABAUX", "tab_aux.xlsx"), sheet = "13"))
mun  <- as.data.table(readRDS(file.path(D, "municipios_ibge.rds")))
d1   <- readRDS(file.path(PD, "D1_s_rd.rds"))
cc   <- fread(file.path(D, "baci", "country_codes_V202601.csv"))
cpi  <- as.data.table(readRDS(file.path(D, "cpi_us.rds")))

# ---- municipality -> microregion ------------------------------------------------
mun[, key := paste(state, nrm(municipality_name))]
umun[, key := paste(SG_UF, nrm(NO_MUN_MIN))]
umun[key %in% names(renamed), key := renamed[key]]
umun[, ibge := as.integer(mun$municipality_code_ibge[match(key, mun$key)])]
ex[, ibge := fifelse(as.integer(CO_MUN) %in% mun$municipality_code_ibge, as.integer(CO_MUN),
                     umun$ibge[match(as.integer(CO_MUN), as.integer(umun$CO_MUN_GEO))])]
cat(sprintf("Comex 2010 value with no IBGE municipality after name match: %.5f%%\n",
            100 * ex[is.na(ibge), sum(VL_FOB)] / ex[, sum(VL_FOB)]))
ex[, micro := mun$microregion_code[match(ibge, mun$municipality_code_ibge)]]

# ---- destination -> BACI country code --------------------------------------------
ex[, iso3 := pais$CO_PAIS_ISOA3[match(CO_PAIS, pais$CO_PAIS)]]
ex[, baci := cc$country_code[match(iso3, cc$country_iso3)]]
am <- d1$comex_baci_area_map; ex[iso3 %in% names(am), baci := am[iso3]]
fold <- d1$panel_persistent_fold
foldf <- function(v) { s <- as.character(v); i <- s %in% names(fold); v[i] <- fold[s[i]]; v }
ex[, baci := foldf(baci)]
cat(sprintf("Comex 2010 value with no BACI destination: %.5f%% (iso3: %s)\n",
            100 * ex[is.na(baci), sum(VL_FOB)] / ex[, sum(VL_FOB)], paste(unique(ex[is.na(baci), iso3]), collapse = ",")))
X <- ex[!is.na(micro) & !is.na(baci), .(x = sum(VL_FOB)), by = .(micro, d = baci)]

# ---- shares N2 ----------------------------------------------------------------------
rais <- as.data.table(readRDS(file.path(D, "rais_fte.rds")))
Lall <- rais[, .(L = sum(total_fte)), by = .(micro = microregion_code)]
X[, s := x / Lall$L[match(micro, Lall$micro)]]

# ---- BACI shocks -------------------------------------------------------------------
defl <- function(t) cpi$cpi[cpi$year == t] / 100
rd <- function(t) { b <- fread(file.path(D, "baci", sprintf("BACI_HS07_Y%d_V202601.csv", t)),
                               select = c("i", "j", "k", "v"))
  b[, `:=`(i = foldf(i), j = foldf(j))]; b }
b10 <- rd(2010)
om <- b10[i == 76, .(v = sum(v)), by = .(d = j, p = k)][, w := v / sum(v), by = d][, .(d, p, w)]
mrow <- function(b, t) b[i != 76, .(m = sum(v) / defl(t)), by = .(d = j, p = k)]
m10 <- mrow(b10, 2010); rm(b10); gc()
arc <- function(a, b) fifelse((a + b) > 0, (a - b) / ((a + b) / 2), 0)
G <- rbindlist(lapply(c(2014, 2018, 2022), function(t) {
  mt <- mrow(rd(t), t)
  z <- merge(om, m10, by = c("d", "p"), all.x = TRUE); setnames(z, "m", "m0")
  z <- merge(z, mt, by = c("d", "p"), all.x = TRUE)
  z[is.na(m0), m0 := 0]; z[is.na(m), m := 0]
  r <- z[, .(g = sum(w * arc(m, m0))), by = d][, t := t]; rm(mt, z); gc(); r }))

# ---- treatment -----------------------------------------------------------------------
ent <- cc$country_code[cc$country_iso3 %in% c("NLD", "SGP", "HKG", "ARE", "LCA")]
keep <- setdiff(intersect(unique(X$d), unique(G$d)), ent)
Z <- merge(X[d %in% keep], G[d %in% keep], by = "d", allow.cartesian = TRUE)
z <- Z[, .(z_cr = sum(s * g)), by = .(micro, year = t)]
saveRDS(list(z = z, G = G, X = X, keep = keep), "audit/out/cleanroom_s3.rds")
cat("clean-room S3: destinations", length(keep), "| exporting micros", uniqueN(X$micro), "\n")
