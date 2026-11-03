# Reproduce the PDF's Table 4 (old spec: presidential ΔDalton / ΔCentre, raw ΔEPW, mesoregion×year clusters)
suppressMessages({library(data.table); library(fixest)})
df <- as.data.table(readRDS("D/df_estimation_v7.rds")); z <- function(v) (v - mean(v)) / sd(v)
sdE <- sd(df$delta_EPW)
df[, `:=`(yD = z(delta_P_dalton), yN = z(delta_P_center), x = z(delta_EPW),
          xp = pmax(delta_EPW, 0) / sdE, xm = pmax(-delta_EPW, 0) / sdE,
          gdp = z(ln_gdp_pc), pop = z(ln_pop), th = z(tradable_emp_share), urb = z(urban_share), edu = z(educ_share), man = z(manuf_share_of_tradable),
          cl = paste(mesoregion_code, year))]
base <- "gdp + pop + th"; ext <- "gdp + pop + th + urb + edu + man"
res <- list()
for (o in c("yD", "yN")) for (cc in c("base", "ext")) { ctl <- if (cc == "base") base else ext
  a <- feols(as.formula(sprintf("%s ~ x + %s | state^year", o, ctl)), df, cluster = ~cl)
  b <- feols(as.formula(sprintf("%s ~ xp + xm + %s | state^year", o, ctl)), df, cluster = ~cl)
  w <- wald(b, "xp|xm", print = FALSE)  # joint, not the symmetry test
  sym <- {V <- vcov(b)[c("xp","xm"), c("xp","xm")]; d <- sum(coef(b)[c("xp","xm")]); 2 * pnorm(-abs(d / sqrt(sum(V))))}
  am <- feols(as.formula(sprintf("%s ~ x + %s | state^year", o, ctl)), df, cluster = ~mesoregion_code)
  res[[length(res) + 1]] <- data.table(outcome = o, controls = cc, n = nobs(a), b_pooled = coef(a)[["x"]], se_mesoyr = se(a)[["x"]], se_meso = se(am)[["x"]],
    b_boom = coef(b)[["xp"]], se_boom = se(b)[["xp"]], b_bust = coef(b)[["xm"]], se_bust = se(b)[["xm"]], p_sym_normal = sym,
    b_edu = if (cc == "ext") coef(b)[["edu"]] else NA, r2w_B = fitstat(b, "war2")[[1]])
}
r <- rbindlist(res); print(r[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 3) else v)]); fwrite(r, "step5/out/s5_table4_repro.csv")
