# =============================================================================
# G3 — does the null survive more independent shifts? Arc-percentage shock.
# Referee item R3-M4.
#
# The level shock is  g_jt = (EXP_jt - EXP_j,2010) / L_j,2010  (per-worker).
# The arc-percentage (Davis-Haltiwanger) shock is
#       g^arc_jt = (EXP_jt - EXP_j,2010) / (0.5 * (EXP_jt + EXP_j,2010)),
# bounded in [-2, 2], defined at zeros on either side (entry = +2, total
# collapse = -2), and 0/0 := 0 for industries with no exports in either year.
# It removes L_j,2010 from the denominator, which is what mechanically inflates
# capital-intensive extraction shocks and concentrates the Rotemberg weights.
#
# NOTE (searched first, per the task file): no arc-% implementation exists in
# the repo. SPEC_import_and_governor.md sec. A.4 PROPOSES it ("a Davis-Haltiwanger
# arc change robust to zeros") but 03d, which was to run it, has never been
# executed (07's joint block reports "SKIPPED (missing 03a/03d outputs)"). The
# draft's Section 5.2 claim of "five to nine" effective shifts therefore has no
# committed code behind it in this repository. Built here from scratch.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("G3")
B_RI <- 9999

# ---- (1) build the arc-% shock ----------------------------------------------
shocks_arc <- shocks |>
  mutate(denom = 0.5 * (exp_national + exp_2010),
         g_arc = if_else(denom > 0, delta_exp / denom, 0))
stopifnot(!anyNA(shocks_arc$g_arc), all(abs(shocks_arc$g_arc) <= 2 + 1e-9))

cat("\n=== G3(1) arc-% shock distribution by year ===\n")
print(as.data.frame(
  shocks_arc |> filter(year != 2010) |> group_by(year) |>
    summarise(n = n(), min = min(g_arc), p25 = quantile(g_arc, .25),
              median = median(g_arc), mean = mean(g_arc),
              p75 = quantile(g_arc, .75), max = max(g_arc),
              sd = sd(g_arc), pct_neg = 100 * mean(g_arc < 0),
              at_minus2 = sum(abs(g_arc + 2) < 1e-9),
              at_plus2  = sum(abs(g_arc - 2) < 1e-9), .groups = "drop")), digits = 4)

g_wide_arc <- shocks_arc |> filter(year %in% c(2014, 2018, 2022)) |>
  select(isic4, year, g_arc) |>
  pivot_wider(names_from = year, values_from = g_arc, values_fill = 0)
g_mat_arc <- g_wide_arc |> column_to_rownames("isic4") |> as.matrix()
g_mat_arc <- g_mat_arc[colnames(W), , drop = FALSE]

epw_arc_raw <- make_epw_star(seq_len(nrow(g_mat_arc)), gm = g_mat_arc)
stopifnot(length(epw_arc_raw) == nrow(df_scaled))

# ---- (4) correlation between the two treatment series -----------------------
corr <- tibble(
  scope = c("pooled", "2014", "2018", "2022"),
  pearson = c(cor(df_scaled$delta_EPW_raw, epw_arc_raw),
              map_dbl(c(2014, 2018, 2022), ~ cor(df_scaled$delta_EPW_raw[df_scaled$year == .x],
                                                 epw_arc_raw[df_scaled$year == .x]))),
  spearman = c(cor(df_scaled$delta_EPW_raw, epw_arc_raw, method = "spearman"),
               map_dbl(c(2014, 2018, 2022), ~ cor(df_scaled$delta_EPW_raw[df_scaled$year == .x],
                                                  epw_arc_raw[df_scaled$year == .x],
                                                  method = "spearman"))))
cat("\n=== G3(4) correlation: level vs arc-% treatment ===\n")
print(as.data.frame(corr), digits = 4)

cat("\n=== G3(4b) arc treatment descriptives (raw) ===\n")
print(as.data.frame(tibble(
  series = c("delta_EPW (level)", "delta_EPW (arc-%)"),
  mean = c(mean(df_scaled$delta_EPW_raw), mean(epw_arc_raw)),
  sd   = c(sd(df_scaled$delta_EPW_raw),   sd(epw_arc_raw)),
  min  = c(min(df_scaled$delta_EPW_raw),  min(epw_arc_raw)),
  p25  = c(quantile(df_scaled$delta_EPW_raw, .25), quantile(epw_arc_raw, .25)),
  med  = c(median(df_scaled$delta_EPW_raw), median(epw_arc_raw)),
  p75  = c(quantile(df_scaled$delta_EPW_raw, .75), quantile(epw_arc_raw, .75)),
  max  = c(max(df_scaled$delta_EPW_raw),  max(epw_arc_raw)))), digits = 4)

# ---- (2) Rotemberg weights and effective shifts, both constructions ---------
rotemberg_for <- function(treat_vec, gm, ctrls) {
  d_all <- df_scaled |> mutate(.treat = treat_vec)
  map_dfr(c("2014", "2018", "2022"), function(t) {
    sel <- df_scaled$year == as.integer(t)
    d   <- d_all[sel, ]
    Wt  <- W[sel, , drop = FALSE]
    x_perp <- resid(lm(reformulate(c(ctrls, "factor(state)"), response = ".treat"), data = d))
    num <- gm[colnames(Wt), t] * as.numeric(t(Wt) %*% x_perp)
    tibble(isic4 = colnames(Wt), year = t, alpha = num / sum(num))
  })
}
conc <- function(rot) {
  by_year <- rot |> group_by(year) |>
    summarise(hhi = sum((abs(alpha) / sum(abs(alpha)))^2),
              eff_n = 1 / hhi,
              top3 = sum(sort(abs(alpha), decreasing = TRUE)[1:3]) / sum(abs(alpha)),
              top1 = max(abs(alpha)) / sum(abs(alpha)), .groups = "drop")
  # pooled over all (industry x year) cells
  pooled <- rot |> summarise(year = "pooled(all j,t cells)",
                             hhi = sum((abs(alpha) / sum(abs(alpha)))^2),
                             eff_n = 1 / hhi,
                             top3 = sum(sort(abs(alpha), decreasing = TRUE)[1:3]) / sum(abs(alpha)),
                             top1 = max(abs(alpha)) / sum(abs(alpha)))
  bind_rows(by_year, pooled,
            tibble(year = "mean of yearly", hhi = NA, eff_n = mean(by_year$eff_n),
                   top3 = mean(by_year$top3), top1 = mean(by_year$top1)))
}

rot_tbl <- list(); conc_tbl <- list(); top5 <- list()
for (ck in c("base", "ext")) {
  ctrls <- if (ck == "base") ctrl_base else ctrl_ext
  for (sh in c("level", "arc")) {
    tv <- if (sh == "level") df_scaled$delta_EPW_raw else epw_arc_raw
    gm <- if (sh == "level") g_mat else g_mat_arc
    r  <- rotemberg_for(tv, gm, ctrls)
    rot_tbl[[paste(sh, ck)]]  <- r |> mutate(shock = sh, ctrls = ck)
    conc_tbl[[paste(sh, ck)]] <- conc(r) |> mutate(shock = sh, ctrls = ck, .before = 1)
    top5[[paste(sh, ck)]] <- r |> group_by(year) |> slice_max(abs(alpha), n = 5) |>
      arrange(year, desc(abs(alpha))) |> ungroup() |> mutate(shock = sh, ctrls = ck)
  }
}
conc_all <- bind_rows(conc_tbl)
top5_all <- bind_rows(top5)
cat("\n=== G3(2) Rotemberg concentration and effective number of shifts ===\n")
print(as.data.frame(conc_all |> select(shock, ctrls, year, hhi, eff_n, top1, top3)), digits = 4)
cat("\n=== G3(2b) top-5 |alpha| by year ===\n")
print(as.data.frame(top5_all |> select(shock, ctrls, year, isic4, alpha)), digits = 4)

# ---- (3) full Table 3 under the arc-% treatment ------------------------------
sd_arc <- sd(epw_arc_raw)
df_arc <- df_scaled |>
  mutate(epw_arc_raw = epw_arc_raw,
         delta_EPW_arc = as.numeric(scale(epw_arc_raw)),
         arc_boom = pmax( epw_arc_raw, 0) / sd_arc,
         arc_bust = pmax(-epw_arc_raw, 0) / sd_arc)

est_tbl <- function(data, treat, boom, bust) {
  map_dfr(c("base", "ext"), function(ck) {
    ctrls <- if (ck == "base") ctrl_base else ctrl_ext
    cz <- paste(ctrls, collapse = " + ")
    map_dfr(outcomes, function(oc) {
      mp <- feols(as.formula(paste(oc, "~", treat, "+", cz, "| state^year")),
                  data = data, cluster = ~ mesoregion_code^year)
      md <- feols(as.formula(paste(oc, "~", boom, "+", bust, "+", cz, "| state^year")),
                  data = data, cluster = ~ mesoregion_code^year)
      b <- coef(md)[c(boom, bust)]
      V <- vcov(md)[c(boom, bust), c(boom, bust)]
      cc <- sum(b); s <- sqrt(sum(V))
      dof <- fixest::degrees_freedom(md, type = "t")
      bind_rows(
        tibble(outcome = oc, ctrls = ck, term = "pooled", beta = coef(mp)[[treat]],
               se = se(mp)[[treat]], n = nobs(mp)),
        tibble(outcome = oc, ctrls = ck, term = "boom", beta = b[[boom]],
               se = se(md)[[boom]], n = nobs(md)),
        tibble(outcome = oc, ctrls = ck, term = "bust", beta = b[[bust]],
               se = se(md)[[bust]], n = nobs(md)),
        tibble(outcome = oc, ctrls = ck, term = "symmetry", beta = cc, se = s,
               n = nobs(md), p_sym = 2 * pt(-abs(cc / s), df = dof)))
    })
  })
}
res_arc <- est_tbl(df_arc, "delta_EPW_arc", "arc_boom", "arc_bust") |> mutate(shock = "arc")

# ---- RI under the arc treatment ---------------------------------------------
ri_arc <- function(ctrls) {
  set.seed(2026)
  cz <- paste(ctrls, collapse = " + ")
  t(replicate(B_RI, {
    perm    <- sample(nrow(g_mat_arc))
    raw     <- make_epw_star(perm, gm = g_mat_arc)
    d <- df_scaled |> mutate(epw_star  = raw / sd_arc,
                             boom_star = pmax( raw, 0) / sd_arc,
                             bust_star = pmax(-raw, 0) / sd_arc)
    f <- function(dv, rhs) coef(feols(as.formula(paste0(dv, " ~ ", rhs, " + ", cz,
                                                        " | state^year")),
                                      data = d, lean = TRUE))
    pD <- f("delta_P_dalton", "epw_star"); pN <- f("delta_P_center", "epw_star")
    aD <- f("delta_P_dalton", "boom_star + bust_star")
    aN <- f("delta_P_center", "boom_star + bust_star")
    c(pooled_D = pD[["epw_star"]], pooled_N = pN[["epw_star"]],
      boom_D = aD[["boom_star"]], bust_D = aD[["bust_star"]],
      boom_N = aN[["boom_star"]], bust_N = aN[["bust_star"]])
  }))
}
cat("\n[G3] running RI under the arc-% treatment (base controls)...\n")
ri_arc_base <- ri_arc(ctrl_base); saveRDS(ri_arc_base, file.path(OUT, "ri_arc_base.rds"))
cat("[G3] running RI under the arc-% treatment (ext controls)...\n")
ri_arc_ext  <- ri_arc(ctrl_ext);  saveRDS(ri_arc_ext,  file.path(OUT, "ri_arc_ext.rds"))

key <- c("delta_P_dalton_pooled" = "pooled_D", "delta_P_center_pooled" = "pooled_N",
         "delta_P_dalton_boom" = "boom_D", "delta_P_center_boom" = "boom_N",
         "delta_P_dalton_bust" = "bust_D", "delta_P_center_bust" = "bust_N")
ril <- list(base = ri_arc_base, ext = ri_arc_ext)

res_arc <- res_arc |> rowwise() |>
  mutate(ri_p = { k <- paste0(outcome, "_", term)
                  if (!k %in% names(key)) NA_real_ else p_ri(ril[[ctrls]][, key[[k]]], beta) },
         ri_sd = { k <- paste0(outcome, "_", term)
                   if (!k %in% names(key)) NA_real_ else sd(ril[[ctrls]][, key[[k]]]) }) |>
  ungroup() |> mutate(sd_ratio = ri_sd / se)

cat("\n=== G3(3) Table 3 under the ARC-% treatment ===\n")
print(as.data.frame(res_arc |> select(outcome, ctrls, term, beta, se, ri_p, ri_sd,
                                      sd_ratio, p_sym, n)), digits = 4)

# ---- (5) BHJ shock-balance test under arc-% ---------------------------------
ind_obs <- shocks |> distinct(isic4, L_j_2010, exp_2010) |>
  mutate(div = as.integer(substr(isic4, 1, 2)),
         commodity = as.integer(div <= 9),
         log_Lj = log(L_j_2010), log_exp2010 = log1p(exp_2010),
         exp_per_L = exp_2010 / L_j_2010)
s_bar <- shocks |> filter(year == 2014) |>
  transmute(isic4, s_bar = L_j_2010 / sum(L_j_2010))
bal_df <- shocks_arc |> filter(year != 2010) |>
  select(isic4, year, g_jt, g_arc) |>
  inner_join(ind_obs, by = "isic4") |> inner_join(s_bar, by = "isic4")

balance_F <- function(dv, form_rhs, tag) {
  map_dfr(c(2014, 2018, 2022), function(t) {
    m  <- feols(as.formula(paste(dv, "~", form_rhs)), data = filter(bal_df, year == t),
                weights = ~ s_bar)
    fs <- fitstat(m, "f")$f
    tibble(spec = tag, shock = dv, year = t, F = fs$stat, df1 = fs$df1, df2 = fs$df2,
           p = fs$p, r2 = fitstat(m, "r2")$r2)
  })
}
bal <- bind_rows(
  balance_F("g_jt",  "commodity + log_exp2010", "primary_nonmechanical"),
  balance_F("g_arc", "commodity + log_exp2010", "primary_nonmechanical"),
  balance_F("g_jt",  "log_Lj + commodity + log_exp2010 + exp_per_L", "mechanical_incl_Lj"),
  balance_F("g_arc", "log_Lj + commodity + log_exp2010 + exp_per_L", "mechanical_incl_Lj"))
cat("\n=== G3(5) BHJ shock-balance test: level vs arc-% ===\n")
print(as.data.frame(bal), digits = 4)

write_csv(shocks_arc, file.path(OUT, "G3_shocks_arc.csv"))
write_csv(corr,       file.path(OUT, "G3_treatment_correlation.csv"))
write_csv(conc_all,   file.path(OUT, "G3_rotemberg_concentration.csv"))
write_csv(top5_all,   file.path(OUT, "G3_rotemberg_top5.csv"))
write_csv(bind_rows(rot_tbl), file.path(OUT, "G3_rotemberg_weights_full.csv"))
write_csv(res_arc,    file.path(OUT, "G3_table3_arc.csv"))
write_csv(bal,        file.path(OUT, "G3_bhj_balance.csv"))
saveRDS(tibble(micro = df_scaled$micro, year = df_scaled$year,
               epw_level = df_scaled$delta_EPW_raw, epw_arc = epw_arc_raw),
        file.path(OUT, "G3_epw_arc_panel.rds"))
cat("\n[G3] wrote", OUT, "\n")
