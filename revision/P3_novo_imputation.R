# =============================================================================
# P3 — NOVO (and PATRIOTA) imputation, applied symmetrically with the Bolsonaro
# rule. Referee item R2-M2. Runs regardless of the gates.
#
# The canonical index build (02_polarization_indices.R) imputes Bolsonaro's 2018
# position from BLS 9 -- the earliest wave in which he is scored -- but drops
# NOVO, which is ALSO scored only in BLS 9 and sits at the far right (0.711).
# This script applies the rule symmetrically and rebuilds every downstream
# object as a candidate new baseline. The current construction is retained
# unchanged as the robustness arm; nothing is overwritten.
#
# NOTE: a NOVO variant already exists at
#   "dados consolidados/índices corrigidos 13.07/dalton_panel_presidencial_novo2018.rds"
# but it was built by 00_outcome_polarizacao_v2.R, which ALSO substitutes
# Bolsonaro's individual score for PL in 2022 and imputes UNIAO 2022. It is
# therefore not a single-change variant against the canonical baseline. Rebuilt
# cleanly here so that NOVO is the only thing that moves.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("P3")
B_RI <- 9999

votes <- readRDS(paths$votos_pres)
bls   <- readRDS(paths$bls9) |> mutate(ano_eleicao = year + 1)

# ---- (1) which parties are scored, and where --------------------------------
cat("\n=== P3(1) BLS coverage of the parties in question ===\n")
for (p in c("NOVO", "PATRI", "PATRIOTA", "BOLSONARO", "PSL", "PL", "PSTU", "DC", "PPL", "UP", "PCB")) {
  hit <- bls |> filter(toupper(party.or.pres) == p)
  cat(sprintf("%-10s : %s\n", p,
              if (nrow(hit)) paste(sprintf("%d(ideo=%.3f)", hit$ano_eleicao, hit$ideo),
                                   collapse = " ") else "NEVER SCORED in any wave"))
}

# ---- (2) is v_rpt renormalised over scored parties? --------------------------
# 02_polarization_indices.R computes total_votes AFTER filter(!is.na(ideo)), so
# the shares renormalise to one over the scored set. Verify numerically.
ideo_base <- bind_rows(
  bls,
  bls |> filter(party.or.pres == "BOLSONARO", ano_eleicao == 2022) |>
    mutate(party.or.pres = "PSL", ano_eleicao = 2018))

build_idx <- function(ideo_tbl, tag) {
  pi <- votes |> filter(round == 1) |>
    left_join(ideo_tbl |> select(party.or.pres, ano_eleicao, ideo),
              by = c("party" = "party.or.pres", "year" = "ano_eleicao"))
  cov <- pi |> group_by(year) |>
    summarise(pct_scored = 100 * sum(votes[!is.na(ideo)]) / sum(votes),
              n_parties_scored = n_distinct(party[!is.na(ideo)]), .groups = "drop") |>
    mutate(variant = tag)
  idx <- pi |> filter(!is.na(ideo)) |>
    group_by(microregion_code, year) |>
    mutate(total_votes = sum(votes), v_rpt = votes / total_votes) |>
    summarise(check_sum = sum(v_rpt), n_scored = n(),
              y_bar = sum(v_rpt * ideo),
              P_dalton = sqrt(sum(v_rpt * (ideo - y_bar[1])^2)),
              P_center = 1 - sum(v_rpt * (ideo >= -0.25 & ideo <= 0.25)),
              right_share = sum(v_rpt * (ideo > 0.25)),
              .groups = "drop")
  list(idx = idx, cov = cov, panel = pi)
}

base_b <- build_idx(ideo_base, "baseline (current)")
cat("\n=== P3(2) renormalisation check: does sum_p v_rpt == 1 in every cell? ===\n")
cat(sprintf("max |sum(v_rpt) - 1| = %.3e over %d cells -> v_rpt IS renormalised over the SCORED set.\n",
            max(abs(base_b$idx$check_sum - 1)), nrow(base_b$idx)))
cat("Consequence to state in the paper: the weighted mean and weighted SD of\n",
    "Equation (2) are well defined, but the center-emptying DENOMINATOR is also\n",
    "the scored-vote total, so dropping a NON-neutral party (NOVO) mechanically\n",
    "RAISES the measured neutral share and LOWERS P^N in 2018.\n")

# ---- (3) rebuild with NOVO (and PATRIOTA if scored) --------------------------
novo9 <- bls |> filter(toupper(party.or.pres) == "NOVO") |> slice_max(ano_eleicao, n = 1)
patri <- bls |> filter(toupper(party.or.pres) %in% c("PATRI", "PATRIOTA"))
stopifnot("NOVO not scored in any wave" = nrow(novo9) == 1)
cat(sprintf("\n[P3] NOVO earliest/only score: wave for election %d, ideo = %.3f\n",
            novo9$ano_eleicao, novo9$ideo))
cat(sprintf("[P3] PATRIOTA scored in any wave: %s\n",
            if (nrow(patri)) paste(patri$ano_eleicao, collapse = ", ") else "NO -- cannot be imputed"))

ideo_novo <- bind_rows(ideo_base, novo9 |> mutate(ano_eleicao = 2018))
if (nrow(patri))
  ideo_novo <- bind_rows(ideo_novo,
                         patri |> slice_min(ano_eleicao, n = 1) |> mutate(ano_eleicao = 2018))
stopifnot(!any(duplicated(ideo_novo |> select(party.or.pres, ano_eleicao))))

novo_b <- build_idx(ideo_novo, "NOVO imputed")

# ---- (4) what changes -------------------------------------------------------
cov_cmp <- bind_rows(base_b$cov, novo_b$cov) |>
  select(variant, year, pct_scored, n_parties_scored) |>
  pivot_wider(names_from = variant, values_from = c(pct_scored, n_parties_scored))
cat("\n=== P3(4) BLS vote coverage, before vs after ===\n")
print(as.data.frame(cov_cmp), digits = 5)

cmp <- base_b$idx |> select(microregion_code, year, P_dalton, P_center, y_bar, right_share) |>
  left_join(novo_b$idx |> select(microregion_code, year, P_dalton_n = P_dalton,
                                 P_center_n = P_center, y_bar_n = y_bar,
                                 right_share_n = right_share),
            by = c("microregion_code", "year"))

chg <- cmp |> group_by(year) |>
  summarise(cor_PD = cor(P_dalton, P_dalton_n), mean_PD = mean(P_dalton),
            mean_PD_novo = mean(P_dalton_n), d_mean_PD = mean(P_dalton_n - P_dalton),
            sd_PD = sd(P_dalton), sd_PD_novo = sd(P_dalton_n),
            cor_PN = cor(P_center, P_center_n),
            d_mean_PN = mean(P_center_n - P_center),
            pct_PN_degenerate_novo = 100 * mean(abs(P_center_n - 1) < 1e-12),
            cor_ybar = cor(y_bar, y_bar_n), d_mean_ybar = mean(y_bar_n - y_bar),
            .groups = "drop")
cat("\n=== P3(4b) index change by year ===\n"); print(as.data.frame(chg), digits = 5)

# decile shift + regional pattern in 2018
d18 <- cmp |> filter(year == 2018) |>
  mutate(uf = substr(as.character(microregion_code), 1, 2),
         region = case_when(uf %in% c("11","12","13","14","15","16","17") ~ "North",
                            uf %in% c("21","22","23","24","25","26","27","28","29") ~ "Northeast",
                            uf %in% c("31","32","33","35") ~ "Southeast",
                            uf %in% c("41","42","43") ~ "South",
                            TRUE ~ "Center-West"),
         dec_old = ntile(P_dalton, 10), dec_new = ntile(P_dalton_n, 10))
cat("\n=== P3(4c) 2018 decile migration (rows = old decile, cols = new) ===\n")
print(table(old = d18$dec_old, new = d18$dec_new))
cat("\n=== P3(4d) 2018 change in P^D by region ===\n")
print(as.data.frame(d18 |> group_by(region) |>
  summarise(n = n(), mean_PD_old = mean(P_dalton), mean_PD_new = mean(P_dalton_n),
            d_PD = mean(P_dalton_n - P_dalton), d_PN = mean(P_center_n - P_center),
            .groups = "drop")), digits = 5)

# ---- (5) re-run the main specification --------------------------------------
mk_panel <- function(idx) {
  base10 <- idx |> filter(year == 2010) |>
    select(microregion_code, P_dalton_0 = P_dalton, P_center_0 = P_center)
  idx |> filter(year != 2010) |> left_join(base10, by = "microregion_code") |>
    transmute(micro = as.character(microregion_code), year,
              dPD = P_dalton - P_dalton_0, dPN = P_center - P_center_0)
}
p_new <- mk_panel(novo_b$idx); p_old <- mk_panel(base_b$idx)

d_new <- df_scaled |> select(-any_of(c("dPD", "dPN"))) |>
  left_join(p_new, by = c("micro", "year")) |>
  mutate(delta_P_dalton_novo = as.numeric(scale(dPD)),
         delta_P_center_novo = as.numeric(scale(dPN)),
         epw_boom = pmax( delta_EPW_raw, 0) / sd_epw,
         epw_bust = pmax(-delta_EPW_raw, 0) / sd_epw)
# sanity: the OLD rebuild must reproduce the panel's own outcome exactly
chk <- df_scaled |> select(micro, year, delta_P_dalton) |>
  left_join(p_old, by = c("micro", "year")) |>
  mutate(z = as.numeric(scale(dPD)))
cat(sprintf("\n[P3] rebuild check: max|z(rebuilt dP^D) - panel dP^D| = %.3e\n",
            max(abs(chk$z - chk$delta_P_dalton))))

novo_outcomes <- c("delta_P_dalton_novo", "delta_P_center_novo")
est <- map_dfr(novo_outcomes, function(oc) map_dfr(c("base", "ext"), function(ck) {
  ctrls <- if (ck == "base") ctrl_base else ctrl_ext
  cz <- paste(ctrls, collapse = " + ")
  mp <- feols(as.formula(paste(oc, "~ delta_EPW +", cz, "| state^year")),
              data = d_new, cluster = ~ mesoregion_code^year)
  md <- feols(as.formula(paste(oc, "~ epw_boom + epw_bust +", cz, "| state^year")),
              data = d_new, cluster = ~ mesoregion_code^year)
  b <- coef(md)[c("epw_boom","epw_bust")]; V <- vcov(md)[c("epw_boom","epw_bust"),c("epw_boom","epw_bust")]
  cc <- sum(b); s <- sqrt(sum(V))
  bind_rows(
    tibble(outcome = oc, ctrls = ck, term = "pooled", beta = coef(mp)[["delta_EPW"]],
           se = se(mp)[["delta_EPW"]], n = nobs(mp)),
    tibble(outcome = oc, ctrls = ck, term = "boom", beta = b[["epw_boom"]],
           se = se(md)[["epw_boom"]], n = nobs(md)),
    tibble(outcome = oc, ctrls = ck, term = "bust", beta = b[["epw_bust"]],
           se = se(md)[["epw_bust"]], n = nobs(md)),
    tibble(outcome = oc, ctrls = ck, term = "symmetry", beta = cc, se = s, n = nobs(md),
           p_sym = 2 * pt(-abs(cc/s), df = fixest::degrees_freedom(md, type = "t"))))
}))

ri_novo <- function(ctrls) {
  set.seed(2026); cz <- paste(ctrls, collapse = " + ")
  t(replicate(B_RI, {
    raw <- make_epw_star(sample(nrow(g_mat)))
    d <- d_new |> mutate(epw_star = raw/sd_epw, boom_star = pmax(raw,0)/sd_epw,
                         bust_star = pmax(-raw,0)/sd_epw)
    f <- function(dv, rhs) coef(feols(as.formula(paste0(dv," ~ ",rhs," + ",cz," | state^year")),
                                      data = d, lean = TRUE))
    pD <- f("delta_P_dalton_novo","epw_star"); pN <- f("delta_P_center_novo","epw_star")
    aD <- f("delta_P_dalton_novo","boom_star + bust_star")
    aN <- f("delta_P_center_novo","boom_star + bust_star")
    c(delta_P_dalton_novo_pooled = pD[["epw_star"]],
      delta_P_center_novo_pooled = pN[["epw_star"]],
      delta_P_dalton_novo_boom = aD[["boom_star"]],
      delta_P_dalton_novo_bust = aD[["bust_star"]],
      delta_P_center_novo_boom = aN[["boom_star"]],
      delta_P_center_novo_bust = aN[["bust_star"]])
  }))
}
cat("\n[P3] running RI (base)...\n"); rb <- ri_novo(ctrl_base)
cat("[P3] running RI (ext)...\n");   re <- ri_novo(ctrl_ext)
saveRDS(list(base = rb, ext = re), file.path(OUT, "P3_ri.rds"))

est <- est |> rowwise() |>
  mutate(ri_p = { k <- paste0(outcome,"_",term); m <- if (ctrls=="base") rb else re
                  if (!k %in% colnames(m)) NA_real_ else p_ri(m[,k], beta) },
         ri_sd = { k <- paste0(outcome,"_",term); m <- if (ctrls=="base") rb else re
                   if (!k %in% colnames(m)) NA_real_ else sd(m[,k]) }) |>
  ungroup() |> mutate(sd_ratio = ri_sd/se)

cat("\n=== P3(5) main specification under the NOVO-imputed outcomes ===\n")
print(as.data.frame(est), digits = 4)

saveRDS(novo_b$idx, file.path(OUT, "dalton_panel_presidencial_NOVOimputed.rds"))
write_csv(cov_cmp, file.path(OUT, "P3_coverage.csv"))
write_csv(chg,     file.path(OUT, "P3_index_change.csv"))
write_csv(est,     file.path(OUT, "P3_main_spec.csv"))
write_csv(cmp,     file.path(OUT, "P3_index_old_vs_new.csv"))
cat("\n[P3] wrote", OUT, "\n")
