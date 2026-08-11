# =============================================================================
# D6_entrepot_ladder_and_2022.R  —  Packet D, Stage 1, step 6
# -----------------------------------------------------------------------------
# TWO JOBS.
#
# (1) Apply the entrepot exclusion to S2 as well. Z_jt is destination-weighted,
#     so entrepots enter it too. S2 is dead at eff_n 1.85, but a ladder where one
#     rung uses a different destination universe than another is indefensible
#     even in an appendix.
#
# (2) Diagnose the 2022 destination-balance deterioration: F went 2.78 -> 4.06
#     (p = 0.0008) when entrepots came out, while 2018 improved.
#     HYPOTHESIS: the surviving identifying variation is geopolitical. Dropping
#     LCA redistributes weight onto CHN, VEN, RUS, IRN. Venezuela is contiguous
#     with Brazil and `contig` is on the RHS; Russia's 2022 collapse is Ukraine
#     sanctions. Gravity covariates are good predictors of which countries have
#     geopolitical events, so the balance test picks that up. If so, 2022 is not
#     a data defect but a statement about what the design identifies off.
#     Four tests: per-term coefficients, leave-one-destination-out,
#     leave-one-entrepot-out, and unweighted.
#
# No outcome regression.
# Run: LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 Rscript códigos/packet_D/D6_entrepot_ladder_and_2022.R
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
suppressPackageStartupMessages(library(fixest))

OUT_D          <- file.path("output", "packet_D")
ELECTION_YEARS <- c(2014L, 2018L, 2022L)
YEARS_CHR      <- as.character(ELECTION_YEARS)
BASE_YEAR      <- 2010L
ENTREPOT_ISO3  <- c("NLD", "SGP", "HKG", "ARE", "LCA")
N_ISIC_EXPECTED <- 152L
BENCH_EFF_LEVEL <- 2.589602662949854
BAL_ALPHA      <- 0.05
GRAVITY_YEAR   <- 2010L
BAL_RHS_DEST   <- "log_gdpcap_d + log_dist + contig + comlang_off + china + top5"
FOCUS_YEAR     <- 2022L
LOO_REPORT_N   <- 12

dir.create(OUT_D, showWarnings = FALSE, recursive = TRUE)
D6_OUT <- c("D6_S2_entrepot.csv", "D6_bal2022_coefs.csv", "D6_bal2022_loo.csv",
            "D6_bal2022_entrepot_loo.csv", "D6_bal_weighting.csv",
            "tab_d6_2022_diagnosis.md")
existing <- D6_OUT[file.exists(file.path(OUT_D, D6_OUT))]
if (length(existing)) stop("[D6] refusing to overwrite:\n  ",
                           paste(existing, collapse = "\n  "))

log_con <- file(file.path(OUT_D, "D6_run_log.txt"), open = "wt")
sink(log_con, split = TRUE)
cat("=== D6:", format(Sys.time()), "===\n\n")
write_csv_safe <- function(x, f) { if (file.exists(f)) unlink(f); readr::write_csv(x, f) }
md <- function(df, digits = 4) {
  d <- df |> mutate(across(where(is.double), ~ signif(.x, digits))) |>
    mutate(across(everything(), as.character))
  rows <- do.call(paste, c(unname(as.list(d)), sep = " | "))
  paste(c(paste0("| ", paste(names(d), collapse = " | "), " |"),
          paste0("| ", paste(rep("---", ncol(d)), collapse = " | "), " |"),
          paste0("| ", rows, " |")), collapse = "\n")
}

d1 <- readRDS(file.path(OUT_D, "D1_s_rd.rds"))
g_dt <- readRDS(file.path(OUT_D, "D3_g_dt.rds"))
omega_jd <- readRDS(file.path(OUT_D, "D2_omega_jd.rds"))
m_dp_row <- readRDS(file.path(OUT_D, "D2_m_dp_row.rds"))
s_rd <- d1$s_rd; baci_countries <- d1$baci_countries
ent_codes <- baci_countries |> filter(baci_iso3 %in% ENTREPOT_ISO3) |> pull(destino)
chn_code  <- baci_countries |> filter(baci_iso3 == "CHN") |> pull(destino)

arc <- function(v_t, v_0) { den <- 0.5 * (v_t + v_0)
  if_else(den > 0, (v_t - v_0) / den, 0) }

# =============================================================================
# JOB 1 — S2 WITH ENTREPOTS EXCLUDED
# -----------------------------------------------------------------------------
# [D-47] omega_jd IS A COMPOSITION, so its leave-out RENORMALISES.
# This is the same rule as [D-43], applied consistently rather than by analogy:
#   incomplete share set (N2, sum = theta_r) -> drop the column, theta_r falls
#   composition      (N1, omega_jd, sum = 1) -> renormalise over survivors
# Dropping destinations from omega_jd WITHOUT renormalising would shrink Z_jt
# toward zero by an industry-specific factor - a scale distortion masquerading
# as an exclusion, and it would differ across industries by how much each sells
# through entrepots.
# =============================================================================
ncm_isic_v7   <- readRDS("ncm_isic_match_v7.rds")
composite_map <- readRDS("composite_map_v7.rds")
universe      <- sort(unique(readRDS("sectoral_shocks_isic_v7.rds")$isic4))

m_dj_row <- m_dp_row |>
  inner_join(ncm_isic_v7, by = c("hs6" = "ncm6"), relationship = "many-to-many") |>
  mutate(val = m * w_ncm) |>
  left_join(composite_map |> select(isic4, isic_composite), by = "isic4") |>
  mutate(isic4 = coalesce(isic_composite, isic4)) |>
  filter(isic4 %in% universe) |>
  group_by(destino, isic4, ano) |> summarise(m = sum(val), .groups = "drop")

build_Z <- function(drop_ent) {
  oj <- omega_jd |> select(isic4, destino, omega_jd)
  if (drop_ent) oj <- oj |> filter(!destino %in% ent_codes) |>
    group_by(isic4) |> mutate(omega_jd = omega_jd / sum(omega_jd)) |> ungroup()
  stopifnot("[D6] omega_jd does not sum to 1 within industry" =
              all(abs(oj |> group_by(isic4) |> summarise(s = sum(omega_jd)) |>
                        pull(s) - 1) < 1e-8))
  w <- oj |> crossing(ano = c(BASE_YEAR, ELECTION_YEARS)) |>
    left_join(m_dj_row, by = c("destino", "isic4", "ano")) |>
    mutate(m = replace_na(m, 0)) |>
    pivot_wider(names_from = ano, values_from = m, names_prefix = "m_", values_fill = 0)
  map_dfr(ELECTION_YEARS, function(t)
    w |> transmute(isic4, omega_jd,
                   a = arc(.data[[paste0("m_", t)]], m_2010), ano = t) |>
      group_by(isic4, ano) |> summarise(Z = sum(omega_jd * a), .groups = "drop"))
}
Z_all <- build_Z(FALSE); Z_ex <- build_Z(TRUE)
stopifnot(n_distinct(Z_ex$isic4) == N_ISIC_EXPECTED,
          all(abs(Z_ex$Z) <= 2 + 1e-9))

rotemberg_for <- function(treat_vec, gm, Wm, ctrls) {
  d_all <- df_scaled |> mutate(.treat = treat_vec)
  map_dfr(YEARS_CHR, function(t) {
    sel <- df_scaled$year == as.integer(t); d <- d_all[sel, ]
    Wt <- Wm[sel, , drop = FALSE]
    x_perp <- resid(lm(reformulate(c(ctrls, "factor(state)"), response = ".treat"), data = d))
    num <- gm[colnames(Wt), t] * as.numeric(t(Wt) %*% x_perp)
    tibble(unit = colnames(Wt), year = t, alpha = num / sum(num))
  })
}
conc <- function(rot) {
  by_year <- rot |> group_by(year) |>
    summarise(eff_n = 1 / sum((abs(alpha)/sum(abs(alpha)))^2),
              top1 = max(abs(alpha))/sum(abs(alpha)),
              top1_unit = unit[which.max(abs(alpha))], .groups = "drop")
  bind_rows(by_year, tibble(year = "mean of yearly", eff_n = mean(by_year$eff_n),
                            top1 = mean(by_year$top1), top1_unit = NA_character_))
}
epw_of <- function(Wm, gm) {
  m <- sapply(YEARS_CHR, function(t) as.numeric(Wm %*% gm[, t]))
  m[cbind(seq_len(nrow(Wm)), match(as.character(df_scaled$year), YEARS_CHR))]
}
gmZ <- function(Z) { M <- Z |> pivot_wider(names_from = ano, values_from = Z,
                                           values_fill = 0) |>
  column_to_rownames("isic4") |> as.matrix(); M[colnames(W), YEARS_CHR, drop = FALSE] }

r0 <- rotemberg_for(df_scaled$delta_EPW_raw, g_mat[colnames(W), YEARS_CHR], W, ctrl_base)
stopifnot("[D6] S0 canary failed" = abs(conc(r0)$eff_n[4] - BENCH_EFF_LEVEL) < 1e-6)
cat("CANARY: S0 eff_n =", round(conc(r0)$eff_n[4], 4), "\n\n")

s2_tbl <- bind_rows(
  conc(rotemberg_for(epw_of(W, gmZ(Z_all)), gmZ(Z_all), W, ctrl_base)) |>
    mutate(spec = "S2 Z_jt, all destinations"),
  conc(rotemberg_for(epw_of(W, gmZ(Z_ex)), gmZ(Z_ex), W, ctrl_base)) |>
    mutate(spec = "S2 Z_jt, entrepots dropped"))
cat("=== D6(1) S2 WITH AND WITHOUT ENTREPOTS ===\n")
print(as.data.frame(s2_tbl |> select(spec, year, eff_n, top1, top1_unit)), digits = 4)
cat(sprintf("\nrho(Z_all, Z_ex) pooled = %.4f\n",
            cor(Z_all$Z, Z_ex$Z[match(paste(Z_all$isic4, Z_all$ano),
                                      paste(Z_ex$isic4, Z_ex$ano))])))
write_csv_safe(s2_tbl, file.path(OUT_D, "D6_S2_entrepot.csv"))

# =============================================================================
# JOB 2 — THE 2022 BALANCE DETERIORATION
# =============================================================================
grav_dir <- "CEPII Gravity database"
grav <- readRDS(file.path(grav_dir, "Gravity_V202211.rds"))
grav_bra <- grav |> filter(iso3_o == "BRA", year == GRAVITY_YEAR) |>
  select(iso3_d, gdpcap_d, dist, contig, comlang_off) |>
  distinct(iso3_d, .keep_all = TRUE)
rm(grav); gc()
x_d <- s_rd |> group_by(destino) |> summarise(x_d = sum(x_rd), .groups = "drop") |>
  mutate(share_2010 = x_d / sum(x_d))
top5_dest <- x_d |> slice_max(share_2010, n = 5) |> pull(destino)
bal_base <- g_dt |> left_join(x_d |> select(destino, share_2010), by = "destino") |>
  left_join(grav_bra, by = c("iso3" = "iso3_d")) |>
  mutate(log_gdpcap_d = log(gdpcap_d), log_dist = log(dist),
         china = as.integer(destino == chn_code),
         top5 = as.integer(destino %in% top5_dest), s_bar = share_2010) |>
  filter(is.finite(log_gdpcap_d), is.finite(log_dist), !is.na(contig),
         !is.na(comlang_off), !is.na(s_bar))

fitF <- function(d, wtd = TRUE) {
  m <- if (wtd) feols(as.formula(paste("g_dt ~", BAL_RHS_DEST)), data = d, weights = ~ s_bar)
       else     feols(as.formula(paste("g_dt ~", BAL_RHS_DEST)), data = d)
  f <- fitstat(m, "f")[[1]]; list(m = m, F = f$stat, p = f$p, n = nobs(m))
}

# ---- (1) per-term coefficients, 2022, both samples --------------------------
coefs <- map_dfr(c("all destinations", "entrepots dropped"), function(sc) {
  d <- filter(bal_base, ano == FOCUS_YEAR)
  if (sc == "entrepots dropped") d <- filter(d, !destino %in% ent_codes)
  m <- fitF(d)$m
  tibble(sample = sc, term = names(coef(m)), beta = as.numeric(coef(m)),
         t = as.numeric(tstat(m))) |> filter(term != "(Intercept)")
})
cat("\n=== D6(2a) 2022 BALANCE COEFFICIENTS, BOTH SAMPLES ===\n")
print(as.data.frame(coefs |> pivot_wider(names_from = sample,
                                         values_from = c(beta, t))), digits = 4)
write_csv_safe(coefs, file.path(OUT_D, "D6_bal2022_coefs.csv"))

# ---- (2) leave-one-destination-out on the 2022 F ----------------------------
d22 <- filter(bal_base, ano == FOCUS_YEAR, !destino %in% ent_codes)
F_full <- fitF(d22)
loo <- map_dfr(unique(d22$destino), function(dd) {
  f <- fitF(filter(d22, destino != dd))
  tibble(dropped = dd, F = f$F, p = f$p)
}) |> left_join(baci_countries |> select(dropped = destino, iso3 = baci_iso3),
                by = "dropped") |>
  left_join(x_d |> select(dropped = destino, share_2010), by = "dropped") |>
  mutate(dF = F - F_full$F) |> arrange(dF)
cat(sprintf("\n=== D6(2b) LEAVE-ONE-DESTINATION-OUT, 2022 (full F = %.3f, p = %.5f) ===\n",
            F_full$F, F_full$p))
cat("Largest REDUCTIONS in F (these destinations carry the failure):\n")
print(as.data.frame(loo |> slice_head(n = LOO_REPORT_N) |>
                      select(iso3, share_2010, F, p, dF)), digits = 4)
write_csv_safe(loo, file.path(OUT_D, "D6_bal2022_loo.csv"))

# ---- (3) leave-one-entrepot-out ---------------------------------------------
ent_loo <- map_dfr(c("none dropped", ENTREPOT_ISO3, "all five dropped"), function(e) {
  d <- filter(bal_base, ano == FOCUS_YEAR)
  if (e == "all five dropped") d <- filter(d, !destino %in% ent_codes)
  else if (e != "none dropped") {
    cd <- baci_countries |> filter(baci_iso3 == e) |> pull(destino)
    d <- filter(d, destino != cd)
  }
  f <- fitF(d)
  tibble(dropped = e, n = f$n, F = f$F, p = f$p, passes = f$p >= BAL_ALPHA)
})
cat("\n=== D6(2c) LEAVE-ONE-ENTREPOT-OUT, 2022 ===\n")
print(as.data.frame(ent_loo), digits = 4)
write_csv_safe(ent_loo, file.path(OUT_D, "D6_bal2022_entrepot_loo.csv"))

# ---- (4) weighted vs unweighted, all cycles ---------------------------------
wt_tbl <- map_dfr(c(TRUE, FALSE), function(wtd)
  map_dfr(c("all destinations", "entrepots dropped"), function(sc)
    map_dfr(ELECTION_YEARS, function(t) {
      d <- filter(bal_base, ano == t)
      if (sc == "entrepots dropped") d <- filter(d, !destino %in% ent_codes)
      f <- fitF(d, wtd)
      tibble(weighting = if (wtd) "2010 export share" else "unweighted",
             sample = sc, year = t, F = f$F, p = f$p, passes = f$p >= BAL_ALPHA)
    })))
cat("\n=== D6(2d) WEIGHTED VS UNWEIGHTED ===\n")
print(as.data.frame(wt_tbl), digits = 4)
write_csv_safe(wt_tbl, file.path(OUT_D, "D6_bal_weighting.csv"))

writeLines(c(
  "# Packet D — S2 entrepot exclusion and the 2022 balance diagnosis",
  "", paste0("Generated ", format(Sys.time()), "."),
  "", "## 1. S2 with entrepots dropped (`[D-47]`: omega_jd is a composition, so renormalise)",
  "", md(s2_tbl |> select(spec, year, eff_n, top1, top1_unit)),
  "", "## 2a. 2022 balance coefficients, both samples",
  "", md(coefs |> pivot_wider(names_from = sample, values_from = c(beta, t))),
  "", paste0("## 2b. Leave-one-destination-out (full F = ", round(F_full$F, 3),
             ", p = ", signif(F_full$p, 3), ")"),
  "", md(loo |> slice_head(n = LOO_REPORT_N) |> select(iso3, share_2010, F, p, dF)),
  "", "## 2c. Leave-one-entrepot-out", "", md(ent_loo),
  "", "## 2d. Weighted vs unweighted", "", md(wt_tbl), ""
), file.path(OUT_D, "tab_d6_2022_diagnosis.md"))

cat("\n[D6] wrote", OUT_D, "\n")
sink(); close(log_con)
