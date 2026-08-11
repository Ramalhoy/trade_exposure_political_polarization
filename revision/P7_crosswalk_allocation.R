# =============================================================================
# P7 — crosswalk-allocation sensitivity. Referee item R3-M2.
#
# The treatment allocates the export value of a multi-match NCM-6 code across
# its ISIC classes using the weights in ncm_isic_match_v7.rds. Rebuild it under
#   (base) the committed weights;
#   (a)   primary-match only  (all value to one ISIC class);
#   (b)   equal splitting     (1/n);
#   (c)   ISIC national-employment weights from RAIS 2010.
# Report the 4x4 correlation matrix among the resulting treatments and re-run
# the pooled specification under each.
#
# FIDELITY GUARD. This script re-walks the export side of stage 03 from the
# committed match table. Before any alternative is trusted, the rebuild under
# the committed weights is compared to exports_isic_v7.rds and to the v7 EPW
# panel. If the reproduction is not exact the script says so loudly and marks
# the task PARTIAL rather than reporting alternatives off an unverified base.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("P7")

match_tbl <- readRDS("ncm_isic_match_v7.rds")
cmap      <- readRDS("composite_map_v7.rds")
exports   <- readRDS(paths$exports_ncm)
cpi       <- readRDS("cpi_us.rds")
USD_UNIT  <- 1e4
SPECIAL   <- "^(97|98|99)"

# ---- is the committed weighting really "occurrence share"? -------------------
wchk <- match_tbl |> group_by(ncm6) |>
  summarise(n = n(), uniform = all(abs(w_ncm - 1/n[1]) < 1e-9), .groups = "drop")
cat(sprintf("\n=== P7(0) committed weights: %d NCM-6 codes, %d multi-match; %.1f%% have w = 1/n\n",
            nrow(wchk), sum(wchk$n > 1), 100*mean(wchk$uniform)))
cat("If that is 100%, the committed 'occurrence-share' weights are numerically\n",
    "IDENTICAL to equal splitting, so scheme (b) is not a separate specification\n",
    "and the paper's description of the rule should say so.\n")

# ---- rebuild the NCM-6 export series ----------------------------------------
cpi2010 <- cpi$cpi[cpi$year == 2010]
exp6 <- exports |>
  transmute(year = as.integer(ano), ncm8 = str_pad(as.character(id_ncm), 8, pad = "0"),
            value = as.numeric(valor_fob_dolar)) |>
  filter(!str_detect(ncm8, SPECIAL), year %in% election_years) |>
  left_join(cpi, by = "year") |>
  mutate(value_real = value * (cpi2010 / cpi) / USD_UNIT,
         ncm6 = str_sub(ncm8, 1, 6)) |>
  group_by(ncm6, year) |>
  summarise(value_real = sum(value_real), .groups = "drop")

Lj <- readRDS("rais_isic_v7.rds") |> group_by(isic4) |>
  summarise(L_group = sum(workers), .groups = "drop")     # composite-group level
Lclass <- readRDS("rais_isic_v7.rds")                     # already composited

# class-level employment for scheme (c): use the CNAE->ISIC RAIS mapping at the
# COMPOSITE-GROUP resolution the match table resolves to after cmap.
grp_of <- setNames(coalesce(cmap$isic_composite, cmap$isic4), cmap$isic4)

weight_schemes <- function(mt) {
  base_w <- mt
  primary <- mt |> group_by(ncm6) |>
    slice_max(w_ncm, n = 1, with_ties = FALSE) |>
    mutate(w_ncm = 1) |> ungroup()
  equal <- mt |> group_by(ncm6) |> mutate(w_ncm = 1/n()) |> ungroup()
  empw <- mt |>
    mutate(grp = coalesce(grp_of[isic4], isic4)) |>
    left_join(Lj |> rename(grp = isic4), by = "grp") |>
    mutate(L_group = replace_na(L_group, 0)) |>
    group_by(ncm6) |>
    mutate(w_ncm = if (sum(L_group) > 0) L_group / sum(L_group) else 1/n()) |>
    ungroup() |> select(ncm6, isic4, w_ncm)
  list(committed = base_w, primary_only = primary, equal_split = equal,
       employment_weighted = empw)
}
schemes <- weight_schemes(match_tbl)

build_treatment <- function(mt, tag) {
  ei <- exp6 |> inner_join(mt, by = "ncm6", relationship = "many-to-many") |>
    mutate(v = value_real * w_ncm) |>
    mutate(grp = coalesce(grp_of[isic4], isic4)) |>
    group_by(isic4 = grp, year) |>
    summarise(exp_national = sum(v), .groups = "drop") |>
    complete(isic4 = colnames(W), year = election_years,
             fill = list(exp_national = 0)) |>
    filter(isic4 %in% colnames(W))
  sh <- ei |> left_join(ei |> filter(year == 2010) |> select(isic4, e0 = exp_national),
                        by = "isic4") |>
    left_join(Lj, by = "isic4") |>
    mutate(g = (exp_national - e0) / L_group) |>
    filter(year %in% c(2014, 2018, 2022)) |>
    select(isic4, year, g) |>
    pivot_wider(names_from = year, values_from = g, values_fill = 0) |>
    column_to_rownames("isic4") |> as.matrix()
  sh <- sh[colnames(W), , drop = FALSE]
  list(g = sh, epw = make_epw_star(seq_len(nrow(sh)), gm = sh), tag = tag)
}

built <- imap(schemes, function(mt, nm) build_treatment(mt, nm))

# ---- FIDELITY GUARD ---------------------------------------------------------
gap_epw <- max(abs(built$committed$epw - df_scaled$delta_EPW_raw))
rel_gap <- gap_epw / sd(df_scaled$delta_EPW_raw)
cat(sprintf("\n=== P7 FIDELITY GUARD ===\nmax|rebuilt committed EPW - v7 EPW| = %.3e (%.4f SD of the treatment)\n",
            gap_epw, rel_gap))
cat(sprintf("cor(rebuilt committed, v7) = %.6f\n",
            cor(built$committed$epw, df_scaled$delta_EPW_raw)))
FIDELITY_OK <- rel_gap < 1e-6
if (!FIDELITY_OK)
  cat("!! The rebuild does NOT reproduce the committed treatment exactly. Stage 03\n",
      "   applies steps this script does not re-walk (producer-primacy filtering,\n",
      "   HS-vintage bridging of orphan codes, manual residual assignments). The\n",
      "   alternatives below are therefore RELATIVE comparisons within this\n",
      "   rebuild, not drop-in replacements for the v7 treatment. Task = PARTIAL.\n")

# ---- correlation matrix -----------------------------------------------------
M <- cbind(v7_committed_panel = df_scaled$delta_EPW_raw,
           map_dfc(built, ~ .x$epw) |> as.matrix())
colnames(M) <- c("v7_panel", names(built))
cormat <- round(cor(M), 4)
spear  <- round(cor(M, method = "spearman"), 4)
cat("\n=== P7 Pearson correlation among treatment series ===\n"); print(cormat)
cat("\n=== P7 Spearman ===\n"); print(spear)

desc <- map_dfr(colnames(M), function(k) tibble(
  series = k, mean = mean(M[,k]), sd = sd(M[,k]), min = min(M[,k]),
  p25 = quantile(M[,k],.25), median = median(M[,k]), p75 = quantile(M[,k],.75),
  max = max(M[,k])))
cat("\n=== P7 treatment descriptives by scheme ===\n"); print(as.data.frame(desc), digits = 4)

# ---- re-run the pooled specification under each -----------------------------
est <- map_dfr(colnames(M), function(k) {
  s <- sd(M[,k])
  d <- df_scaled |> mutate(t_z = as.numeric(scale(M[,k])),
                           t_boom = pmax( M[,k],0)/s, t_bust = pmax(-M[,k],0)/s)
  map_dfr(outcomes, function(oc) map_dfr(c("base","ext"), function(ck) {
    ctrls <- if (ck=="base") ctrl_base else ctrl_ext; cz <- paste(ctrls, collapse=" + ")
    mp <- feols(as.formula(paste(oc,"~ t_z +",cz,"| state^year")), data=d,
                cluster = ~ mesoregion_code^year)
    md <- feols(as.formula(paste(oc,"~ t_boom + t_bust +",cz,"| state^year")), data=d,
                cluster = ~ mesoregion_code^year)
    bind_rows(
      tibble(scheme=k, outcome=oc, ctrls=ck, term="pooled", beta=coef(mp)[["t_z"]],
             se=se(mp)[["t_z"]], n=nobs(mp)),
      tibble(scheme=k, outcome=oc, ctrls=ck, term="boom", beta=coef(md)[["t_boom"]],
             se=se(md)[["t_boom"]], n=nobs(md)),
      tibble(scheme=k, outcome=oc, ctrls=ck, term="bust", beta=coef(md)[["t_bust"]],
             se=se(md)[["t_bust"]], n=nobs(md)))
  }))
})
cat("\n=== P7 estimates under each allocation rule (cluster SEs; no RI) ===\n")
print(as.data.frame(est), digits = 4)

# Rotemberg concentration under each scheme (base controls)
rot <- map_dfr(names(built), function(k) {
  gm <- built[[k]]$g
  s <- sd(built[[k]]$epw)
  d <- df_scaled |> mutate(t_raw = built[[k]]$epw)
  map_dfr(c("2014","2018","2022"), function(t) {
    sel <- df_scaled$year == as.integer(t)
    xp <- resid(lm(reformulate(c(ctrl_base, "factor(state)"), response = "t_raw"),
                   data = d[sel, ]))
    num <- gm[colnames(W), t] * as.numeric(t(W[sel,,drop=FALSE]) %*% xp)
    a <- num/sum(num)
    tibble(scheme=k, year=t, eff_n = 1/sum((abs(a)/sum(abs(a)))^2),
           top1 = max(abs(a))/sum(abs(a)))
  })
})
cat("\n=== P7 effective number of shifts under each allocation rule ===\n")
print(as.data.frame(rot), digits = 4)

write_csv(as_tibble(cormat, rownames = "series"), file.path(OUT, "P7_correlation_pearson.csv"))
write_csv(as_tibble(spear,  rownames = "series"), file.path(OUT, "P7_correlation_spearman.csv"))
write_csv(desc, file.path(OUT, "P7_treatment_descriptives.csv"))
write_csv(est,  file.path(OUT, "P7_estimates.csv"))
write_csv(rot,  file.path(OUT, "P7_rotemberg.csv"))
writeLines(sprintf("FIDELITY_OK = %s | max abs gap = %.6e | rel to SD = %.6e",
                   FIDELITY_OK, gap_epw, rel_gap),
           file.path(OUT, "P7_fidelity.txt"))
cat("\n[P7] wrote", OUT, "\n")
