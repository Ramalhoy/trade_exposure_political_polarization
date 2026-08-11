# =============================================================================
# P5 — stratified randomization inference. Referee item R1-M2.
# The current RI permutes 152 industry identities unstratified, so crude
# petroleum's shock path can land on a small food-processing group. Re-run
# permuting WITHIN ISIC section (A/B/C) and WITHIN quartiles of L_j,2010, and
# report quantile-based rather than SD-based p-values, plus the shape of each
# placebo distribution.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("P5")
B_RI <- 9999

ind <- tibble(isic4 = colnames(W)) |>
  left_join(shocks |> distinct(isic4, L_j_2010), by = "isic4") |>
  mutate(div = as.integer(substr(isic4, 1, 2)),
         section = case_when(div <= 3 ~ "A", div <= 9 ~ "B", TRUE ~ "C"),
         size_q  = ntile(L_j_2010, 4))
stopifnot(!anyNA(ind$L_j_2010))
cat("\n=== P5 strata sizes ===\n")
print(as.data.frame(ind |> count(section)))
print(as.data.frame(ind |> count(size_q)))
print(as.data.frame(ind |> count(section, size_q)))

perm_within <- function(strata) {
  idx <- seq_along(strata)
  out <- idx
  for (s in unique(strata)) {
    k <- which(strata == s)
    out[k] <- k[sample(length(k))]
  }
  out
}

d <- df_scaled |> mutate(epw_boom = pmax( delta_EPW_raw, 0)/sd_epw,
                         epw_bust = pmax(-delta_EPW_raw, 0)/sd_epw)

ri_scheme <- function(ctrls, scheme) {
  set.seed(2026); cz <- paste(ctrls, collapse = " + ")
  strata <- switch(scheme, unstratified = NULL,
                   section = ind$section, size = as.character(ind$size_q))
  t(replicate(B_RI, {
    perm <- if (is.null(strata)) sample(nrow(g_mat)) else perm_within(strata)
    raw  <- make_epw_star(perm)
    dd <- d |> mutate(epw_star = raw/sd_epw, boom_star = pmax(raw,0)/sd_epw,
                      bust_star = pmax(-raw,0)/sd_epw)
    f1 <- function(dv) coef(feols(as.formula(paste0(dv," ~ epw_star + ",cz," | state^year")),
                                  data = dd, lean = TRUE))[["epw_star"]]
    f2 <- function(dv) coef(feols(as.formula(paste0(dv," ~ boom_star + bust_star + ",cz,
                                                    " | state^year")), data = dd,
                                  lean = TRUE))[c("boom_star","bust_star")]
    aD <- f2("delta_P_dalton"); aN <- f2("delta_P_center")
    c(pooled_D = f1("delta_P_dalton"), pooled_N = f1("delta_P_center"),
      boom_D = aD[[1]], bust_D = aD[[2]], boom_N = aN[[1]], bust_N = aN[[2]])
  }))
}

obs <- function(ctrls) {
  cz <- paste(ctrls, collapse = " + ")
  p <- function(dv) coef(feols(as.formula(paste0(dv," ~ delta_EPW + ",cz," | state^year")), data=d))[["delta_EPW"]]
  a <- function(dv) coef(feols(as.formula(paste0(dv," ~ epw_boom + epw_bust + ",cz," | state^year")), data=d))[c("epw_boom","epw_bust")]
  aD <- a("delta_P_dalton"); aN <- a("delta_P_center")
  c(pooled_D = p("delta_P_dalton"), pooled_N = p("delta_P_center"),
    boom_D = aD[[1]], bust_D = aD[[2]], boom_N = aN[[1]], bust_N = aN[[2]])
}

skew <- function(x) mean((x - mean(x))^3) / sd(x)^3
kurt <- function(x) mean((x - mean(x))^4) / sd(x)^4

res <- list(); shape <- list()
for (ck in c("base", "ext")) {
  ctrls <- if (ck == "base") ctrl_base else ctrl_ext
  hats <- obs(ctrls)
  for (sc in c("unstratified", "section", "size")) {
    cat(sprintf("\n[P5] RI | controls %s | scheme %s ...\n", ck, sc))
    m <- ri_scheme(ctrls, sc)
    saveRDS(m, file.path(OUT, sprintf("ri_%s_%s.rds", ck, sc)))
    for (cf in colnames(m)) {
      x <- m[, cf]
      # quantile-based two-sided p: the fraction of placebos at least as
      # EXTREME as the estimate in the direction it points, doubled -- and the
      # symmetric |.| version for comparison
      p_abs <- (1 + sum(abs(x) >= abs(hats[[cf]]))) / (B_RI + 1)
      p_q   <- 2 * min((1 + sum(x >= hats[[cf]])) / (B_RI + 1),
                       (1 + sum(x <= hats[[cf]])) / (B_RI + 1))
      res[[length(res)+1]] <- tibble(
        ctrls = ck, scheme = sc, coef = cf, beta_hat = hats[[cf]],
        p_abs = p_abs, p_quantile = min(p_q, 1), placebo_sd = sd(x))
      shape[[length(shape)+1]] <- tibble(
        ctrls = ck, scheme = sc, coef = cf,
        mean = mean(x), median = median(x), sd = sd(x),
        skew = skew(x), kurtosis = kurt(x),
        q001 = quantile(x, .001), q025 = quantile(x, .025), q05 = quantile(x, .05),
        q25 = quantile(x, .25), q75 = quantile(x, .75),
        q95 = quantile(x, .95), q975 = quantile(x, .975), q999 = quantile(x, .999),
        min = min(x), max = max(x),
        sd_trim10 = sd(x[x >= quantile(x, .05) & x <= quantile(x, .95)]),
        # centred at zero under the sharp null?
        t_mean0 = mean(x) / (sd(x)/sqrt(length(x))))
    }
  }
}
res_all <- bind_rows(res); shape_all <- bind_rows(shape)

cat("\n=== P5 p-values under three permutation schemes ===\n")
print(as.data.frame(res_all |> select(ctrls, coef, scheme, beta_hat, p_abs,
                                      p_quantile, placebo_sd) |>
                      arrange(ctrls, coef, scheme)), digits = 4)
cat("\n=== P5 placebo-distribution shape ===\n")
print(as.data.frame(shape_all |> select(ctrls, scheme, coef, mean, sd, sd_trim10,
                                        skew, kurtosis, q025, q975, t_mean0)), digits = 4)
cat("\nRead t_mean0: |t| > ~2 means the placebo distribution is NOT centred at zero,\n",
    "which would indicate the sharp null is not being imposed correctly.\n")

write_csv(res_all,   file.path(OUT, "P5_pvalues_by_scheme.csv"))
write_csv(shape_all, file.path(OUT, "P5_placebo_shape.csv"))
write_csv(ind,       file.path(OUT, "P5_strata.csv"))
cat("\n[P5] wrote", OUT, "\n")
