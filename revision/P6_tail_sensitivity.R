# =============================================================================
# P6 — treatment-tail sensitivity and the missing reduced-form figure.
# Referee item R1-M7.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("P6")
B_RI <- 9999

wins <- function(x, p) {
  q <- quantile(x, c(p, 1 - p))
  pmin(pmax(x, q[1]), q[2])
}

d <- df_scaled |>
  mutate(raw          = delta_EPW_raw,
         raw_w1       = wins(delta_EPW_raw, 0.01),
         raw_w5       = wins(delta_EPW_raw, 0.05),
         raw_rank     = (rank(delta_EPW_raw) - 0.5) / length(delta_EPW_raw))

treat_defs <- c("raw", "raw_w1", "raw_w5", "raw_rank")
for (v in treat_defs) {
  d[[paste0("z_", v)]]    <- as.numeric(scale(d[[v]]))
  s <- sd(d[[v]])
  cen <- if (v == "raw_rank") d[[v]] - 0.5 else d[[v]]     # rank: centre at median
  d[[paste0("boom_", v)]] <- pmax( cen, 0) / s
  d[[paste0("bust_", v)]] <- pmax(-cen, 0) / s
}

cat("\n=== P6(1)(2) treatment definitions ===\n")
print(as.data.frame(map_dfr(treat_defs, function(v) tibble(
  treat = v, mean = mean(d[[v]]), sd = sd(d[[v]]), min = min(d[[v]]),
  p25 = quantile(d[[v]], .25), median = median(d[[v]]), p75 = quantile(d[[v]], .75),
  max = max(d[[v]]), cor_with_raw = cor(d[[v]], d$raw),
  spearman_with_raw = cor(d[[v]], d$raw, method = "spearman")))), digits = 4)

est <- map_dfr(treat_defs, function(v) map_dfr(outcomes, function(oc)
  map_dfr(c("base","ext"), function(ck) {
    ctrls <- if (ck=="base") ctrl_base else ctrl_ext; cz <- paste(ctrls, collapse=" + ")
    mp <- feols(as.formula(paste(oc, "~ z_", v, " + ", cz, "| state^year", sep="")),
                data = d, cluster = ~ mesoregion_code^year)
    md <- feols(as.formula(paste(oc, " ~ boom_", v, " + bust_", v, " + ", cz,
                                 "| state^year", sep="")),
                data = d, cluster = ~ mesoregion_code^year)
    bn <- paste0("boom_", v); bs <- paste0("bust_", v)
    bind_rows(
      tibble(treat=v, outcome=oc, ctrls=ck, term="pooled", beta=coef(mp)[[paste0("z_",v)]],
             se=se(mp)[[paste0("z_",v)]], n=nobs(mp)),
      tibble(treat=v, outcome=oc, ctrls=ck, term="boom", beta=coef(md)[[bn]],
             se=se(md)[[bn]], n=nobs(md)),
      tibble(treat=v, outcome=oc, ctrls=ck, term="bust", beta=coef(md)[[bs]],
             se=se(md)[[bs]], n=nobs(md)))
  })))
cat("\n=== P6 estimates under winsorised and rank treatments ===\n")
print(as.data.frame(est), digits = 4)

# ---- (3) leverage and DFBETAS for the top-10 |delta_EPW| microregions -------
mlev <- lm(as.formula(paste("delta_P_dalton ~ delta_EPW +",
                            paste(ctrl_base, collapse = " + "),
                            "+ factor(state):factor(year)")), data = df_scaled)
h  <- hatvalues(mlev)
db <- dfbeta(mlev)[, "delta_EPW"]
dbs <- dfbetas(mlev)[, "delta_EPW"]
lev <- df_scaled |>
  mutate(hat = h, dfbeta = db, dfbetas = dbs, absEPW = abs(delta_EPW_raw)) |>
  select(micro, year, state, delta_EPW_raw, absEPW, hat, dfbeta, dfbetas)
names_micro <- df_raw |> distinct(micro, microregion_name = microregion_code) |>
  mutate(micro = as.character(micro))
# microregion names live in the vote panel
vn <- readRDS(paths$votos_pres) |>
  distinct(micro = as.character(microregion_code), microregion_name)
lev <- lev |> left_join(vn, by = "micro")

cat("\n=== P6(3) top 10 microregion-years by |delta_EPW| ===\n")
print(as.data.frame(lev |> arrange(desc(absEPW)) |> head(10)), digits = 4)
cat("\n=== P6(3b) top 10 by |DFBETAS| on the treatment ===\n")
print(as.data.frame(lev |> arrange(desc(abs(dfbetas))) |> head(10)), digits = 4)
cat(sprintf("\nDFBETAS threshold 2/sqrt(n) = %.4f; %d observations exceed it.\n",
            2/sqrt(nrow(lev)), sum(abs(lev$dfbetas) > 2/sqrt(nrow(lev)))))

# drop-the-top-10 refit
top10 <- lev |> arrange(desc(absEPW)) |> head(10) |> transmute(micro, year)
d_no10 <- df_scaled |> anti_join(top10, by = c("micro","year"))
drop_est <- map_dfr(outcomes, function(oc) map_dfr(c("base","ext"), function(ck) {
  ctrls <- if (ck=="base") ctrl_base else ctrl_ext
  m <- feols(as.formula(paste(oc, "~ delta_EPW +", paste(ctrls, collapse=" + "),
                              "| state^year")), data = d_no10,
             cluster = ~ mesoregion_code^year)
  tibble(outcome=oc, ctrls=ck, spec="drop top-10 |dEPW|",
         beta=coef(m)[["delta_EPW"]], se=se(m)[["delta_EPW"]], n=nobs(m))
}))
cat("\n=== P6(3c) dropping the ten most extreme microregion-years ===\n")
print(as.data.frame(drop_est), digits = 4)

# ---- (4) the missing figure: residualised binned scatter --------------------
resid_on <- function(v, ctrls) {
  f <- as.formula(paste(v, "~", paste(ctrls, collapse = " + "), "| state^year"))
  resid(feols(f, data = df_scaled))
}
for (ck in c("base", "ext")) {
  ctrls <- if (ck=="base") ctrl_base else ctrl_ext
  bs <- tibble(x = resid_on("delta_EPW", ctrls),
               yD = resid_on("delta_P_dalton", ctrls),
               yN = resid_on("delta_P_center", ctrls)) |>
    mutate(bin = ntile(x, 20)) |>
    group_by(bin) |>
    summarise(x = mean(x), yD = mean(yD), yN = mean(yN), n = n(), .groups = "drop")
  slope <- coef(feols(as.formula(paste("delta_P_dalton ~ delta_EPW +",
                                       paste(ctrls, collapse=" + "), "| state^year")),
                      data = df_scaled))[["delta_EPW"]]
  p <- ggplot(bs, aes(x, yD)) + geom_point() +
    geom_abline(intercept = 0, slope = slope, linetype = 2) +
    labs(x = expression("Residualised "*Delta*"EPW (20-bin means)"),
         y = expression("Residualised "*Delta*P^D),
         subtitle = sprintf("Controls: %s; residualised on state x year FE. Dashed line = OLS slope (%.4f).",
                            ck, slope)) + theme_minimal()
  ggsave(file.path(OUT, sprintf("P6_binscatter_dalton_%s.pdf", ck)), p,
         width = 6.5, height = 4.5, device = grDevices::pdf)
  pN <- ggplot(bs, aes(x, yN)) + geom_point() +
    labs(x = expression("Residualised "*Delta*"EPW (20-bin means)"),
         y = expression("Residualised "*Delta*P^N)) + theme_minimal()
  ggsave(file.path(OUT, sprintf("P6_binscatter_center_%s.pdf", ck)), pN,
         width = 6.5, height = 4.5, device = grDevices::pdf)
  write_csv(bs, file.path(OUT, sprintf("P6_binscatter_data_%s.csv", ck)))
}

write_csv(est,      file.path(OUT, "P6_tail_estimates.csv"))
write_csv(lev,      file.path(OUT, "P6_leverage.csv"))
write_csv(drop_est, file.path(OUT, "P6_drop_top10.csv"))
cat("\n[P6] wrote", OUT, "\n")
