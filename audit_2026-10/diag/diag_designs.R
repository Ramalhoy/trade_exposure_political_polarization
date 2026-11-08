# =============================================================================
# diag_designs.R — DESIGN-ONLY diagnostics (no outcome enters any computation;
# ss_core.R loads the deputy Dalton panel at source time, but nothing here uses it).
# Asked 07/11/2026: before deciding on any extension, measure how many effective
# shocks and microregions would identify each candidate design.
#   S0, S3        current designs (A4 controls), recentred, as in step 4a
#   S3_fine       S3 at destination x HS4: s_r,dp = X_r,d,p,2010 / L_r (Comex municipal
#                 2010 by SH4 x country), g_dp,t = arc(RoW imports of HS4 p into d, t vs 2010),
#                 Brazil removed as exporter, US-CPI deflated (cr_s3.R conventions)
#   IMP_BR        import competition: S0 shares; g_jt = Δ(Brazil imports from China, ISIC j) / L_j,2010
#   IMP_IV        same with China's exports to all other destinations (ADH/BHJ shock)
#   *_agro        S0 / S3 restricted to agro-dominant microregions (pre-declared below)
# Metrics per design (recentred treatment, residualised on FE + base controls):
#   eff_rot   1/HHI of |Rotemberg weights| at the shock-unit level (years summed)
#   eff_akm   1/HHI of AKM estimand weights  sum_t g~_nt^2 sum_r s_rn^2
#   eff_bhj   1/sum s_n^2 (BHJ exposure weights)
#   eff_micro 1/HHI of |leverage| across microregions; top10 = share of Σ x⊥x in top 10
# =============================================================================
source("audit/ss_core.R"); suppressMessages({ library(data.table); library(Matrix) })
invisible(Sys.setlocale("LC_ALL", "C.UTF-8"))
hhi <- function(a) { a <- abs(a) / sum(abs(a)); 1 / sum(a^2) }
# fast merge of identical share columns (random projections, verified exactly)
merge_fast <- function(W1, G, strata) {
  set.seed(1); k1 <- as.numeric(crossprod(W1, rnorm(nrow(W1)))); k2 <- as.numeric(crossprod(W1, rnorm(nrow(W1))))
  key <- paste(signif(k1, 14), signif(k2, 14), strata); grp <- match(key, unique(key))
  if (!anyDuplicated(grp)) return(list(W1 = W1, G = G, strata = strata, merged = 0))
  first <- !duplicated(grp); G2 <- rowsum(G, grp, reorder = FALSE)
  list(W1 = W1[, first, drop = FALSE], G = G2, strata = strata[first], merged = sum(!first)) }
diag1 <- function(tag, W1, G, strata, ctrl, keep_micro = NULL, labels = NULL) {
  u <- merge_fast(W1, G, strata); W1 <- u$W1; G <- u$G; strata <- u$strata
  rows <- if (is.null(keep_micro)) rep(TRUE, nrow(df)) else df$micro %in% keep_micro
  Gt <- apply(G, 2, function(g) ave(g, strata))           # stratum-year means
  Gt <- G - Gt
  Z <- as.matrix(W1 %*% Gt)                                # micro x year, recentred
  zt <- Z[cbind(match(df$micro, rownames(W1)), yi)]
  zt <- zt[rows]; d <- df[rows, ]; x <- zt / sd(zt)
  X <- model.matrix(~ ., data.frame(ctrl[rows, , drop = FALSE], sy = factor(paste(d$state, d$year))))
  xp <- as.numeric(lm.fit(X, x)$residuals)
  a <- numeric(ncol(W1)); pi <- numeric(ncol(W1)); sn <- numeric(ncol(W1))
  for (k in 1:3) { r <- which(d$year == YRS[k]); Wk <- W1[match(d$micro[r], rownames(W1)), , drop = FALSE]
    a  <- a + Gt[, k] * as.numeric(crossprod(Wk, xp[r]))
    pi <- pi + Gt[, k]^2 * as.numeric(colSums(Wk^2)); sn <- sn + as.numeric(colSums(Wk)) }
  sn <- sn / sum(sn); lev <- tapply(xp * x, d$micro, sum) / sum(xp * x)
  o <- order(-abs(a))[1:5]; nm <- colnames(W1)[o]
  data.table(design = tag, rows = nrow(d), micros = uniqueN(d$micro), units = ncol(W1), merged = u$merged,
    strata = uniqueN(strata), eff_rot = hhi(a), eff_akm = hhi(pi), eff_bhj = 1 / sum(sn^2),
    top3_rot = sum(sort(abs(a), TRUE)[1:3]) / sum(abs(a)), eff_micro = hhi(lev),
    top10_micro = sum(sort(lev, TRUE)[1:10]),
    top5_units = paste(sprintf("%s(%.2f)", if (is.null(labels)) nm else ifelse(is.na(labels[nm]), nm, labels[nm]),
                               a[o] / sum(abs(a))), collapse = "; ")) }
res <- list()
# ---- current designs --------------------------------------------------------------
res$S0 <- diag1("S0", W0_1, G0, sec0, ctrl_base0)
res$S3 <- diag1("S3", W3_1, G3, sec3, ctrl_base3, labels = iso)
cat("baseline done\n"); print(rbindlist(res)[, 1:12])

# ---- BACI aggregates (read once) ---------------------------------------------------
cpi <- as.data.table(readRDS(file.path(D, "cpi_us.rds"))); cc <- fread(file.path(D, "baci", "country_codes_V202601.csv"))
d1 <- readRDS(file.path(PD, "D1_s_rd.rds")); fold <- d1$panel_persistent_fold
foldf <- function(v) { s <- as.character(v); i <- s %in% names(fold); v[i] <- fold[s[i]]; as.integer(v) }
agg_f <- "audit/out/diag_baci_aggregates.rds"
if (!file.exists(agg_f)) {
  A <- lapply(YRS0 <- c(2010, YRS), function(t) {
    b <- fread(file.path(D, "baci", sprintf("BACI_HS07_Y%d_V202601.csv", t)), select = c("i", "j", "k", "v"),
               colClasses = list(character = "k"))
    b[, `:=`(i = foldf(i), j = foldf(j))]; df_ <- cpi$cpi[cpi$year == t] / 100; b[, v := v / df_]
    b[, k := sprintf("%06d", as.integer(k))]
    list(t = t,
         row4  = b[i != 76, .(m = sum(v)), by = .(d = j, p = substr(k, 1, 4))],   # RoW imports, HS4
         chnbr = b[i == 156 & j == 76, .(v = sum(v)), by = k],                      # China -> Brazil, HS6
         chnot = b[i == 156 & j != 76, .(v = sum(v)), by = k]) })                   # China -> others, HS6
  saveRDS(A, agg_f) }
A <- readRDS(agg_f); names(A) <- sapply(A, `[[`, "t")
cat("BACI aggregates ready\n")

# ---- S3_fine: destination x HS4 ---------------------------------------------------------
nrm <- function(s) { s <- chartr("ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç",
                                 "AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc", enc2utf8(s)); toupper(gsub("[^A-Za-z]", "", s)) }
ex <- fread(file.path(D, "EXP_2010_MUN.csv"), colClasses = list(character = c("CO_PAIS", "CO_MUN", "SH4")))
pais <- as.data.table(readxl::read_excel("tab_aux.xlsx", sheet = "10")); umun <- as.data.table(readxl::read_excel("tab_aux.xlsx", sheet = "13"))
mun <- as.data.table(readRDS(file.path(D, "municipios_ibge.rds")))
mun[, key := paste(state, nrm(municipality_name))]; umun[, key := paste(SG_UF, nrm(NO_MUN_MIN))]
umun[key == "SP EMBU", key := "SP EMBUDASARTES"]; umun[, ibge := as.integer(mun$municipality_code_ibge[match(key, mun$key)])]
ex[, ibge := fifelse(as.integer(CO_MUN) %in% as.integer(mun$municipality_code_ibge), as.integer(CO_MUN),
                     umun$ibge[match(as.integer(CO_MUN), as.integer(umun$CO_MUN_GEO))])]
ex[, micro := as.character(mun$microregion_code[match(ibge, as.integer(mun$municipality_code_ibge))])]
ex[, iso3 := pais$CO_PAIS_ISOA3[match(CO_PAIS, pais$CO_PAIS)]]
ex[, baci := cc$country_code[match(iso3, cc$country_iso3)]]
am <- d1$comex_baci_area_map; ex[iso3 %in% names(am), baci := am[iso3]]; ex[, baci := foldf(baci)]
L <- as.data.table(readRDS(file.path(D, "rais_fte.rds")))[, .(L = sum(total_fte)), by = .(micro = as.character(microregion_code))]
X <- ex[micro %in% m14 & paste0("d", baci) %in% colnames(W3_1), .(x = sum(VL_FOB)), by = .(micro, d = baci, p = SH4)]
X[, s := x / L$L[match(micro, L$micro)]]
arc <- function(a, b) fifelse((a + b) > 0, (a - b) / ((a + b) / 2), 0)
U <- unique(X[, .(d, p)])
for (t in c("2010", YC)) { m <- A[[t]]$row4; U[, (paste0("m", t)) := m$m[match(paste(d, p), paste(m$d, m$p))]] }
for (t in YC) U[, (paste0("g", t)) := arc(fcoalesce(get(paste0("m", t)), 0), fcoalesce(m2010, 0))]
U[, id := paste0("d", d, "_", p)]; X[, id := paste0("d", d, "_", p)]
Wf <- sparseMatrix(i = match(X$micro, m14), j = match(X$id, U$id), x = X$s, dims = c(length(m14), nrow(U)), dimnames = list(m14, U$id))
# canary: summing over products reproduces the S3 destination shares
agg <- as.matrix(Wf %*% sparseMatrix(i = seq_len(nrow(U)), j = match(paste0("d", U$d), colnames(W3_1)), x = 1, dims = c(nrow(U), ncol(W3_1))))
cat(sprintf("S3_fine canary: max |sum_p s_rdp - s_rd| = %.3e (max s_rd %.1f)\n", max(abs(agg - W3_1)), max(W3_1)))
Gf <- as.matrix(U[, paste0("g", YC), with = FALSE]); rownames(Gf) <- U$id; colnames(Gf) <- YC
hs_sec <- function(p) { c2 <- as.integer(substr(p, 1, 2))
  cut(c2, c(0, 5, 14, 15, 24, 27, 38, 40, 43, 46, 49, 63, 67, 70, 71, 83, 85, 89, 92, 93, 96, 99), labels = 1:21) }
lab_f <- setNames(paste0(iso[paste0("d", U$d)], "-", U$p), U$id)
res$S3_fine <- diag1("S3_fine (dest x HS4; strata region)", Wf, Gf, sec3[paste0("d", U$d)], ctrl_base3, labels = lab_f)
res$S3_fine2 <- diag1("S3_fine (dest x HS4; strata region x HS section)", Wf, Gf, paste(sec3[paste0("d", U$d)], hs_sec(U$p)), ctrl_base3, labels = lab_f)
cat("S3_fine done\n")

# ---- import competition: S0 shares, China shocks ----------------------------------------
mt <- as.data.table(readRDS(file.path(D, "ncm_isic_match_v7.rds"))); cm <- as.data.table(readRDS(file.path(D, "composite_map_v7.rds")))
br <- fread(file.path(D, "hs2007_hs2012.csv"), colClasses = "character")
mt[, comp := cm$isic_composite[match(isic4, cm$isic4)]]
Lj <- as.data.table(readRDS(file.path(D, "sectoral_shocks_isic_v7.rds")))[year == 2014, .(isic4, L = L_j_2010)]
to_isic <- function(v) {           # v: data.table(k = HS07 6-digit, v); returns value by composite + unmatched share
  b <- merge(v, br, by.x = "k", by.y = "hs6_from", all.x = TRUE)
  b[is.na(hs6_to), `:=`(hs6_to = k, w_bridge = "1")]; b[, v := v * as.numeric(w_bridge)]
  z <- merge(b[, .(k = hs6_to, v)], mt[, .(k = ncm6, comp, w_ncm)], by = "k", allow.cartesian = TRUE, all.x = TRUE)
  un <- z[is.na(comp) | !comp %in% inds, sum(v, na.rm = TRUE)] / b[, sum(v)]
  list(by = z[!is.na(comp) & comp %in% inds, .(v = sum(v * w_ncm)), by = comp], unmatched = un) }
imp <- list()
for (nmv in c("chnbr", "chnot")) {
  base <- to_isic(A[["2010"]][[nmv]]); cat(sprintf("%s 2010 value unmatched to the 152 groups: %.1f%%\n", nmv, 100 * base$unmatched))
  Gi <- sapply(YC, function(t) { cur <- to_isic(A[[t]][[nmv]])$by; v <- setNames(rep(0, length(inds)), inds)
    dv <- cur$v[match(inds, cur$comp)]; dv[is.na(dv)] <- 0; b0 <- base$by$v[match(inds, base$by$comp)]; b0[is.na(b0)] <- 0
    (dv - b0) / 1e4 / Lj$L[match(inds, Lj$isic4)] }); rownames(Gi) <- inds; Gi[!is.finite(Gi)] <- 0
  imp[[nmv]] <- Gi }
lab0 <- c(`0610`="crude oil", `0710`="iron ore", `0111`="soy/cereals", `1010`="meat", `1920`="refined petroleum",
          `2610`="electronic components", `2630`="communication equip.", `2620`="computers", `2640`="consumer electronics",
          `2710`="electric motors", `1410`="apparel", `1311`="textile fibres", `2011`="basic chemicals", `2910`="motor vehicles",
          `2930`="vehicle parts", `2821`="agri machinery", `2410`="iron & steel", `3091`="motorcycles", `2750`="domestic appliances")
res$IMP_BR <- diag1("IMP_BR (China->Brazil per worker)", W0_1, imp$chnbr, sec0, ctrl_base0, labels = lab0)
res$IMP_IV <- diag1("IMP_IV (China->other countries per worker)", W0_1, imp$chnot, sec0, ctrl_base0, labels = lab0)
# entanglement: correlation of the recentred, residualised import and S0 exposures
xr <- function(W1, G, st, ctrl) { u <- merge_units(W1, G, st); de <- build_design(u$W1, u$G, u$strata); as.numeric(proj_maker(ctrl)(matrix(de$zt))) }
cors <- c(IMP_BR = cor(xr(W0_1, imp$chnbr, sec0, ctrl_base0), xr(W0_1, G0, sec0, ctrl_base0)),
          IMP_IV = cor(xr(W0_1, imp$chnot, sec0, ctrl_base0), xr(W0_1, G0, sec0, ctrl_base0)))
cat("corr(residualised recentred import exposure, S0):", sprintf("%s %.3f", names(cors), cors), "\n")

# ---- agro-dominant microregions (pre-declared: >= 50% of tradable employment) -----------
secA <- names(sec0)[sec0 == "A"]; food <- inds[substr(inds, 1, 2) %in% c("10", "11", "12")]
st <- as.data.table(sh)[, .(A = sum(s_rj_trad[isic4 %in% secA]), Afood = sum(s_rj_trad[isic4 %in% c(secA, food)])), by = micro]
agro1 <- st[A >= 0.5, micro]; agro2 <- st[Afood >= 0.5, micro]
cat(sprintf("agro-dominant micros: section A >= 50%%: %d; A + food/bev/tobacco mfg >= 50%%: %d\n", length(agro1), length(agro2)))
res$S0_agroA <- diag1("S0 | agro (A >= 50%)", W0_1, G0, sec0, ctrl_base0, keep_micro = agro1)
res$S3_agroA <- diag1("S3 | agro (A >= 50%)", W3_1, G3, sec3, ctrl_base3, keep_micro = agro1, labels = iso)
res$S0_agroF <- diag1("S0 | agro (A + food mfg >= 50%)", W0_1, G0, sec0, ctrl_base0, keep_micro = agro2)
res$S3_agroF <- diag1("S3 | agro (A + food mfg >= 50%)", W3_1, G3, sec3, ctrl_base3, keep_micro = agro2, labels = iso)
tab <- rbindlist(res); fwrite(tab, "audit/out/diag_designs.csv")
fwrite(data.table(design = names(cors), corr_with_S0 = cors), "audit/out/diag_designs_import_corr.csv")
options(width = 250); print(tab[, .(design, micros, units, merged, strata, eff_rot = round(eff_rot, 1), eff_akm = round(eff_akm, 1),
  eff_bhj = round(eff_bhj, 1), top3_rot = round(top3_rot, 2), eff_micro = round(eff_micro, 1), top10_micro = round(top10_micro, 2))])
print(tab[, .(design, top5_units)])
