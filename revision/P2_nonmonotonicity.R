# =============================================================================
# P2 — is the null mechanical? Outcome non-monotonicity diagnostics.
# Referee item R2-M1.
#
# Gate note: the task file conditions P2 on G2 passing. G2 could not be
# evaluated in the first pass (no post-2010 RAIS locally; see G2 log). P2 is run
# anyway because it diagnoses the OUTCOME, not the shock: nothing in it depends
# on whether the shock moved local labour markets, and it is the highest-value
# item in the file. Read its verdict independently of G2.
#
# One instruction could not be executed literally and a documented substitute is
# used instead: step 3 asks for a split on the "2010 median right-flank vote
# share". No party on the 2010 ballot is scored above +0.25 on the BLS scale
# (the right-most 2010 candidate sits at +0.09), so that variable is identically
# zero and the split is empty. Two predetermined substitutes are reported:
#   (a) the 2010 vote-share-weighted mean position ybar_r,2010 (continuous,
#       predetermined, and the natural "how right-leaning was this microregion
#       before treatment" measure); and
#   (b) the 2010 vote share of the right-most party actually on the 2010 ballot.
# The contemporaneous above/below-50% split the referee describes is ALSO
# reported, explicitly labelled as descriptive rather than identifying.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("P2")
B_RI <- 9999

votes <- readRDS(paths$votos_pres)
bls   <- readRDS(paths$bls9) |> mutate(ano_eleicao = year + 1)
ideo  <- bind_rows(bls, bls |> filter(party.or.pres == "BOLSONARO", ano_eleicao == 2022) |>
                     mutate(party.or.pres = "PSL", ano_eleicao = 2018))

# =============================================================================
# (1) DISTRIBUTION OF THE TOP-CANDIDATE FIRST-ROUND VOTE SHARE
# =============================================================================
top_share <- votes |> filter(round == 1) |>
  group_by(microregion_code, year) |>
  summarise(total = sum(votes), top = max(votes),
            top_party = party[which.max(votes)],
            top_share = top / total, .groups = "drop")

dist_tbl <- top_share |> group_by(year) |>
  summarise(n = n(), mean = mean(top_share), sd = sd(top_share),
            min = min(top_share),
            d1 = quantile(top_share, .1), d2 = quantile(top_share, .2),
            d3 = quantile(top_share, .3), d4 = quantile(top_share, .4),
            median = quantile(top_share, .5),
            d6 = quantile(top_share, .6), d7 = quantile(top_share, .7),
            d8 = quantile(top_share, .8), d9 = quantile(top_share, .9),
            max = max(top_share),
            frac_above_50 = mean(top_share > 0.5), .groups = "drop")
cat("\n=== P2(1) top-candidate first-round vote share, by year ===\n")
print(as.data.frame(dist_tbl), digits = 4)
cat("\n=== P2(1b) which party is top, by year ===\n")
print(as.data.frame(top_share |> count(year, top_party) |>
                      group_by(year) |> mutate(pct = 100*n/sum(n)) |> ungroup()), digits = 3)

# =============================================================================
# (2) CURVATURE: is P^D an inverted U in the top-candidate share?
# =============================================================================
pol <- readRDS("dalton_panel_presidencial.rds")
cur <- pol |> mutate(microregion_code = as.integer(microregion_code)) |>
  inner_join(top_share |> mutate(microregion_code = as.integer(microregion_code)),
             by = c("microregion_code", "year"))

quad <- map_dfr(sort(unique(cur$year)), function(t) {
  d <- filter(cur, year == t)
  m <- lm(P_dalton ~ top_share + I(top_share^2), data = d)
  b <- coef(m)
  tibble(year = t, n = nrow(d), b0 = b[[1]], b1 = b[[2]], b2 = b[[3]],
         se_b2 = summary(m)$coefficients[3, 2],
         t_b2 = summary(m)$coefficients[3, 3],
         turning_point = -b[[2]] / (2 * b[[3]]),
         concave = b[[3]] < 0, r2 = summary(m)$r.squared,
         range_lo = min(d$top_share), range_hi = max(d$top_share))
})
cat("\n=== P2(2) quadratic fit of P^D on the top-candidate share, by year ===\n")
print(as.data.frame(quad), digits = 4)
cat("Read: b2 < 0 with a turning point INSIDE the observed range of top_share is\n",
    "the inverted U the referee posits. b2 > 0, or a turning point outside the\n",
    "range, means the index is monotone over the support the data occupy.\n")

# decile means, the non-parametric version
bins <- cur |> group_by(year) |> mutate(bin = ntile(top_share, 20)) |>
  group_by(year, bin) |>
  summarise(top_share = mean(top_share), P_dalton = mean(P_dalton), n = n(), .groups = "drop")
pcur <- ggplot(bins, aes(top_share, P_dalton)) + geom_point() +
  geom_smooth(method = "loess", se = FALSE, formula = y ~ x) +
  facet_wrap(~ year, scales = "free_y") +
  geom_vline(xintercept = 0.5, linetype = 2) +
  labs(x = "Top-candidate first-round vote share (20-bin means)",
       y = expression(P^D)) + theme_minimal()
ggsave(file.path(OUT, "P2_curvature.pdf"), pcur, width = 8, height = 6,
       device = grDevices::pdf)

# =============================================================================
# (3) SPLIT-SAMPLE ESTIMATES ON A PREDETERMINED 2010 SPLIT
# =============================================================================
idx2010 <- votes |> filter(round == 1, year == 2010) |>
  left_join(ideo |> select(party.or.pres, ano_eleicao, ideo),
            by = c("party" = "party.or.pres", "year" = "ano_eleicao")) |>
  filter(!is.na(ideo)) |>
  group_by(microregion_code) |>
  mutate(v = votes / sum(votes)) |>
  summarise(ybar_2010 = sum(v * ideo),
            right_share_2010 = sum(v * (ideo > 0.25)),
            rightmost_share_2010 = v[which.max(ideo)],
            rightmost_ideo_2010 = max(ideo), .groups = "drop") |>
  mutate(micro = as.character(microregion_code))
cat("\n=== P2(3) predetermined 2010 splitting variables ===\n")
print(as.data.frame(idx2010 |> summarise(
  n = n(), rightmost_ideo = first(rightmost_ideo_2010),
  mean_ybar = mean(ybar_2010), median_ybar = median(ybar_2010),
  min_ybar = min(ybar_2010), max_ybar = max(ybar_2010),
  mean_right_share = mean(right_share_2010),
  mean_rightmost_share = mean(rightmost_share_2010))), digits = 4)
cat("Note: right_share_2010 (parties scored above +0.25) is identically",
    unique(idx2010$right_share_2010), "-- the literal split is empty.\n")

d_sp <- df_scaled |>
  left_join(idx2010 |> select(micro, ybar_2010, rightmost_share_2010), by = "micro") |>
  mutate(hi_ybar = ybar_2010 > median(ybar_2010, na.rm = TRUE),
         hi_rmost = rightmost_share_2010 > median(rightmost_share_2010, na.rm = TRUE),
         epw_boom = pmax( delta_EPW_raw, 0) / sd_epw,
         epw_bust = pmax(-delta_EPW_raw, 0) / sd_epw)
stopifnot(!anyNA(d_sp$ybar_2010))

# contemporaneous descriptive split (NOT identifying)
d_sp <- d_sp |>
  left_join(top_share |> mutate(micro = as.character(microregion_code)) |>
              select(micro, year, top_share), by = c("micro", "year")) |>
  mutate(top_above_50 = top_share > 0.5)
cat("\n=== P2(3b) contemporaneous split sizes (descriptive) ===\n")
print(as.data.frame(d_sp |> count(year, top_above_50)))

split_est <- function(data, sub_name, sub_flag) {
  map_dfr(c(TRUE, FALSE), function(v) {
    d <- data[data[[sub_flag]] == v, ]
    map_dfr(c("base", "ext"), function(ck) {
      ctrls <- if (ck == "base") ctrl_base else ctrl_ext
      cz <- paste(ctrls, collapse = " + ")
      mp <- feols(as.formula(paste("delta_P_dalton ~ delta_EPW +", cz, "| state^year")),
                  data = d, cluster = ~ mesoregion_code^year)
      md <- feols(as.formula(paste("delta_P_dalton ~ epw_boom + epw_bust +", cz,
                                   "| state^year")), data = d, cluster = ~ mesoregion_code^year)
      bind_rows(
        tibble(split = sub_name, side = if (v) "high" else "low", ctrls = ck,
               term = "pooled", beta = coef(mp)[["delta_EPW"]], se = se(mp)[["delta_EPW"]], n = nobs(mp)),
        tibble(split = sub_name, side = if (v) "high" else "low", ctrls = ck,
               term = "boom", beta = coef(md)[["epw_boom"]], se = se(md)[["epw_boom"]], n = nobs(md)),
        tibble(split = sub_name, side = if (v) "high" else "low", ctrls = ck,
               term = "bust", beta = coef(md)[["epw_bust"]], se = se(md)[["epw_bust"]], n = nobs(md)))
    })
  })
}
splits <- bind_rows(
  split_est(d_sp, "2010 ybar (predetermined)", "hi_ybar"),
  split_est(d_sp, "2010 rightmost-party share (predetermined)", "hi_rmost"),
  split_est(d_sp, "top share > 50% (CONTEMPORANEOUS, descriptive)", "top_above_50"))

# RI for the predetermined ybar split (the key output)
ri_split <- function(data, sub_flag, v, ctrls) {
  set.seed(2026); cz <- paste(ctrls, collapse = " + ")
  sel <- which(data[[sub_flag]] == v)
  Ws <- W[sel, , drop = FALSE]
  idx <- cbind(seq_along(sel), match(as.character(data$year[sel]), YEARS))
  ds <- data[sel, ]
  t(replicate(B_RI, {
    raw <- make_epw_star(sample(nrow(g_mat)), Wm = Ws, idx = idx)
    d <- ds |> mutate(epw_star = raw/sd_epw, boom_star = pmax(raw,0)/sd_epw,
                      bust_star = pmax(-raw,0)/sd_epw)
    p <- coef(feols(as.formula(paste0("delta_P_dalton ~ epw_star + ",cz," | state^year")),
                    data = d, lean = TRUE))
    a <- coef(feols(as.formula(paste0("delta_P_dalton ~ boom_star + bust_star + ",cz,
                                      " | state^year")), data = d, lean = TRUE))
    c(pooled = p[["epw_star"]], boom = a[["boom_star"]], bust = a[["bust_star"]])
  }))
}
cat("\n[P2] running RI for the predetermined ybar split (base controls)...\n")
ri_hi <- ri_split(d_sp, "hi_ybar", TRUE,  ctrl_base)
ri_lo <- ri_split(d_sp, "hi_ybar", FALSE, ctrl_base)
saveRDS(list(hi = ri_hi, lo = ri_lo), file.path(OUT, "P2_ri_split.rds"))

splits <- splits |> rowwise() |>
  mutate(ri_p = if (split == "2010 ybar (predetermined)" && ctrls == "base") {
    m <- if (side == "high") ri_hi else ri_lo; p_ri(m[, term], beta) } else NA_real_) |>
  ungroup()
cat("\n=== P2(3c) split-sample estimates, delta_P_dalton ===\n")
print(as.data.frame(splits), digits = 4)

# =============================================================================
# (4)(5) DIRECTIONAL OUTCOMES: ybar_rt and the right-flank vote share
# =============================================================================
dir_idx <- votes |> filter(round == 1) |>
  left_join(ideo |> select(party.or.pres, ano_eleicao, ideo),
            by = c("party" = "party.or.pres", "year" = "ano_eleicao")) |>
  filter(!is.na(ideo)) |>
  group_by(microregion_code, year) |>
  mutate(v = votes / sum(votes)) |>
  summarise(ybar = sum(v * ideo),
            right_flank = sum(v * (ideo > 0.25)), .groups = "drop")

dir_d <- dir_idx |> filter(year != 2010) |>
  left_join(dir_idx |> filter(year == 2010) |>
              select(microregion_code, ybar0 = ybar, rf0 = right_flank),
            by = "microregion_code") |>
  transmute(micro = as.character(microregion_code), year,
            d_ybar = ybar - ybar0, d_right = right_flank - rf0)
cat("\n=== P2(4)(5) directional outcomes, raw descriptives by year ===\n")
print(as.data.frame(dir_d |> group_by(year) |>
  summarise(mean_d_ybar = mean(d_ybar), sd_d_ybar = sd(d_ybar),
            mean_d_right = mean(d_right), sd_d_right = sd(d_right), .groups="drop")), digits = 4)

d_dir <- d_sp |> left_join(dir_d, by = c("micro", "year")) |>
  mutate(d_ybar_z = as.numeric(scale(d_ybar)), d_right_z = as.numeric(scale(d_right)))
stopifnot(!anyNA(d_dir$d_ybar_z))

dir_outcomes <- c("d_ybar_z", "d_right_z")
est_dir <- map_dfr(dir_outcomes, function(oc) map_dfr(c("base","ext"), function(ck) {
  ctrls <- if (ck=="base") ctrl_base else ctrl_ext; cz <- paste(ctrls, collapse=" + ")
  mp <- feols(as.formula(paste(oc,"~ delta_EPW +",cz,"| state^year")), data=d_dir,
              cluster = ~ mesoregion_code^year)
  md <- feols(as.formula(paste(oc,"~ epw_boom + epw_bust +",cz,"| state^year")), data=d_dir,
              cluster = ~ mesoregion_code^year)
  b <- coef(md)[c("epw_boom","epw_bust")]; V <- vcov(md)[c("epw_boom","epw_bust"),c("epw_boom","epw_bust")]
  cc <- sum(b); s <- sqrt(sum(V))
  bind_rows(
    tibble(outcome=oc, ctrls=ck, term="pooled", beta=coef(mp)[["delta_EPW"]],
           se=se(mp)[["delta_EPW"]], n=nobs(mp), within_r2=fitstat(mp,"wr2")$wr2),
    tibble(outcome=oc, ctrls=ck, term="boom", beta=b[["epw_boom"]], se=se(md)[["epw_boom"]],
           n=nobs(md), within_r2=fitstat(md,"wr2")$wr2),
    tibble(outcome=oc, ctrls=ck, term="bust", beta=b[["epw_bust"]], se=se(md)[["epw_bust"]],
           n=nobs(md), within_r2=fitstat(md,"wr2")$wr2),
    tibble(outcome=oc, ctrls=ck, term="symmetry", beta=cc, se=s, n=nobs(md), within_r2=NA_real_,
           p_sym=2*pt(-abs(cc/s), df=fixest::degrees_freedom(md,type="t"))))
}))

ri_dir <- function(ctrls) {
  set.seed(2026); cz <- paste(ctrls, collapse=" + ")
  t(replicate(B_RI, {
    raw <- make_epw_star(sample(nrow(g_mat)))
    d <- d_dir |> mutate(epw_star=raw/sd_epw, boom_star=pmax(raw,0)/sd_epw,
                         bust_star=pmax(-raw,0)/sd_epw)
    unlist(lapply(dir_outcomes, function(oc) {
      p <- coef(feols(as.formula(paste0(oc," ~ epw_star + ",cz," | state^year")), data=d, lean=TRUE))
      a <- coef(feols(as.formula(paste0(oc," ~ boom_star + bust_star + ",cz," | state^year")), data=d, lean=TRUE))
      setNames(c(p[["epw_star"]], a[["boom_star"]], a[["bust_star"]]),
               paste0(oc, c("_pooled","_boom","_bust")))
    }))
  }))
}
cat("\n[P2] running RI for the directional outcomes (base)...\n"); rdb <- ri_dir(ctrl_base)
cat("[P2] running RI for the directional outcomes (ext)...\n");    rde <- ri_dir(ctrl_ext)
saveRDS(list(base=rdb, ext=rde), file.path(OUT, "P2_ri_directional.rds"))

est_dir <- est_dir |> rowwise() |>
  mutate(ri_p = { k <- paste0(outcome,"_",term); m <- if (ctrls=="base") rdb else rde
                  if (!k %in% colnames(m)) NA_real_ else p_ri(m[,k], beta) },
         ri_sd = { k <- paste0(outcome,"_",term); m <- if (ctrls=="base") rdb else rde
                   if (!k %in% colnames(m)) NA_real_ else sd(m[,k]) }) |>
  ungroup() |> mutate(sd_ratio = ri_sd/se)
cat("\n=== P2(4)(5) directional outcomes, main specification ===\n")
print(as.data.frame(est_dir), digits = 4)

write_csv(dist_tbl, file.path(OUT, "P2_top_share_distribution.csv"))
write_csv(quad,     file.path(OUT, "P2_curvature_quadratic.csv"))
write_csv(bins,     file.path(OUT, "P2_curvature_bins.csv"))
write_csv(splits,   file.path(OUT, "P2_split_sample.csv"))
write_csv(est_dir,  file.path(OUT, "P2_directional_outcomes.csv"))
write_csv(dir_d,    file.path(OUT, "P2_directional_panel.csv"))
cat("\n[P2] wrote", OUT, "\n")
