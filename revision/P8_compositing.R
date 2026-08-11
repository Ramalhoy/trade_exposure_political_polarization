# =============================================================================
# P8 — compositing and by-year diagnostics. Referee item R3-M3.
# The composite share of export value rises from 24.3% (2010) to 39.2% (2022),
# so the RI exchangeability unit coarsens over the sample. Report the effective
# number of shifts and Rotemberg concentration by year, and re-run RI under a
# fixed compositing scheme common to all years.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("P8")
B_RI <- 9999

cmap <- readRDS("composite_map_v7.rds")
cat("\n=== P8(1) composite structure ===\n")
grp <- cmap |> count(isic_composite, name = "n_classes")
cat(sprintf("ISIC classes mapped: %d -> %d groups; %d multi-class composites absorbing %d classes\n",
            nrow(cmap), nrow(grp), sum(grp$n_classes > 1),
            sum(grp$n_classes[grp$n_classes > 1])))
print(as.data.frame(grp |> filter(n_classes > 1) |> arrange(desc(n_classes))))

# export value inside multi-constituent composites, by year
multi <- grp |> filter(n_classes > 1) |> pull(isic_composite)
val <- shocks |> group_by(year) |>
  summarise(total = sum(exp_national),
            in_multi = sum(exp_national[isic4 %in% multi]),
            pct_in_multi = 100 * in_multi / total, .groups = "drop")
cat("\n=== P8(1b) share of export value inside multi-class composites, by year ===\n")
print(as.data.frame(val), digits = 4)

# ---- (1) Rotemberg by year, both control sets (level shock) ------------------
rot_by_year <- function(ctrls) {
  map_dfr(c("2014","2018","2022"), function(t) {
    sel <- df_scaled$year == as.integer(t)
    dd  <- df_scaled[sel, ]; Wt <- W[sel, , drop = FALSE]
    xp  <- resid(lm(reformulate(c(ctrls, "factor(state)"), response = "delta_EPW_raw"),
                    data = dd))
    num <- g_mat[colnames(Wt), t] * as.numeric(t(Wt) %*% xp)
    a <- num / sum(num)
    tibble(year = t, hhi = sum((abs(a)/sum(abs(a)))^2), eff_n = 1/sum((abs(a)/sum(abs(a)))^2),
           top1 = max(abs(a))/sum(abs(a)),
           top3 = sum(sort(abs(a), decreasing = TRUE)[1:3])/sum(abs(a)),
           top5 = sum(sort(abs(a), decreasing = TRUE)[1:5])/sum(abs(a)),
           n_pos = sum(a > 0), n_neg = sum(a < 0), sum_alpha = sum(a))
  })
}
conc <- bind_rows(rot_by_year(ctrl_base) |> mutate(ctrls = "base"),
                  rot_by_year(ctrl_ext)  |> mutate(ctrls = "ext"))
cat("\n=== P8(1c) Rotemberg concentration by year (level shock) ===\n")
print(as.data.frame(conc), digits = 4)

# ---- (2) FIXED compositing common across years -------------------------------
# The exchangeability unit should be constant over the sample. Build the
# coarsest grouping that is separable in EVERY year: an ISIC group is kept
# separate only if it carries non-zero export value in all three difference
# years AND in the base year; everything else is merged into its ISIC DIVISION
# (2-digit), which is separable throughout by construction.
present <- shocks |> group_by(isic4) |>
  summarise(all_years_pos = all(exp_national > 0), .groups = "drop")
fixed_map <- present |>
  mutate(group = if_else(all_years_pos, isic4, paste0("D", substr(isic4, 1, 2))))
cat(sprintf("\n=== P8(2) fixed compositing: %d groups (from %d), %d classes merged into divisions\n",
            n_distinct(fixed_map$group), nrow(fixed_map), sum(!fixed_map$all_years_pos)))
print(as.data.frame(fixed_map |> filter(!all_years_pos)))

# aggregate W columns and g rows to the fixed grouping. EPW is linear in both,
# so aggregating the SHARE columns and re-deriving the group shock as the
# employment-weighted mean of its members' shocks reproduces the treatment
# exactly when the group is a singleton, and coarsens it otherwise.
Lj <- shocks |> distinct(isic4, L_j_2010)
grp_of <- setNames(fixed_map$group, fixed_map$isic4)
grp_of <- grp_of[colnames(W)]
Wg <- t(rowsum(t(W), grp_of))                      # shares add within group
# group shock: sum_j delta_exp_j / sum_j L_j  (the correct per-worker aggregate)
gg <- shocks |> filter(year %in% c(2014,2018,2022)) |>
  mutate(group = grp_of[isic4]) |> filter(!is.na(group)) |>
  group_by(group, year) |>
  summarise(g = sum(delta_exp) / sum(L_j_2010), .groups = "drop") |>
  pivot_wider(names_from = year, values_from = g, values_fill = 0) |>
  column_to_rownames("group") |> as.matrix()
gg <- gg[colnames(Wg), , drop = FALSE]

idx <- cbind(seq_len(nrow(Wg)), match(as.character(df_scaled$year), YEARS))
epw_fixed <- sapply(YEARS, function(t) as.numeric(Wg %*% gg[, t]))[idx]
cat(sprintf("cor(delta_EPW, fixed-composite EPW) = %.4f (Spearman %.4f)\n",
            cor(df_scaled$delta_EPW_raw, epw_fixed),
            cor(df_scaled$delta_EPW_raw, epw_fixed, method = "spearman")))

sd_fix <- sd(epw_fixed)
d_fix <- df_scaled |> mutate(epw_fix_z = as.numeric(scale(epw_fixed)),
                             fix_boom = pmax( epw_fixed,0)/sd_fix,
                             fix_bust = pmax(-epw_fixed,0)/sd_fix)

est <- map_dfr(outcomes, function(oc) map_dfr(c("base","ext"), function(ck) {
  ctrls <- if (ck=="base") ctrl_base else ctrl_ext; cz <- paste(ctrls, collapse=" + ")
  mp <- feols(as.formula(paste(oc,"~ epw_fix_z +",cz,"| state^year")), data=d_fix,
              cluster = ~ mesoregion_code^year)
  md <- feols(as.formula(paste(oc,"~ fix_boom + fix_bust +",cz,"| state^year")), data=d_fix,
              cluster = ~ mesoregion_code^year)
  bind_rows(
    tibble(outcome=oc, ctrls=ck, term="pooled", beta=coef(mp)[["epw_fix_z"]], se=se(mp)[["epw_fix_z"]], n=nobs(mp)),
    tibble(outcome=oc, ctrls=ck, term="boom", beta=coef(md)[["fix_boom"]], se=se(md)[["fix_boom"]], n=nobs(md)),
    tibble(outcome=oc, ctrls=ck, term="bust", beta=coef(md)[["fix_bust"]], se=se(md)[["fix_bust"]], n=nobs(md)))
}))

ri_fix <- function(ctrls) {
  set.seed(2026); cz <- paste(ctrls, collapse=" + ")
  t(replicate(B_RI, {
    perm <- sample(nrow(gg))
    raw  <- sapply(YEARS, function(t) as.numeric(Wg %*% gg[perm, t]))[idx]
    dd <- df_scaled |> mutate(epw_star = raw/sd_fix, boom_star = pmax(raw,0)/sd_fix,
                              bust_star = pmax(-raw,0)/sd_fix)
    f1 <- function(dv) coef(feols(as.formula(paste0(dv," ~ epw_star + ",cz," | state^year")), data=dd, lean=TRUE))[["epw_star"]]
    f2 <- function(dv) coef(feols(as.formula(paste0(dv," ~ boom_star + bust_star + ",cz," | state^year")), data=dd, lean=TRUE))[c("boom_star","bust_star")]
    aD <- f2("delta_P_dalton"); aN <- f2("delta_P_center")
    c(delta_P_dalton_pooled=f1("delta_P_dalton"), delta_P_center_pooled=f1("delta_P_center"),
      delta_P_dalton_boom=aD[[1]], delta_P_dalton_bust=aD[[2]],
      delta_P_center_boom=aN[[1]], delta_P_center_bust=aN[[2]])
  }))
}
cat("\n[P8] RI under fixed compositing (base)...\n"); rb <- ri_fix(ctrl_base)
cat("[P8] RI under fixed compositing (ext)...\n");    re <- ri_fix(ctrl_ext)
saveRDS(list(base=rb, ext=re), file.path(OUT, "P8_ri.rds"))

est <- est |> rowwise() |>
  mutate(ri_p = { k <- paste0(outcome,"_",term); m <- if (ctrls=="base") rb else re
                  if (!k %in% colnames(m)) NA_real_ else p_ri(m[,k], beta) },
         ri_sd = { k <- paste0(outcome,"_",term); m <- if (ctrls=="base") rb else re
                   if (!k %in% colnames(m)) NA_real_ else sd(m[,k]) }) |>
  ungroup() |> mutate(sd_ratio = ri_sd/se)
cat("\n=== P8(2b) main specification under fixed compositing ===\n")
print(as.data.frame(est), digits = 4)

# Rotemberg under fixed compositing
rot_fix <- map_dfr(c("2014","2018","2022"), function(t) {
  sel <- df_scaled$year == as.integer(t)
  dd <- d_fix[sel, ]; Wt <- Wg[sel, , drop = FALSE]
  xp <- resid(lm(reformulate(c(ctrl_base, "factor(state)"), response = "epw_fix_z"), data = dd))
  num <- gg[colnames(Wt), t] * as.numeric(t(Wt) %*% xp); a <- num/sum(num)
  tibble(year=t, hhi=sum((abs(a)/sum(abs(a)))^2), eff_n=1/sum((abs(a)/sum(abs(a)))^2),
         top1=max(abs(a))/sum(abs(a)))
})
cat("\n=== P8(2c) Rotemberg under fixed compositing (base controls) ===\n")
print(as.data.frame(rot_fix), digits = 4)

write_csv(grp,       file.path(OUT, "P8_composite_groups.csv"))
write_csv(val,       file.path(OUT, "P8_composite_value_share.csv"))
write_csv(conc,      file.path(OUT, "P8_rotemberg_by_year.csv"))
write_csv(fixed_map, file.path(OUT, "P8_fixed_compositing_map.csv"))
write_csv(est,       file.path(OUT, "P8_fixed_compositing_estimates.csv"))
write_csv(rot_fix,   file.path(OUT, "P8_rotemberg_fixed.csv"))
cat("\n[P8] wrote", OUT, "\n")
