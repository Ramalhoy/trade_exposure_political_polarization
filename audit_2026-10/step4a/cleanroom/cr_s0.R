# =============================================================================
# cr_s0.R — CLEAN-ROOM rebuild of the S0 treatment (gate e). Imports no
# project code. Written from the written specification only (PDF eq. 5 and
# Appendix B; amendment A1.4) plus the decision tables that ARE data:
#   rais_fte.rds (RAIS 2010 FTE by microregion x CNAE 2.0 class)
#   exports_national_ncm.rds (Comex Stat, national exports by NCM-8, USD FOB)
#   CNAE20_ISIC4.xls (IBGE/CONCLA correspondence; 1/n split where 1-to-many)
#   ncm_isic_match_v7.rds (NCM-6 -> ISIC weights incl. the documented
#     primary-industry overrides and recovery waterfall — a decision table)
#   composite_map_v7.rds (ISIC classes collapsed into composites — decision table)
#   hs2007_hs2012.csv, hs2017_hs2012.csv (HS vintage bridges)
#   cpi_us.rds (US CPI, 2010 = 100)
# Spec choices made here, each listed so divergences can be attributed:
#   (S1) NCM-6 = first six digits; HS chapters 98-99 excluded.
#   (S2) vintage bridge applied by year: HS2007 codes for 2010-2011,
#        HS2017 codes for 2017-2021; identity otherwise.
#   (S3) value in constant 2010 USD (CPI), in units of USD 10,000 (PDF p.37).
#   (S4) shares s_rj = L_rj / L_r^ALL (total formal FTE, all classes).
#   (S5) universe = composites with employment > 0 and exports > 0 in
#        2010, 2014, 2018 and 2022 (Appendix B).
#   (S6) g_jt = (EXP_jt - EXP_j,2010) / L_j,2010, L_j = sum_r L_rj.
# =============================================================================
D <- Sys.getenv("SS_DATA_DIR", "D")
YRS <- c(2010, 2014, 2018, 2022)
rais <- as.data.frame(readRDS(file.path(D, "rais_fte.rds")))
ex   <- as.data.frame(readRDS(file.path(D, "exports_national_ncm.rds")))
cx   <- as.data.frame(readxl::read_excel(Sys.getenv("SS_CNAE_XLS", "cnae_isic.xls"), sheet = 1, col_names = FALSE))
m    <- as.data.frame(readRDS(file.path(D, "ncm_isic_match_v7.rds")))
comp <- as.data.frame(readRDS(file.path(D, "composite_map_v7.rds")))
cpi  <- as.data.frame(readRDS(file.path(D, "cpi_us.rds")))
b07  <- read.csv(file.path(D, "hs2007_hs2012.csv"), colClasses = "character")
b17  <- read.csv(file.path(D, "hs2017_hs2012.csv"), colClasses = "character")

# ---- CNAE class -> ISIC (1/n) --------------------------------------------------
cx <- cx[grepl("^[0-9]{2}\\.[0-9]{2}-[0-9]$", cx[[1]]) & grepl("^[0-9]{4}$", cx[[3]]), c(1, 3)]
names(cx) <- c("cnae", "isic4"); cx$cnae <- gsub("[.-]", "", cx$cnae); cx <- unique(cx)
cx$w <- 1 / as.numeric(table(cx$cnae)[cx$cnae])
cmap <- setNames(comp$isic_composite, comp$isic4)
to_comp <- function(k) ifelse(k %in% names(cmap), cmap[k], k)

# ---- employment ------------------------------------------------------------------
rais$cnae <- substr(rais$cnae_2, 1, 5)
L_all <- tapply(rais$total_fte, rais$microregion_code, sum)
e <- merge(rais[, c("microregion_code", "cnae", "total_fte")], cx, by = "cnae")
e$j <- to_comp(e$isic4); e$L <- e$total_fte * e$w
Lrj <- aggregate(L ~ microregion_code + j, e, sum)

# ---- exports ---------------------------------------------------------------------
ex <- ex[ex$ano %in% YRS, ]
ex$hs6 <- substr(sprintf("%08s", ex$id_ncm), 1, 6)
ex <- ex[!substr(ex$hs6, 1, 2) %in% c("98", "99"), ]
br <- function(hs6, b) { i <- match(sub("^0", "", hs6), sub("^0", "", b$hs6_from))
  out <- hs6; out[!is.na(i)] <- sprintf("%06d", as.integer(b$hs6_to[i[!is.na(i)]])); out }
ex$hs6[ex$ano <= 2011] <- br(ex$hs6[ex$ano <= 2011], b07)
ex$hs6[ex$ano >= 2017 & ex$ano <= 2021] <- br(ex$hs6[ex$ano >= 2017 & ex$ano <= 2021], b17)
x <- merge(ex, m, by.x = "hs6", by.y = "ncm6")
x$j <- to_comp(x$isic4)
x$v <- x$valor_fob_dolar * x$w_ncm / (cpi$cpi[match(x$ano, cpi$year)] / 100) / 1e4
EXP <- tapply(x$v, list(x$j, x$ano), sum); EXP[is.na(EXP)] <- 0
cat(sprintf("export value matched to ISIC, share of total by year: %s\n",
    paste(sprintf("%d %.4f", YRS, tapply(x$valor_fob_dolar * x$w_ncm, x$ano, sum) /
                  tapply(ex$valor_fob_dolar, ex$ano, sum)), collapse = " | ")))

# ---- universe, shares, shocks, treatment --------------------------------------
Lj <- tapply(Lrj$L, Lrj$j, sum)
uni <- sort(intersect(names(Lj)[Lj > 0], rownames(EXP)[apply(EXP[, as.character(YRS)] > 0, 1, all)]))
g <- (EXP[uni, c("2014", "2018", "2022")] - EXP[uni, "2010"]) / as.numeric(Lj[uni])
Lrj <- Lrj[Lrj$j %in% uni, ]
Lrj$s <- Lrj$L / as.numeric(L_all[as.character(Lrj$microregion_code)])
z <- do.call(rbind, lapply(c("2014", "2018", "2022"), function(t)
  data.frame(micro = names(tapply(Lrj$s * g[Lrj$j, t], Lrj$microregion_code, sum)), year = as.integer(t),
             z_cr = as.numeric(tapply(Lrj$s * g[Lrj$j, t], Lrj$microregion_code, sum)))))
saveRDS(list(z = z, g = g, uni = uni, Lj = Lj[uni], s = Lrj[, c("microregion_code", "j", "s")]), "audit/out/cleanroom_s0.rds")
cat("clean-room universe:", length(uni), "units\n")
