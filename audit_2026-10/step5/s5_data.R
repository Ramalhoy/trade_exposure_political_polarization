# =============================================================================
# s5_data.R — Step 5 checks of the sample, industry-universe, crosswalk and descriptive
# numbers in the dissertation text. Inputs: stored raw-extraction objects in D/
# (df_estimation_v7, exposure_shares_isic_v7, sectoral_shocks_isic_v7, composite_map_v7,
# ncm_isic_match_v7, exports_national_ncm, cpi_us, rais_2010_micro, municipios_ibge,
# bls9_estimates_partiespresidents_long), the IBGE/CONCLA tables CNAE20_ISIC4.xls and
# NCM2011XCNAE20XPRODLIST2010XCGCE.xlsx (as found in the author's folder).
# Output: step5/out/s5_data.csv (item, value, source).
# =============================================================================
invisible(Sys.setlocale("LC_ALL", "C.UTF-8")); suppressMessages(library(data.table))
out <- list(); add <- function(item, value, source) out[[length(out) + 1]] <<- data.table(item, value = as.character(value), source)
df <- as.data.table(readRDS("D/df_estimation_v7.rds"))
mun <- as.data.table(readRDS("D/municipios_ibge.rds")); mm <- unique(mun[!is.na(microregion_code), .(microregion_code, microregion_name, state)])
add("IBGE microregions (municipios_ibge.rds)", nrow(mm), "municipios_ibge.rds")
add("Estimation rows / microregions", paste(nrow(df), uniqueN(df$microregion_code)), "df_estimation_v7.rds")
miss <- mm[!as.integer(microregion_code) %in% as.integer(df$microregion_code)]
add("Microregion absent from estimation sample", paste(miss$microregion_code, miss$microregion_name, miss$state), "municipios_ibge vs df_estimation_v7")
code <- as.integer(miss$microregion_code)
add("Absent micro: tradable_emp_share", as.data.table(readRDS("D/tradable_emp_share_2010_v7.rds"))[as.integer(micro) == code, tradable_emp_share], "tradable_emp_share_2010_v7.rds")
add("Absent micro: rows in exposure shares / in EPW panel", paste(as.data.table(readRDS("D/exposure_shares_isic_v7.rds"))[as.integer(micro) == code, .N],
    as.data.table(readRDS("D/epw_panel_isic_v7.rds"))[as.integer(micro) == code, .N]), "exposure_shares_isic_v7 / epw_panel_isic_v7")
r <- as.data.table(readRDS("D/rais_2010_micro.rds"))[as.integer(microregion_code) == code]
add("Absent micro: RAIS 2010 contracts total, and by CNAE", paste(sum(r$total_vinculos), paste(r$cnae_2, r$total_vinculos, collapse = "; ")), "rais_2010_micro.rds")
add("Microregions named 'Medio Amazonas' in IBGE file", mm[grepl("dio Amazonas", microregion_name), .N], "municipios_ibge.rds")
add("States with a single microregion (FE singletons)", paste(df[, .N, by = state][N == 3, state]), "df_estimation_v7.rds")
# ---- industry universe -------------------------------------------------------------------
sh <- as.data.table(readRDS("D/exposure_shares_isic_v7.rds")); cm <- as.data.table(readRDS("D/composite_map_v7.rds"))
inds <- unique(sh$isic4); sec <- function(c) { d <- as.integer(substr(c, 1, 2)); ifelse(d <= 3, "A", ifelse(d <= 9, "B", ifelse(d <= 33, "C", "other"))) }
add("Industry units in share matrix (composite groups)", length(inds), "exposure_shares_isic_v7.rds")
add("Units by ISIC section A/B/C", paste(table(sec(inds)), collapse = "/"), "exposure_shares_isic_v7.rds")
add("ISIC classes in composite map / composite groups", paste(nrow(cm), uniqueN(cm$isic_composite)), "composite_map_v7.rds")
add("Composite group in map without shares", paste(setdiff(unique(cm$isic_composite), inds), collapse = ","), "composite_map_v7 vs shares")
k <- cm[isic_composite %in% inds]
add("ISIC classes inside the 152 retained groups (A/B/C, total)", paste(paste(table(sec(k$isic4)), collapse = "/"), nrow(k)), "composite_map_v7.rds")
cl <- suppressWarnings(as.data.table(readxl::read_excel("step5/cnae20_isic4.xls", col_names = FALSE, col_types = "text")))
ic <- unique(gsub("\\D", "", na.omit(cl[[which.max(sapply(cl, function(v) sum(nchar(gsub("\\D", "", na.omit(v))) == 4)))]]))); ic <- ic[nchar(ic) == 4]
add("Distinct 4-digit ISIC codes in CONCLA table (A/B/C/other)", paste(length(ic), paste(table(sec(ic))[c("A", "B", "C", "other")], collapse = "/")), "CNAE20_ISIC4.xls col 4")
# ---- crosswalk ---------------------------------------------------------------------------
m <- as.data.table(readRDS("D/ncm_isic_match_v7.rds"))
add("ncm_isic_match: NCM-6 260111 mapping", paste(m[ncm6 == "260111", paste(isic4, w_ncm)], collapse = "; "), "ncm_isic_match_v7.rds")
add("ncm_isic_match: chapter 98/99 rows", m[substr(ncm6, 1, 2) %in% c("98", "99"), .N], "ncm_isic_match_v7.rds")
e <- as.data.table(readRDS("D/exports_national_ncm.rds")); e[, ncm := sprintf("%08d", as.integer(id_ncm))][, n6 := substr(ncm, 1, 6)]
x <- suppressWarnings(as.data.table(readxl::read_excel("step5/ncm2011_cnae.xlsx", col_types = "text"))); x <- unique(gsub("\\D", "", x[[1]])); x <- x[nchar(x) == 8]
for (yrs in list(c(2010, 2014, 2018, 2022), 2010:2022)) { ee <- e[ano %in% yrs]; u <- unique(ee$ncm); ms <- setdiff(u, x)
  add(sprintf("NCM-8 codes exported %d-%d (%d yrs): total / absent from CONCLA NCM2011xCNAE / value share absent (pct)", min(yrs), max(yrs), length(yrs)),
      paste(length(u), length(ms), round(100 * ee[ncm %in% ms, sum(valor_fob_dolar)] / sum(ee$valor_fob_dolar), 2)), "exports_national_ncm + NCM2011XCNAE20XPRODLIST2010XCGCE.xlsx") }
cpi <- as.data.table(readRDS("D/cpi_us.rds"))
s <- e[, .(tot = sum(valor_fob_dolar), c9899 = sum(valor_fob_dolar[substr(ncm, 1, 2) %in% c("98", "99")]),
           unm = sum(valor_fob_dolar[!n6 %in% m$ncm6 & !substr(ncm, 1, 2) %in% c("98", "99")])), by = ano][order(ano)]
s <- merge(s, cpi, by.x = "ano", by.y = "year"); s[, real := tot / (cpi / 100)]
fwrite(s[, .(ano, nominal_bn = round(tot / 1e9, 1), real_bn = round(real / 1e9, 1), pct_9899 = round(100 * c9899 / tot, 2),
             pct_unmatched_ex9899 = round(100 * unm / (tot - c9899), 3))], "step5/out/s5_exports_series.csv")
add("Real exports, USD bn 2010 prices (US CPI), 2010..2022", paste(round(s$real / 1e9, 1), collapse = " "), "exports_national_ncm + cpi_us")
add("Real exports: max year / trough year after 2011", paste(s[which.max(real), ano], s[ano > 2011][which.min(real), ano]), "same")
add("Unmatched value after crosswalk, pct of non-98/99 exports, min-max over years", paste(round(range(100 * s$unm / (s$tot - s$c9899)), 2), collapse = "-"), "exports_national_ncm vs ncm_isic_match_v7")
gk <- as.data.table(readRDS("D/sectoral_shocks_isic_v7.rds"))
k2 <- merge(gk[, .(isic = sum(exp_national) * 1e4), by = year], s[, .(year = ano, real, tot)], by = "year")
add("Shock-table exports x 1e4 / real total exports, 2010/14/18/22", paste(round(k2$isic / k2$real, 3), collapse = " "), "sectoral_shocks_isic_v7 vs exports_national_ncm/cpi")
# ---- descriptive -------------------------------------------------------------------------
add("Share of rows with dDalton>0 / dCentre>0 (president)", paste(round(mean(df$delta_P_dalton > 0), 3), round(mean(df$delta_P_center > 0), 3)), "df_estimation_v7.rds")
add("sd/mean of dEPW", round(sd(df$delta_EPW) / mean(df$delta_EPW), 2), "df_estimation_v7.rds")
add("Range ln_pop / ln_gdp_pc", paste(round(diff(range(df$ln_pop)), 2), round(diff(range(df$ln_gdp_pc)), 2)), "df_estimation_v7.rds")
add("Mean manuf_share_of_tradable / P75 ln_pop (5 dp)", sprintf("%.5f / %.5f", mean(df$manuf_share_of_tradable), quantile(df$ln_pop, .75)), "df_estimation_v7.rds")
b <- as.data.table(readRDS("D/bls9_estimates_partiespresidents_long.rds"))
add("BLS mean score by wave 1990..2021", paste(b[, round(mean(ideo), 3), by = year]$V1, collapse = " "), "bls9_estimates_partiespresidents_long.rds")
add("BLS entries with score > 0.6 by wave 1990..2021", paste(b[, sum(ideo > 0.6), by = year]$V1, collapse = " "), "same")
fwrite(rbindlist(out), "step5/out/s5_data.csv"); print(rbindlist(out)[, .(item, value)], nrows = 100)
