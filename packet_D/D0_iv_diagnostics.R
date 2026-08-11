# =============================================================================
# D0_iv_diagnostics.R  —  Packet D, Phase 1, STAGE 0
# -----------------------------------------------------------------------------
# Diagnoses the instruments that 03b_instrument_construction.R produces. It does
# NOT rebuild them: 03b was re-run unmodified on 2026-08-10 and this script reads
# sectoral_demand_iv_v1.rds and epw_iv_panel_v1.rds off disk.
#
# Three questions, none of which has ever been answered in this repository:
#
#   1. What is the ACTUAL first-stage F for IV-A and IV-B?  [D-3a] records
#      "weak first stage" as unverified recollection from another machine.
#      This converts it to record.
#   2. Do z_A and z_B pass the BHJ balance tests that g_jt fails?  Newly
#      possible: sector_chars.rds was only built 2026-08-10 ([D-0-4]), so no
#      balance test could ever have been run on these instruments ([D-3]).
#   3. Do the Rotemberg weights de-concentrate?  This isolates whether
#      exogeneity ALONE touches the 0710/0610 dominance, or whether the level
#      normalisation is doing all the work ([D-3b]).
#
# STRICTLY ADDITIVE. Reads locked artefacts; writes only under output/packet_D/.
# Aborts rather than overwriting. No outcome regression is run here — Phase 1 is
# instruments and diagnostics only, and answering [D-PRE-2] before touching
# delta_P_dalton makes specification search structurally impossible.
#
# Run:  LANG=en_US.UTF-8 Rscript códigos/packet_D/D0_iv_diagnostics.R
#   [D-5] The UTF-8 locale is REQUIRED, not cosmetic. Under a US-ASCII codeset
#   (the default for a non-interactive shell on this machine) readr resolves the
#   accented absolute path "dissertação/…/versão com vínculos totais" to a mixed
#   NFC/NFD byte string and every read_csv/write_csv fails with "cannot open the
#   connection". base::read.csv on a RELATIVE path is unaffected, which is why
#   the failure is intermittent across the existing pipeline. 03b's first
#   execution died at STEP 3 on exactly this. Nothing in any script was changed
#   to accommodate it.
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
# ^ read-only use of the locked revision/ tree. Sourcing it is what guarantees
#   that W, df_scaled, ctrl_base and make_epw_star() are byte-identical to the
#   objects G3 used, so the effective-shock counts below are comparable to the
#   2.59 / 5.57 benchmarks rather than merely similar.

suppressPackageStartupMessages(library(fixest))

# ---- NAMED CONSTANTS (no hidden defaults) -----------------------------------
OUT_D            <- file.path("output", "packet_D")
N_ISIC_EXPECTED  <- 152L      # v7 post-composite industry universe
YEARS_EST        <- c(2014L, 2018L, 2022L)

# Balance-test right-hand sides. Reproduced verbatim from the two existing
# tests so that z_A / z_B are read against g_jt / g_arc on the same ruler.
BAL_RHS_WORKFORCE <- "sh_loweduc + sh_white + sh_male + mean_lnwage"  # G4 / 07 §6
BAL_RHS_TRADE     <- "commodity + log_exp2010"                        # G3 primary
COMMODITY_DIV_MAX <- 9L       # ISIC divisions 01-09 = agriculture + mining (G3)
BAL_ALPHA         <- 0.05     # "passes balance" = fail to reject at 5%

# Rotemberg control set. G3 reports both; "base" carries the headline 2.59/5.57.
ROT_CTRLS_NAME    <- "base"

# Benchmarks from G3_rotemberg_concentration.csv, mean-of-yearly, base controls.
BENCH_EFF_LEVEL   <- 2.589602662949854
BENCH_EFF_ARC     <- 5.568901834676357

# ---- output guard: abort rather than overwrite ------------------------------
dir.create(OUT_D, showWarnings = FALSE, recursive = TRUE)
D0_OUT <- c("D0_firststage.csv", "D0_balance.csv", "D0_rotemberg.csv",
            "D0_rotemberg_top5.csv", "D0_shock_distributions.csv",
            "D0_shock_correlations.csv", "tab_d0_stage0.md", "fig_d0_shocks.pdf")
existing <- D0_OUT[file.exists(file.path(OUT_D, D0_OUT))]
if (length(existing))
  stop("[D0] refusing to overwrite existing packet_D output:\n  ",
       paste(existing, collapse = "\n  "),
       "\nMove or delete them deliberately before re-running.")

log_con <- file(file.path(OUT_D, "D0_run_log.txt"), open = "wt")
sink(log_con, split = TRUE)
cat("=== D0 Stage-0 instrument diagnostics:", format(Sys.time()), "===\n")
cat("SHARE_DENOM =", SHARE_DENOM, "| N_SAMPLE =", N_SAMPLE,
    "| industries =", ncol(W), "\n\n")

# =============================================================================
# STEP 1 — LOAD 03b OUTPUT AND THE COMPARISON SHOCKS
# =============================================================================
stopifnot(
  "[D0] sectoral_demand_iv_v1.rds absent — re-run 03b first" =
    file.exists("sectoral_demand_iv_v1.rds"),
  "[D0] epw_iv_panel_v1.rds absent — re-run 03b first" =
    file.exists("epw_iv_panel_v1.rds"))

z_panel <- readRDS("sectoral_demand_iv_v1.rds")
epw_iv  <- readRDS("epw_iv_panel_v1.rds") |> mutate(micro = as.character(micro))

stopifnot(
  "[D0] instrument industry set != v7 universe" =
    n_distinct(z_panel$isic4) == N_ISIC_EXPECTED,
  "[D0] instrument industry set != share matrix columns" =
    setequal(unique(z_panel$isic4), colnames(W)),
  "[D0] z_A/z_B carry NA" = !anyNA(z_panel$z_A) && !anyNA(z_panel$z_B),
  "[D0] base year must be identically zero by construction" =
    all(abs(z_panel$z_A[z_panel$year == 2010]) < 1e-12) &&
    all(abs(z_panel$z_B[z_panel$year == 2010]) < 1e-12))

# g_arc from G3 (read-only). Reproducing its benchmarks is this script's canary:
# if 2.59 / 5.57 do not come back, the Rotemberg machinery here is not the
# machinery that produced the numbers in RATIONALE_D and nothing below compares.
arc_path <- file.path("output", "revision", "G3", "G3_shocks_arc.csv")
stopifnot("[D0] G3_shocks_arc.csv absent — run G3 first" = file.exists(arc_path))
shocks_arc <- read.csv(arc_path, colClasses = c(isic4 = "character")) |> as_tibble()

# =============================================================================
# STEP 2 — SHOCK MATRICES ON THE SHARE-MATRIX COLUMN ORDER
#   Every construction below uses the SAME W. Any difference in a Rotemberg
#   weight or an effective-shock count is therefore attributable to the shock
#   series alone, which is the whole point of the ladder ([D-1]).
# =============================================================================
g_mat_from <- function(df, col) {
  m <- df |>
    filter(year %in% YEARS_EST) |>
    select(isic4, year, all_of(col)) |>
    pivot_wider(names_from = year, values_from = all_of(col), values_fill = 0) |>
    column_to_rownames("isic4") |> as.matrix()
  stopifnot("[D0] shock matrix does not span the share matrix" =
              all(colnames(W) %in% rownames(m)))
  m[colnames(W), as.character(YEARS_EST), drop = FALSE]
}

g_mat_arc <- g_mat_from(shocks_arc, "g_arc")
g_mat_zA  <- g_mat_from(z_panel,    "z_A")
g_mat_zB  <- g_mat_from(z_panel,    "z_B")
g_mat_zC  <- g_mat_from(z_panel,    "z_CHN")
stopifnot(identical(dim(g_mat), dim(g_mat_zA)))

epw_arc <- make_epw_star(seq_len(nrow(g_mat_arc)), gm = g_mat_arc)
epw_zA  <- make_epw_star(seq_len(nrow(g_mat_zA)),  gm = g_mat_zA)
epw_zB  <- make_epw_star(seq_len(nrow(g_mat_zB)),  gm = g_mat_zB)
epw_zC  <- make_epw_star(seq_len(nrow(g_mat_zC)),  gm = g_mat_zC)

# Cross-check the regional instrument rebuilt here against the one 03b saved.
# 03b builds it over ALL micros in the shares file; df_scaled is the estimation
# universe. Compare on the intersection.
chk <- df_scaled |> transmute(micro, year, here = epw_zA) |>
  inner_join(epw_iv |> select(micro, year, there = EPW_IV_A),
             by = c("micro", "year"))
cat(sprintf("STEP 2: EPW_IV_A rebuilt here vs 03b's saved panel — max|diff| = %.3e over %d cells\n\n",
            max(abs(chk$here - chk$there)), nrow(chk)))
stopifnot("[D0] regional instrument does not reproduce 03b" =
            max(abs(chk$here - chk$there)) < 1e-8)

# =============================================================================
# STEP 3 — FIRST-STAGE F FOR IV-A AND IV-B          [D-3a] recollection -> record
#   Two levels, because they answer different questions:
#     shock level  : does the exogenous shifter predict the realised shifter
#                    across industries?  This is the BHJ-contemplated first
#                    stage and the one D.3.4 / S2-IV would use.
#     region level : does the assembled instrument predict the assembled
#                    treatment?  This is what a 2SLS on delta_EPW would need.
#   With ONE excluded instrument the Kleibergen-Paap rk Wald F, the robust
#   first-stage Wald F and the Montiel Olea-Pflueger effective F all coincide
#   with the squared robust t on the instrument. Reported as F so that the
#   number is directly comparable to the 23.1 benchmark of [D-PRE-3].
# =============================================================================
shocks_lvl <- shocks |> filter(year %in% YEARS_EST) |> select(isic4, year, g_jt)
arc_lvl    <- shocks_arc |> filter(year %in% YEARS_EST) |> select(isic4, year, g_arc)

fs_ind_df <- shocks_lvl |>
  inner_join(arc_lvl, by = c("isic4", "year")) |>
  inner_join(z_panel |> filter(year %in% YEARS_EST), by = c("isic4", "year"))
stopifnot(nrow(fs_ind_df) == N_ISIC_EXPECTED * length(YEARS_EST))

fs_industry <- function(dv, zv) {
  m <- feols(as.formula(paste(dv, "~", zv, "| year")), data = fs_ind_df,
             weights = ~ L_j_2010, cluster = ~ isic4)
  tt <- tstat(m)[[zv]]
  tibble(level = "industry", endog = dv, instrument = zv,
         beta = coef(m)[[zv]], se = se(m)[[zv]], t = tt, F = tt^2,
         within_r2 = fitstat(m, "wr2")$wr2, n = nobs(m))
}

# Region level: same controls and fixed effects the published design uses.
dfe <- df_scaled |>
  mutate(EPW_IV_A = epw_zA, EPW_IV_B = epw_zB, EPW_IV_CHN = epw_zC,
         EPW_ARC  = epw_arc)
fs_region <- function(zv) {
  m <- feols(as.formula(paste("delta_EPW_raw ~", zv, "+",
                              paste(ctrl_base, collapse = " + "),
                              "| state^year")),
             data = dfe, cluster = ~ mesoregion_code^year)
  tt <- tstat(m)[[zv]]
  tibble(level = "region", endog = "delta_EPW (level, published)",
         instrument = zv, beta = coef(m)[[zv]], se = se(m)[[zv]], t = tt,
         F = tt^2, within_r2 = fitstat(m, "wr2")$wr2, n = nobs(m))
}

firststage <- bind_rows(
  fs_industry("g_jt",  "z_A"), fs_industry("g_jt",  "z_B"), fs_industry("g_jt",  "z_CHN"),
  fs_industry("g_arc", "z_A"), fs_industry("g_arc", "z_B"), fs_industry("g_arc", "z_CHN"),
  fs_region("EPW_IV_A"), fs_region("EPW_IV_B"), fs_region("EPW_IV_CHN"))

cat("=== D0(3) FIRST STAGE — the numbers [D-3a] never had ===\n")
print(as.data.frame(firststage), digits = 4)
cat("\n[D-PRE-3] secondary benchmark: Montiel Olea-Pflueger effective F = 23.1\n")
cat("With a single excluded instrument, F = t^2 IS the effective F.\n\n")

# =============================================================================
# STEP 4 — BHJ SHOCK BALANCE, BOTH CHARACTERISTIC SETS
#   [A-6] national employment weights, exactly as G3, G4 and 07 §6 use them.
#   g_jt and g_arc are re-run here as a canary: their F values must reproduce
#   G3_bhj_balance.csv and G4_bhj_balance_workforce.csv to the digit.
# =============================================================================
sector_chars <- readRDS("sector_chars.rds")
stopifnot("[D0] sector_chars does not span the industry universe" =
            setequal(sector_chars$isic4, colnames(W)))

s_nat <- readRDS("rais_isic_v7.rds") |>
  group_by(isic4) |> summarise(L_j = sum(workers), .groups = "drop") |>
  mutate(s_bar = L_j / sum(L_j))                                     # [A-6]

trade_chars <- shocks |> distinct(isic4, L_j_2010, exp_2010) |>
  mutate(div         = as.integer(substr(isic4, 1, 2)),
         commodity   = as.integer(div <= COMMODITY_DIV_MAX),
         log_exp2010 = log1p(exp_2010))                              # G3 form

bal_df <- fs_ind_df |>
  select(isic4, year, g_jt, g_arc, z_A, z_B, z_CHN) |>
  inner_join(sector_chars, by = "isic4") |>
  inner_join(trade_chars,  by = "isic4") |>
  inner_join(s_nat,        by = "isic4")
stopifnot(nrow(bal_df) == N_ISIC_EXPECTED * length(YEARS_EST))

balance_F <- function(dv, rhs, charset) {
  map_dfr(YEARS_EST, function(t) {
    m  <- feols(as.formula(paste(dv, "~", rhs)),
                data = filter(bal_df, year == t), weights = ~ s_bar)
    f  <- fitstat(m, "f")[[1]]
    tibble(charset = charset, shock = dv, year = t, F = f$stat,
           df1 = f$df1, df2 = f$df2, p = f$p, r2 = fixest::r2(m, "r2"),
           passes = f$p >= BAL_ALPHA)
  })
}

SHOCKS_BAL <- c("g_jt", "g_arc", "z_A", "z_B", "z_CHN")
balance <- bind_rows(
  map_dfr(SHOCKS_BAL, ~ balance_F(.x, BAL_RHS_WORKFORCE, "workforce")),
  map_dfr(SHOCKS_BAL, ~ balance_F(.x, BAL_RHS_TRADE,     "trade")))

cat("=== D0(4) BHJ SHOCK BALANCE — workforce and trade characteristics ===\n")
print(as.data.frame(balance |> arrange(charset, shock, year)), digits = 4)

# Which characteristic carries the failure? The joint F says a shock is not
# orthogonal to industry composition; it does not say on which axis. [D-0-6]
# claims the axis is the capital-intensity gradient, so the coefficients on
# mean_lnwage and sh_loweduc are the ones to read.
balance_coefs <- function(dv, rhs, charset) {
  map_dfr(YEARS_EST, function(t) {
    m <- feols(as.formula(paste(dv, "~", rhs)),
               data = filter(bal_df, year == t), weights = ~ s_bar)
    tibble(charset = charset, shock = dv, year = t, term = names(coef(m)),
           beta = as.numeric(coef(m)), se = as.numeric(se(m)),
           t = as.numeric(tstat(m))) |> filter(term != "(Intercept)")
  })
}
bal_coefs <- bind_rows(
  map_dfr(SHOCKS_BAL, ~ balance_coefs(.x, BAL_RHS_WORKFORCE, "workforce")),
  map_dfr(SHOCKS_BAL, ~ balance_coefs(.x, BAL_RHS_TRADE,     "trade")))
cat("\n=== D0(4b) balance-test coefficients (which axis fails) ===\n")
print(as.data.frame(bal_coefs |> filter(charset == "workforce") |>
                      arrange(shock, year, term)), digits = 4)

# Canary against the committed G3 / G4 tables.
g3 <- read.csv(file.path("output", "revision", "G3", "G3_bhj_balance.csv")) |>
  filter(spec == "primary_nonmechanical") |> select(shock, year, F_ref = F)
g4 <- read.csv(file.path("output", "revision", "G4",
                         "G4_bhj_balance_workforce.csv")) |> select(shock, year, F_ref = F)
canary <- bind_rows(
  balance |> filter(charset == "trade",     shock %in% c("g_jt", "g_arc")) |>
    inner_join(g3, by = c("shock", "year")),
  balance |> filter(charset == "workforce", shock %in% c("g_jt", "g_arc")) |>
    inner_join(g4, by = c("shock", "year")))
cat(sprintf("\nCANARY: max |F here - F in G3/G4| over 12 published cells = %.3e\n\n",
            max(abs(canary$F - canary$F_ref))))
stopifnot("[D0] balance machinery does not reproduce G3/G4 — not comparable" =
            max(abs(canary$F - canary$F_ref)) < 1e-8)

# =============================================================================
# STEP 5 — ROTEMBERG WEIGHTS AND THE EFFECTIVE NUMBER OF SHOCKS
#   rotemberg_for() and conc() are transcribed from revision/G3_arc_shock.R
#   lines 74-100 without alteration. They are copied rather than sourced
#   because G3_arc_shock.R is not a function library — sourcing it would re-run
#   its 9999-draw RI loop and rewrite its outputs, which the locked-tree rule
#   forbids. The transcription is verified by the benchmark check below.
# =============================================================================
rotemberg_for <- function(treat_vec, gm, ctrls) {
  d_all <- df_scaled |> mutate(.treat = treat_vec)
  map_dfr(as.character(YEARS_EST), function(t) {
    sel <- df_scaled$year == as.integer(t)
    d   <- d_all[sel, ]
    Wt  <- W[sel, , drop = FALSE]
    x_perp <- resid(lm(reformulate(c(ctrls, "factor(state)"), response = ".treat"),
                       data = d))
    num <- gm[colnames(Wt), t] * as.numeric(t(Wt) %*% x_perp)
    tibble(isic4 = colnames(Wt), year = t, alpha = num / sum(num))
  })
}
conc <- function(rot) {
  by_year <- rot |> group_by(year) |>
    summarise(hhi   = sum((abs(alpha) / sum(abs(alpha)))^2),
              eff_n = 1 / hhi,
              top3  = sum(sort(abs(alpha), decreasing = TRUE)[1:3]) / sum(abs(alpha)),
              top1  = max(abs(alpha)) / sum(abs(alpha)), .groups = "drop")
  pooled <- rot |> summarise(year = "pooled(all j,t cells)",
                             hhi   = sum((abs(alpha) / sum(abs(alpha)))^2),
                             eff_n = 1 / hhi,
                             top3  = sum(sort(abs(alpha), decreasing = TRUE)[1:3]) / sum(abs(alpha)),
                             top1  = max(abs(alpha)) / sum(abs(alpha)))
  bind_rows(by_year, pooled,
            tibble(year = "mean of yearly", hhi = NA_real_,
                   eff_n = mean(by_year$eff_n), top3 = mean(by_year$top3),
                   top1 = mean(by_year$top1)))
}

SERIES <- list(
  g_jt  = list(tv = df_scaled$delta_EPW_raw, gm = g_mat),
  g_arc = list(tv = epw_arc,                 gm = g_mat_arc),
  z_A   = list(tv = epw_zA,                  gm = g_mat_zA),
  z_B   = list(tv = epw_zB,                  gm = g_mat_zB),
  z_CHN = list(tv = epw_zC,                  gm = g_mat_zC))

rot_all <- list(); conc_all <- list(); top5_all <- list()
for (nm in names(SERIES)) {
  r <- rotemberg_for(SERIES[[nm]]$tv, SERIES[[nm]]$gm, ctrl_base)
  rot_all[[nm]]  <- r |> mutate(shock = nm, ctrls = ROT_CTRLS_NAME)
  conc_all[[nm]] <- conc(r) |> mutate(shock = nm, ctrls = ROT_CTRLS_NAME, .before = 1)
  top5_all[[nm]] <- r |> group_by(year) |> slice_max(abs(alpha), n = 5) |>
    arrange(year, desc(abs(alpha))) |> ungroup() |> mutate(shock = nm)
}
conc_all <- bind_rows(conc_all); top5_all <- bind_rows(top5_all)

cat("=== D0(5) ROTEMBERG CONCENTRATION AND EFFECTIVE SHOCK COUNT ===\n")
print(as.data.frame(conc_all |> select(shock, year, hhi, eff_n, top1, top3)), digits = 4)

eff_mean <- conc_all |> filter(year == "mean of yearly") |>
  select(shock, eff_n) |> deframe()
cat(sprintf("\nBENCHMARK CHECK  level: %.4f (G3: %.4f) | arc: %.4f (G3: %.4f)\n",
            eff_mean[["g_jt"]], BENCH_EFF_LEVEL, eff_mean[["g_arc"]], BENCH_EFF_ARC))
stopifnot("[D0] Rotemberg transcription does not reproduce G3 benchmarks" =
            abs(eff_mean[["g_jt"]]  - BENCH_EFF_LEVEL) < 1e-6 &&
            abs(eff_mean[["g_arc"]] - BENCH_EFF_ARC)   < 1e-6)

cat("\n=== D0(5b) top-5 |alpha| by shock and year ===\n")
print(as.data.frame(top5_all |> select(shock, year, isic4, alpha)), digits = 4)

# =============================================================================
# STEP 6 — SHOCK DISTRIBUTIONS AND CROSS-SHOCK CORRELATION
# =============================================================================
dist_tbl <- fs_ind_df |>
  select(isic4, year, g_jt, g_arc, z_A, z_B, z_CHN) |>
  pivot_longer(-c(isic4, year), names_to = "shock", values_to = "v") |>
  group_by(shock, year) |>
  summarise(n = n(), mean = mean(v), sd = sd(v), min = min(v),
            p25 = quantile(v, .25), median = median(v), p75 = quantile(v, .75),
            max = max(v), pct_neg = 100 * mean(v < 0), .groups = "drop")
cat("\n=== D0(6) shock distributions by year ===\n")
print(as.data.frame(dist_tbl), digits = 4)

cor_tbl <- map_dfr(c("pooled", as.character(YEARS_EST)), function(sc) {
  d <- if (sc == "pooled") fs_ind_df else filter(fs_ind_df, year == as.integer(sc))
  m <- d |> select(g_jt, g_arc, z_A, z_B, z_CHN) |> as.matrix()
  p <- cor(m); s <- cor(m, method = "spearman")
  expand_grid(a = colnames(m), b = colnames(m)) |>
    filter(a < b) |>
    mutate(scope = sc, pearson = map2_dbl(a, b, ~ p[.x, .y]),
           spearman = map2_dbl(a, b, ~ s[.x, .y]))
})
cat("\n=== D0(6b) shock-level correlations ===\n")
print(as.data.frame(cor_tbl), digits = 4)

# ---- figure: shock distributions, vector PDF --------------------------------
fig_df <- fs_ind_df |>
  select(isic4, year, g_arc, z_A, z_B, z_CHN) |>
  pivot_longer(-c(isic4, year), names_to = "shock", values_to = "v") |>
  mutate(shock = factor(shock, levels = c("g_arc", "z_A", "z_B", "z_CHN")))
p <- ggplot(fig_df, aes(x = v)) +
  geom_histogram(bins = 40) +
  facet_grid(year ~ shock, scales = "free_x") +
  labs(x = "shock value", y = "industries",
       title = "Stage-0 shock distributions, 152 ISIC industries",
       subtitle = "g_arc = realised arc; z_A/z_B/z_CHN = 03b level-per-worker demand instruments") +
  theme_minimal(base_size = 9)
# [D-6] Base grDevices::pdf, not cairo_pdf: this R has no working cairo
# (libXrender/libSM absent, no XQuartz). Both are vector devices; the base one
# has no external dependency. Do not "upgrade" this to cairo_pdf.
ggsave(file.path(OUT_D, "fig_d0_shocks.pdf"), p, width = 9, height = 5.5,
       device = grDevices::pdf)

# =============================================================================
# STEP 7 — WRITE
# =============================================================================
write_csv(firststage, file.path(OUT_D, "D0_firststage.csv"))
write_csv(balance,    file.path(OUT_D, "D0_balance.csv"))
write_csv(bal_coefs,  file.path(OUT_D, "D0_balance_coefficients.csv"))
write_csv(conc_all,   file.path(OUT_D, "D0_rotemberg.csv"))
write_csv(top5_all,   file.path(OUT_D, "D0_rotemberg_top5.csv"))
write_csv(bind_rows(rot_all), file.path(OUT_D, "D0_rotemberg_weights_full.csv"))
write_csv(dist_tbl,   file.path(OUT_D, "D0_shock_distributions.csv"))
write_csv(cor_tbl,    file.path(OUT_D, "D0_shock_correlations.csv"))

md <- function(df, digits = 4) {
  d <- df |> mutate(across(where(is.numeric), ~ signif(.x, digits)))
  hdr <- paste0("| ", paste(names(d), collapse = " | "), " |")
  sep <- paste0("| ", paste(rep("---", ncol(d)), collapse = " | "), " |")
  rows <- apply(d, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  paste(c(hdr, sep, rows), collapse = "\n")
}
writeLines(c(
  "# Packet D — Stage 0 diagnostics",
  "",
  paste0("Generated ", format(Sys.time()), " by `códigos/packet_D/D0_iv_diagnostics.R`."),
  "Instruments read from `sectoral_demand_iv_v1.rds`, written by an unmodified",
  "re-run of `03b_instrument_construction.R`. No outcome regression was run.",
  "",
  "## 1. First stage (`[D-3a]`: recollection -> record)",
  "",
  md(firststage), "",
  "Single excluded instrument, so F = t^2 is simultaneously the robust",
  "first-stage Wald F, the Kleibergen-Paap rk Wald F and the Montiel Olea-Pflueger",
  "effective F. `[D-PRE-3]` quotes 23.1 as the reader's benchmark.",
  "",
  "## 2. BHJ shock balance, national employment weights `[A-6]`",
  "",
  md(balance |> arrange(charset, shock, year)), "",
  paste0("`passes` = fail to reject at ", BAL_ALPHA, ". `g_jt` and `g_arc` reproduce ",
         "`G3_bhj_balance.csv` and `G4_bhj_balance_workforce.csv` exactly."),
  "",
  "### 2b. Workforce-balance coefficients — which axis fails",
  "",
  md(bal_coefs |> filter(charset == "workforce") |> arrange(shock, year, term)), "",
  "## 3. Rotemberg concentration and effective shock count",
  "",
  md(conc_all |> select(shock, ctrls, year, hhi, eff_n, top1, top3)), "",
  paste0("Benchmarks reproduced: level ", signif(BENCH_EFF_LEVEL, 4),
         ", arc ", signif(BENCH_EFF_ARC, 4), " (mean of yearly, base controls)."),
  "",
  "## 4. Top-5 Rotemberg weights",
  "",
  md(top5_all |> select(shock, year, isic4, alpha)), "",
  "## 5. Shock distributions",
  "",
  md(dist_tbl), "",
  "## 6. Shock-level correlations",
  "",
  md(cor_tbl), ""
), file.path(OUT_D, "tab_d0_stage0.md"))

cat("\n[D0] wrote", OUT_D, "\n")
sink(); close(log_con)
