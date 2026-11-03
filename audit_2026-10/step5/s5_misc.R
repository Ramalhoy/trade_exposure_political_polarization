# =============================================================================
# s5_misc.R — Step 5: Table 3 moments, the BHJ shock-balance test as specified in
# revision/G3_arc_shock.R §5 (commodity = ISIC division <= 09, log1p(2010 exports),
# weights L_j / sum L_j, F test by year), Table C1 under both share conventions, and the
# presidential-Dalton quintiles by macro-region behind the Figure 3 text.
# =============================================================================
invisible(Sys.setlocale("LC_ALL", "C.UTF-8")); suppressMessages({ library(data.table); library(fixest) })
df <- as.data.table(readRDS("D/df_estimation_v7.rds"))
v <- c("delta_P_dalton", "delta_P_center", "delta_EPW", "tradable_emp_share", "manuf_share_of_tradable", "ln_gdp_pc", "ln_pop", "urban_share", "educ_share")
t3 <- rbindlist(lapply(v, function(k) { x <- df[[k]]; data.table(var = k, N = sum(!is.na(x)), mean = mean(x), sd = sd(x), min = min(x),
  p25 = quantile(x, .25), med = median(x), p75 = quantile(x, .75), max = max(x)) }))
fwrite(t3, "step5/out/s5_table3.csv")
s <- as.data.table(readRDS("D/sectoral_shocks_isic_v7.rds"))
s[, `:=`(commodity = as.integer(as.integer(substr(isic4, 1, 2)) <= 9), lexp = log1p(exp_2010))]
s <- merge(s, s[year == 2014, .(isic4, sbar = L_j_2010 / sum(L_j_2010))], by = "isic4")
bal <- rbindlist(lapply(c(2014, 2018, 2022), function(t) { m <- feols(g_jt ~ commodity + lexp, s[year == t], weights = ~sbar)
  f <- fitstat(m, "f")$f; data.table(year = t, F = f$stat, df1 = f$df1, df2 = f$df2, p = f$p) }))
fwrite(bal, "step5/out/s5_balance_repro.csv")
a3 <- df[, .(epw_mean = mean(delta_EPW), n = uniqueN(microregion_code)), by = state][order(-epw_mean)][, rank := .I]
fwrite(a3, "step5/out/s5_tableA3_total.csv")
sh <- as.data.table(readRDS("D/exposure_shares_isic_v7.rds"))
x <- merge(sh, s[year > 2010, .(isic4, year, g_jt)], by = "isic4", allow.cartesian = TRUE)
tr <- x[, .(z_trad = sum(s_rj_trad * g_jt), z_tot = sum(s_rj * g_jt)), by = .(micro, year, state)]
fwrite(tr[, .(within_tradable = mean(z_trad), total = mean(z_tot), n = uniqueN(micro)), by = state][order(-within_tradable)], "step5/out/s5_tableA3_both_conventions.csv")
d <- as.data.table(readRDS("D/dalton_panel_presidencial.rds")); d[, uf := as.integer(substr(microregion_code, 1, 2))]
d[, reg := fcase(uf < 20, "North", uf < 30, "Northeast", uf < 40, "Southeast", uf < 50, "South", default = "CentreWest")]
d[, q := cut(frank(P_dalton) / .N, c(0, .2, .4, .6, .8, 1), labels = 1:5), by = year]
m1 <- dcast(d[, .(v = round(mean(q == 5), 2)), by = .(year, reg)], reg ~ year, value.var = "v")
m2 <- dcast(d[, .(v = round(mean(as.integer(q)), 2)), by = .(year, reg)], reg ~ year, value.var = "v")
fwrite(merge(m1, m2, by = "reg", suffixes = c("_shareQ5", "_meanQ")), "step5/out/s5_map_quintiles.csv")
print(bal); print(a3[1:6]); print(merge(m1, m2, by = "reg", suffixes = c("_shareQ5", "_meanQ")))
