# =============================================================================
# P1 — bound the null by inverting the randomization test. Referee item R1-M3.
# Runs because G3 holds (the null survives at 5-6 effective shifts).
#
# METHOD. Testing H0: beta = b means permuting on the adjusted outcome
# (y - b*x) and locating the observed statistic in the placebo distribution.
# Because OLS is linear in the outcome, this needs only TWO permutation passes
# rather than one pass per grid point:
#
#   observed statistic at b :  x'M(y - b x) / x'Mx           = beta_hat - b
#   placebo statistic at b  :  x*'M(y - b x) / x*'Mx*        = beta*_y - b * delta*_x
#
# where M residualises on the controls and the state-by-year fixed effects,
# beta*_y is the placebo coefficient with the real outcome, and delta*_x is the
# placebo coefficient from regressing the REAL treatment on the PERMUTED one.
# Both are stored per draw; the whole grid is then evaluated in closed form and
# is EXACT, not an approximation. The identity is asserted against a brute-force
# re-permutation at three grid points before the grid is trusted.
#
# The same algebra carries to the two-regressor decomposition: to test
# H0: beta_bust = b, adjust by b*bust and take delta* to be the coefficient on
# bust* from regressing bust on (boom*, bust*).
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("P1")
B_RI <- 9999

arc <- readRDS(file.path(REV_ROOT, "G3", "G3_epw_arc_panel.rds"))
stopifnot(identical(arc$micro, df_scaled$micro), identical(arc$year, df_scaled$year))
epw_arc_raw <- arc$epw_arc
sd_arc <- sd(epw_arc_raw)

g_arc <- shocks |>
  mutate(denom = 0.5 * (exp_national + exp_2010),
         g_arc = if_else(denom > 0, delta_exp / denom, 0)) |>
  filter(year %in% c(2014, 2018, 2022)) |> select(isic4, year, g_arc) |>
  pivot_wider(names_from = year, values_from = g_arc, values_fill = 0) |>
  column_to_rownames("isic4") |> as.matrix()
g_arc <- g_arc[colnames(W), , drop = FALSE]

# =============================================================================
# permutation pass: store, per draw, the placebo coefficients for the OUTCOMES
# and for the TREATMENTS themselves
# =============================================================================
ri_pass <- function(ctrls, gm, sd_anchor, tag) {
  set.seed(2026)
  cz <- paste(ctrls, collapse = " + ")
  t0 <- Sys.time()
  out <- t(replicate(B_RI, {
    raw <- make_epw_star(sample(nrow(gm)), gm = gm)
    d <- df_scaled |>
      mutate(epw_star  = raw / sd_anchor,
             boom_star = pmax( raw, 0) / sd_anchor,
             bust_star = pmax(-raw, 0) / sd_anchor,
             treat_z   = if (identical(tag, "arc")) as.numeric(scale(epw_arc_raw))
                         else delta_EPW,
             treat_boom = if (identical(tag, "arc")) pmax( epw_arc_raw, 0) / sd_anchor
                          else pmax( delta_EPW_raw, 0) / sd_anchor,
             treat_bust = if (identical(tag, "arc")) pmax(-epw_arc_raw, 0) / sd_anchor
                          else pmax(-delta_EPW_raw, 0) / sd_anchor)
    f1 <- function(dv) coef(feols(as.formula(paste0(dv, " ~ epw_star + ", cz,
                                                    " | state^year")), data = d, lean = TRUE))[["epw_star"]]
    f2 <- function(dv) coef(feols(as.formula(paste0(dv, " ~ boom_star + bust_star + ", cz,
                                                    " | state^year")), data = d, lean = TRUE))[c("boom_star","bust_star")]
    aD <- f2("delta_P_dalton"); aN <- f2("delta_P_center")
    aX <- f2("treat_boom");     aY <- f2("treat_bust")
    c(pooled_D = f1("delta_P_dalton"), pooled_N = f1("delta_P_center"),
      pooled_X = f1("treat_z"),
      boom_D = aD[["boom_star"]], bust_D = aD[["bust_star"]],
      boom_N = aN[["boom_star"]], bust_N = aN[["bust_star"]],
      boom_X = aX[["boom_star"]], bust_X = aY[["bust_star"]])
  }))
  cat(sprintf("[P1] pass %s/%s done in %.1f min\n", tag, paste(ctrls, collapse="+"),
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  out
}

# =============================================================================
# observed estimates
# =============================================================================
mk_df <- function(tag) {
  if (tag == "level")
    df_scaled |> mutate(treat_z = delta_EPW,
                        t_boom = pmax( delta_EPW_raw,0)/sd_epw,
                        t_bust = pmax(-delta_EPW_raw,0)/sd_epw)
  else
    df_scaled |> mutate(treat_z = as.numeric(scale(epw_arc_raw)),
                        t_boom = pmax( epw_arc_raw,0)/sd_arc,
                        t_bust = pmax(-epw_arc_raw,0)/sd_arc)
}
obs_beta <- function(tag, ctrls) {
  d <- mk_df(tag); cz <- paste(ctrls, collapse = " + ")
  p <- function(dv) coef(feols(as.formula(paste0(dv," ~ treat_z + ",cz," | state^year")), data=d))[["treat_z"]]
  a <- function(dv) coef(feols(as.formula(paste0(dv," ~ t_boom + t_bust + ",cz," | state^year")), data=d))[c("t_boom","t_bust")]
  aD <- a("delta_P_dalton"); aN <- a("delta_P_center")
  c(pooled_D = p("delta_P_dalton"), pooled_N = p("delta_P_center"),
    boom_D = aD[["t_boom"]], bust_D = aD[["t_bust"]],
    boom_N = aN[["t_boom"]], bust_N = aN[["t_bust"]])
}

# =============================================================================
# grid inversion
# =============================================================================
invert <- function(stars, hats, coefname, denom_col, grid) {
  bstar <- stars[, coefname]; dstar <- stars[, denom_col]; bhat <- hats[[coefname]]
  map_dfr(grid, function(b) {
    obs <- bhat - b
    pl  <- bstar - b * dstar
    tibble(b = b, p = (1 + sum(abs(pl) >= abs(obs))) / (length(pl) + 1))
  })
}
set_from <- function(tb, lev) {
  keep <- tb$b[tb$p > lev]
  if (!length(keep)) return(tibble(level = lev, lo = NA, hi = NA, contiguous = NA, n_pts = 0))
  idx <- which(tb$p > lev)
  tibble(level = lev, lo = min(keep), hi = max(keep),
         contiguous = all(diff(idx) == 1), n_pts = length(keep))
}

GRID <- seq(-0.30, 0.30, by = 0.002)

results <- list(); sets <- list(); passes <- list()
for (tag in c("level", "arc")) {
  gm <- if (tag == "level") g_mat else g_arc
  sa <- if (tag == "level") sd_epw else sd_arc
  for (ck in c("base", "ext")) {
    ctrls <- if (ck == "base") ctrl_base else ctrl_ext
    st <- ri_pass(ctrls, gm, sa, tag)
    passes[[paste(tag, ck)]] <- st
    hats <- obs_beta(tag, ctrls)
    for (cf in c("pooled_D", "pooled_N", "boom_D", "bust_D", "boom_N", "bust_N")) {
      dcol <- switch(substr(cf, 1, 4), "pool" = "pooled_X", "boom" = "boom_X", "bust" = "bust_X")
      tb <- invert(st, hats, cf, dcol, GRID) |> mutate(shock = tag, ctrls = ck, coef = cf)
      results[[paste(tag, ck, cf)]] <- tb
      sets[[paste(tag, ck, cf)]] <- bind_rows(set_from(tb, 0.05), set_from(tb, 0.10)) |>
        mutate(shock = tag, ctrls = ck, coef = cf, beta_hat = hats[[cf]], .before = 1)
    }
  }
}
saveRDS(passes, file.path(OUT, "P1_ri_passes.rds"))
res_all <- bind_rows(results); set_all <- bind_rows(sets)

cat("\n=== P1 randomization confidence SETS (standardised units: SD of outcome per SD of exposure) ===\n")
print(as.data.frame(set_all |> select(shock, ctrls, coef, beta_hat, level, lo, hi,
                                      contiguous, n_pts)), digits = 4)

# ---- brute-force validation of the linearity identity ------------------------
cat("\n=== P1 validation: closed-form vs brute-force re-permutation ===\n")
val <- map_dfr(c(-0.05, 0.0, 0.05), function(b) {
  set.seed(99); Bv <- 400
  cz <- paste(ctrl_base, collapse = " + ")
  bf <- replicate(Bv, {
    raw <- make_epw_star(sample(nrow(g_mat)))
    d <- df_scaled |> mutate(epw_star = raw / sd_epw,
                             y_adj = delta_P_dalton - b * delta_EPW)
    coef(feols(as.formula(paste0("y_adj ~ epw_star + ", cz, " | state^year")),
               data = d, lean = TRUE))[["epw_star"]]
  })
  set.seed(99)
  perms <- replicate(Bv, sample(nrow(g_mat)), simplify = FALSE)
  cf <- vapply(perms, function(perm) {
    raw <- make_epw_star(perm)
    d <- df_scaled |> mutate(epw_star = raw / sd_epw)
    by <- coef(feols(as.formula(paste0("delta_P_dalton ~ epw_star + ", cz, " | state^year")),
                     data = d, lean = TRUE))[["epw_star"]]
    dx <- coef(feols(as.formula(paste0("delta_EPW ~ epw_star + ", cz, " | state^year")),
                     data = d, lean = TRUE))[["epw_star"]]
    by - b * dx
  }, numeric(1))
  tibble(b = b, max_abs_gap = max(abs(bf - cf)))
})
print(as.data.frame(val), digits = 3)
stopifnot("linearity identity failed" = max(val$max_abs_gap) < 1e-8)

# ---- p-value curves for plotting --------------------------------------------
write_csv(res_all, file.path(OUT, "P1_pvalue_curves.csv"))
write_csv(set_all, file.path(OUT, "P1_confidence_sets.csv"))
write_csv(val,     file.path(OUT, "P1_validation.csv"))

pl <- res_all |> filter(coef %in% c("pooled_D", "bust_D", "boom_D"))
p <- ggplot(pl, aes(b, p, colour = coef, linetype = ctrls)) +
  geom_line() + facet_wrap(~ shock) +
  geom_hline(yintercept = c(0.05, 0.10), linetype = 3) +
  labs(x = expression(b~"(SD of "*Delta*P^D*" per SD of "*Delta*"EPW)"),
       y = "RI p-value of H0: beta = b") + theme_minimal()
ggsave(file.path(OUT, "P1_pvalue_curves.pdf"), p, width = 9, height = 4,
       device = grDevices::pdf)
cat("\n[P1] wrote", OUT, "\n")
