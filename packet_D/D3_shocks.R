# =============================================================================
# D3_shocks.R  —  Packet D, Phase 1, STAGE 1, step 3
# -----------------------------------------------------------------------------
# Branch A:  g_dt  destination-unit shock, arc-%, Brazil excluded
# Branch B:  Z_jt  industry-unit shock, arc-%, DESTINATION-WEIGHTED
#
# [A1] SHOCK DISPERSION IS THE FIRST OUTPUT, BEFORE ANY ROTEMBERG WEIGHT.
# The exposure-diversity argument for Branch A was withdrawn: per microregion,
# destinations carry 6.45 effective units against industries' 7.89, so Branch A
# is if anything slightly MORE concentrated in exposure. What survives is that
# the industry design collapses from 7.89 effective industries of exposure to
# 2.59 effective SHOCKS, and that collapse is shock-side dispersion produced by
# the L_j,2010 denominator (ISIC 0129: g = 88.9 on 3,672 workers). An arc rate is
# bounded in [-2, +2], so that dispersion is arithmetically impossible.
# The entire case for Branch A now rests on this section.
#
# NEITHER SHOCK DIVIDES BY L_j,2010. If a construction here does, it has rebuilt
# IV-A ([D-3b]). Branch A has no industry dimension at all.
#
# No outcome regression. No polarization series is loaded.
#
# Run:  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 Rscript códigos/packet_D/D3_shocks.R
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(data.table)
})
set.seed(2026)

# ---- NAMED CONSTANTS --------------------------------------------------------
OUT_D           <- file.path("output", "packet_D")
BASE_YEAR       <- 2010L
ELECTION_YEARS  <- c(2014L, 2018L, 2022L)
N_ISIC_EXPECTED <- 152L
ARC_BOUND       <- 2
ARC_TOL         <- 1e-9
BIG_SHOCK_CUT   <- 1.0        # |g| > this is reported unit-by-unit
TOP_N_UNITS     <- 20         # units labelled in tables and figures
ENTREPOT_ISO3   <- c("NLD", "SGP", "HKG", "ARE", "LCA")   # [D-25]

# [D-32] SHOCK BASELINE: the spec and the existing ladder disagree, so both are
# built and the disagreement is made visible rather than resolved silently.
#   D_data_contracts §3.2 and §4.4 write arcD( m[t] , m[t-4] ) — a ROLLING
#     four-year window, so 2018 is measured against 2014.
#   The published rungs do not do that. sectoral_shocks_isic_v7.rds defines
#     g_jt = (EXP_jt - EXP_j,2010) / L_j,2010, and G3's arc shock divides by
#     0.5*(exp_national + exp_2010) — both CUMULATIVE against 2010. RATIONALE_D
#     [D-4] says so outright: "shocks are cumulative against 2010".
# Comparability against S0/S1 is the whole point of the ladder, so the 2010
# baseline is PRIMARY. The rolling variant is computed and reported so that the
# contract's reading is on the record and its consequences are visible.
SHOCK_BASELINE  <- "2010"     # "2010" (primary, ladder-comparable) | "rolling"
stopifnot(SHOCK_BASELINE %in% c("2010", "rolling"))

# ---- output guard -----------------------------------------------------------
dir.create(OUT_D, showWarnings = FALSE, recursive = TRUE)
D3_OUT <- c("D3_g_dt.rds", "D3_Z_jt.rds", "D3_dispersion.csv",
            "D3_big_shocks.csv", "D3_shock_units_top.csv",
            "tab_d3_shocks.md", "fig_d3_shock_distributions.pdf")
existing <- D3_OUT[file.exists(file.path(OUT_D, D3_OUT))]
if (length(existing))
  stop("[D3] refusing to overwrite existing packet_D output:\n  ",
       paste(existing, collapse = "\n  "))

log_con <- file(file.path(OUT_D, "D3_run_log.txt"), open = "wt")
sink(log_con, split = TRUE)
cat("=== D3 shocks:", format(Sys.time()), "===\n")
cat("SHOCK_BASELINE =", SHOCK_BASELINE, "(primary) | arc bound +/-", ARC_BOUND, "\n\n")

write_csv_safe <- function(x, f) { if (file.exists(f)) unlink(f); readr::write_csv(x, f) }

# The arc / midpoint growth rate. Bounded in [-2,2]; entry = +2, exit = -2;
# 0/0 := 0 for a unit with no trade at either endpoint (G3 convention).
arc <- function(v_t, v_0) {
  den <- 0.5 * (v_t + v_0)
  if_else(den > 0, (v_t - v_0) / den, 0)
}

# =============================================================================
# STEP 1 — INPUTS
# =============================================================================
need <- c("D1_s_rd.rds", "D2_m_dp_row.rds", "D2_omega_pd.rds", "D2_omega_jd.rds")
stopifnot("[D3] D1/D2 outputs absent — run them first" =
            all(file.exists(file.path(OUT_D, need))))

d1        <- readRDS(file.path(OUT_D, "D1_s_rd.rds"))
m_dp_row  <- readRDS(file.path(OUT_D, "D2_m_dp_row.rds"))
omega_pd  <- readRDS(file.path(OUT_D, "D2_omega_pd.rds"))
omega_jd  <- readRDS(file.path(OUT_D, "D2_omega_jd.rds"))
baci_countries <- d1$baci_countries

# Asserted again immediately before use, as the contract requires: a Brazil leak
# anywhere downstream silently destroys the exogeneity claim.
stopifnot("[D3] BRAZIL PRESENT IN m_dp_row — exogeneity claim void" =
            !any(m_dp_row$destino == 76L))

ncm_isic_v7   <- readRDS("ncm_isic_match_v7.rds")
composite_map <- readRDS("composite_map_v7.rds")
universe      <- sort(unique(readRDS("sectoral_shocks_isic_v7.rds")$isic4))

shocks_v7  <- readRDS("sectoral_shocks_isic_v7.rds")
arc_path   <- file.path("output", "revision", "G3", "G3_shocks_arc.csv")
shocks_arc <- read.csv(arc_path, colClasses = c(isic4 = "character")) |> as_tibble()

cat("STEP 1: m_dp_row", format(nrow(m_dp_row), big.mark = ","), "cells |",
    n_distinct(m_dp_row$destino), "destinations |",
    n_distinct(m_dp_row$hs6), "products\n\n")

# =============================================================================
# STEP 2 — BRANCH A:  g_dt = sum_p omega_pd,2010 * arc( m_dpt , m_dp,base )
#   The product grid is completed with ZEROS within each destination's 2010
#   basket: a product absent from BACI in year t is zero demand, not missing
#   ([B-1] applied to the destination panel). Only products Brazil actually sold
#   to d in 2010 carry weight, so the grid is omega_pd's support.
# =============================================================================
grid <- omega_pd |> select(destino, hs6, omega_pd) |>
  crossing(ano = c(BASE_YEAR, ELECTION_YEARS)) |>
  left_join(m_dp_row, by = c("destino", "hs6", "ano")) |>
  mutate(m = replace_na(m, 0))

m_wide <- grid |>
  pivot_wider(names_from = ano, values_from = m, names_prefix = "m_",
              values_fill = 0)

base_col <- function(t) if (SHOCK_BASELINE == "2010") "m_2010" else
  paste0("m_", t - 4L)

g_dt <- map_dfr(ELECTION_YEARS, function(t) {
  m_wide |>
    transmute(destino, hs6, omega_pd, ano = t,
              m_t = .data[[paste0("m_", t)]],
              m_b = .data[[base_col(t)]]) |>
    mutate(a = arc(m_t, m_b)) |>
    group_by(destino, ano) |>
    summarise(g_dt = sum(omega_pd * a), .groups = "drop")
})

# Robustness variant (spec §D.4.2): unweighted total imports of d.
g_dt_tot <- map_dfr(ELECTION_YEARS, function(t) {
  m_dp_row |> group_by(destino, ano) |> summarise(M = sum(m), .groups = "drop") |>
    pivot_wider(names_from = ano, values_from = M, names_prefix = "M_",
                values_fill = 0) |>
    transmute(destino, ano = t,
              g_dt_tot = arc(.data[[paste0("M_", t)]],
                             .data[[sub("^m_", "M_", base_col(t))]]))
})

# The contract's rolling reading, for the record ([D-32]).
g_dt_roll <- map_dfr(ELECTION_YEARS, function(t) {
  m_wide |>
    transmute(destino, omega_pd, ano = t,
              a = arc(.data[[paste0("m_", t)]], .data[[paste0("m_", t - 4L)]])) |>
    group_by(destino, ano) |>
    summarise(g_dt_rolling = sum(omega_pd * a), .groups = "drop")
})

g_dt <- g_dt |>
  left_join(g_dt_tot,  by = c("destino", "ano")) |>
  left_join(g_dt_roll, by = c("destino", "ano")) |>
  left_join(baci_countries |> select(destino, iso3 = baci_iso3), by = "destino")

stopifnot(
  "[D3] g_dt outside the arc bound" =
    all(g_dt$g_dt >= -ARC_BOUND - ARC_TOL) && all(g_dt$g_dt <= ARC_BOUND + ARC_TOL),
  "[D3] g_dt_tot outside the arc bound" =
    all(abs(g_dt$g_dt_tot) <= ARC_BOUND + ARC_TOL),
  "[D3] g_dt carries NA" = !anyNA(g_dt$g_dt),
  "[D3] destination label lost" = !anyNA(g_dt$iso3))

cat("STEP 2: g_dt built —", n_distinct(g_dt$destino), "destinations x",
    length(ELECTION_YEARS), "cycles\n\n")

# =============================================================================
# STEP 3 — BRANCH B:  Z_jt = sum_d omega_jd,2010 * arc( m_djt , m_dj,base )
#   Proportional and destination-weighted. NOT divided by L_j,2010 — that is
#   what separates it from IV-A/IV-B ([D-3b]).
# =============================================================================
m_dj_row <- m_dp_row |>
  inner_join(ncm_isic_v7, by = c("hs6" = "ncm6"), relationship = "many-to-many") |>
  mutate(val = m * w_ncm) |>
  left_join(composite_map |> select(isic4, isic_composite), by = "isic4") |>
  mutate(isic4 = coalesce(isic_composite, isic4)) |>
  filter(isic4 %in% universe) |>
  group_by(destino, isic4, ano) |>
  summarise(m = sum(val), .groups = "drop")

mj_wide <- omega_jd |> select(isic4, destino, omega_jd) |>
  crossing(ano = c(BASE_YEAR, ELECTION_YEARS)) |>
  left_join(m_dj_row, by = c("destino", "isic4", "ano")) |>
  mutate(m = replace_na(m, 0)) |>
  pivot_wider(names_from = ano, values_from = m, names_prefix = "m_",
              values_fill = 0)

Z_jt <- map_dfr(ELECTION_YEARS, function(t) {
  mj_wide |>
    transmute(isic4, destino, omega_jd, ano = t,
              a = arc(.data[[paste0("m_", t)]], .data[[base_col(t)]])) |>
    group_by(isic4, ano) |>
    summarise(Z_jt = sum(omega_jd * a), .groups = "drop")
})

stopifnot(
  "[D3] Z_jt outside the arc bound" =
    all(Z_jt$Z_jt >= -ARC_BOUND - ARC_TOL) && all(Z_jt$Z_jt <= ARC_BOUND + ARC_TOL),
  "[D3] Z_jt industry set != v7 universe" =
    n_distinct(Z_jt$isic4) == N_ISIC_EXPECTED,
  "[D3] Z_jt carries NA" = !anyNA(Z_jt$Z_jt))
cat("STEP 3: Z_jt built —", n_distinct(Z_jt$isic4), "industries x",
    length(ELECTION_YEARS), "cycles\n\n")

# =============================================================================
# STEP 4 — [A1] SHOCK DISPERSION. THE HEADLINE, BEFORE ANY ROTEMBERG WEIGHT.
# =============================================================================
disp_of <- function(v, label, unit, ano) {
  tibble(shock = label, unit = unit, ano = ano, n = length(v),
         mean = mean(v), sd = sd(v), min = min(v), p25 = quantile(v, .25),
         median = median(v), p75 = quantile(v, .75), max = max(v),
         iqr = IQR(v), range = max(v) - min(v),
         # dimensionless tail measures — the only cross-scale comparison that
         # means anything, since g_jt is USD-per-worker and the arc rates are not
         max_abs_over_sd = max(abs(v)) / sd(v),
         eff_units_by_magnitude = sum(abs(v))^2 / sum(v^2),
         pct_neg = 100 * mean(v < 0))
}

lvl <- shocks_v7 |> filter(ano_ok <- year %in% ELECTION_YEARS) |>
  select(isic4, year, g_jt)
arcs <- shocks_arc |> filter(year %in% ELECTION_YEARS) |> select(isic4, year, g_arc)

dispersion <- bind_rows(
  map_dfr(ELECTION_YEARS, ~ disp_of(filter(lvl,  year == .x)$g_jt,
                                    "g_jt (S0, level per worker)", "industry", .x)),
  map_dfr(ELECTION_YEARS, ~ disp_of(filter(arcs, year == .x)$g_arc,
                                    "g_arc (S1, arc %)", "industry", .x)),
  map_dfr(ELECTION_YEARS, ~ disp_of(filter(Z_jt, ano == .x)$Z_jt,
                                    "Z_jt (S2, arc %, dest-weighted)", "industry", .x)),
  map_dfr(ELECTION_YEARS, ~ disp_of(filter(g_dt, ano == .x)$g_dt,
                                    "g_dt (S3, arc %, destination)", "destination", .x)),
  map_dfr(ELECTION_YEARS, ~ disp_of(filter(g_dt, ano == .x)$g_dt_tot,
                                    "g_dt_tot (S3 robustness)", "destination", .x)))

cat("=== D3(4) [A1] SHOCK DISPERSION — the case for Branch A rests here ===\n")
print(as.data.frame(dispersion |>
  select(shock, ano, n, sd, min, median, max, iqr, max_abs_over_sd,
         eff_units_by_magnitude)), digits = 4)

cat("\n--- read: sd is in each shock's own units and is NOT comparable across\n")
cat("    rows; max_abs_over_sd and eff_units_by_magnitude are dimensionless and\n")
cat("    ARE. eff_units_by_magnitude = (sum|g|)^2 / sum(g^2) is the effective\n")
cat("    number of units by shock magnitude alone, before any exposure weight —\n")
cat("    a preview of Rotemberg concentration that does not depend on W.\n")

cat("\n--- summary across cycles ---\n")
print(as.data.frame(dispersion |> group_by(shock, unit) |>
  summarise(n = first(n), mean_sd = mean(sd),
            min_all = min(min), max_all = max(max),
            mean_max_abs_over_sd = mean(max_abs_over_sd),
            mean_eff_units = mean(eff_units_by_magnitude), .groups = "drop")),
  digits = 4)

# ---- units carrying |shock| > BIG_SHOCK_CUT ---------------------------------
big <- bind_rows(
  g_dt |> filter(abs(g_dt) > BIG_SHOCK_CUT) |>
    transmute(shock = "g_dt", unit = iso3, ano, value = g_dt),
  Z_jt |> filter(abs(Z_jt) > BIG_SHOCK_CUT) |>
    transmute(shock = "Z_jt", unit = isic4, ano, value = Z_jt)) |>
  arrange(shock, ano, desc(abs(value)))

cat(sprintf("\n--- units with |shock| > %.1f ---\n", BIG_SHOCK_CUT))
cat(sprintf("g_dt: %d of %d destination-cycles | Z_jt: %d of %d industry-cycles\n",
            sum(big$shock == "g_dt"), nrow(g_dt),
            sum(big$shock == "Z_jt"), nrow(Z_jt)))
if (nrow(big)) print(as.data.frame(big |> slice_head(n = 30)), digits = 4)

# Are the extreme destinations economically trivial? Weight by Brazil's 2010
# export value to d — a +/-2 on a destination Brazil barely sells to is noise.
d_val <- d1$s_rd |> group_by(destino) |> summarise(x_d = sum(x_rd), .groups = "drop") |>
  mutate(share = x_d / sum(x_d))
big_val <- big |> filter(shock == "g_dt") |>
  left_join(baci_countries |> select(destino, iso3 = baci_iso3), by = c("unit" = "iso3")) |>
  left_join(d_val, by = "destino")
cat(sprintf("\nDestinations with |g_dt| > %.1f carry %.4f%% of Brazil's 2010 exports (mean over cycles)\n",
            BIG_SHOCK_CUT,
            100 * sum(big_val$share, na.rm = TRUE) / length(ELECTION_YEARS)))

write_csv_safe(dispersion, file.path(OUT_D, "D3_dispersion.csv"))
write_csv_safe(big,        file.path(OUT_D, "D3_big_shocks.csv"))

# =============================================================================
# STEP 5 — TOP AND BOTTOM UNITS
# =============================================================================
top_units <- bind_rows(
  map_dfr(ELECTION_YEARS, function(t) {
    d <- g_dt |> filter(ano == t) |> left_join(d_val, by = "destino")
    bind_rows(slice_max(d, g_dt, n = TOP_N_UNITS, with_ties = FALSE) |>
                mutate(end = "top"),
              slice_min(d, g_dt, n = TOP_N_UNITS, with_ties = FALSE) |>
                mutate(end = "bottom")) |>
      transmute(shock = "g_dt", ano, end, unit = iso3, value = g_dt,
                exp_share_2010 = share)
  }),
  map_dfr(ELECTION_YEARS, function(t) {
    d <- Z_jt |> filter(ano == t)
    bind_rows(slice_max(d, Z_jt, n = TOP_N_UNITS, with_ties = FALSE) |>
                mutate(end = "top"),
              slice_min(d, Z_jt, n = TOP_N_UNITS, with_ties = FALSE) |>
                mutate(end = "bottom")) |>
      transmute(shock = "Z_jt", ano, end, unit = isic4, value = Z_jt,
                exp_share_2010 = NA_real_)
  }))
write_csv_safe(top_units, file.path(OUT_D, "D3_shock_units_top.csv"))

cat(sprintf("\n=== D3(5) TOP/BOTTOM %d DESTINATIONS BY g_dt ===\n", TOP_N_UNITS))
print(as.data.frame(top_units |> filter(shock == "g_dt") |>
  group_by(ano, end) |> slice_head(n = 8) |> ungroup()), digits = 4)

# Entrepot check ([D-25]): are the transhipment hubs carrying extreme shocks?
cat("\n--- entrepot destinations, g_dt by cycle ---\n")
print(as.data.frame(g_dt |> filter(iso3 %in% ENTREPOT_ISO3) |>
  select(iso3, ano, g_dt, g_dt_tot) |>
  pivot_wider(names_from = ano, values_from = c(g_dt, g_dt_tot))), digits = 4)

# =============================================================================
# STEP 6 — [D-32] BASELINE SENSITIVITY: 2010 vs rolling
# =============================================================================
base_cmp <- g_dt |> group_by(ano) |>
  summarise(pearson = cor(g_dt, g_dt_rolling),
            spearman = cor(g_dt, g_dt_rolling, method = "spearman"),
            sd_2010 = sd(g_dt), sd_rolling = sd(g_dt_rolling), .groups = "drop")
cat("\n=== D3(6) [D-32] baseline sensitivity: cumulative-2010 vs rolling t-4 ===\n")
print(as.data.frame(base_cmp), digits = 4)
cat("2014 is identical by construction (t-4 = 2010); 2018 and 2022 are not.\n")

# =============================================================================
# STEP 7 — FIGURE
# =============================================================================
fig <- bind_rows(
  g_dt |> transmute(ano, shock = "g_dt (destination)", v = g_dt),
  Z_jt |> transmute(ano, shock = "Z_jt (industry, dest-weighted)", v = Z_jt),
  arcs |> transmute(ano = year, shock = "g_arc (industry, realised)", v = g_arc))
p <- ggplot(fig, aes(x = v)) +
  geom_histogram(bins = 45) +
  facet_grid(ano ~ shock, scales = "free_y") +
  geom_vline(xintercept = 0, linewidth = 0.3) +
  labs(x = "shock value (arc rate, bounded [-2, 2])", y = "units",
       title = "Packet D: arc-rate shock distributions",
       subtitle = "Branch A destination unit vs Branch B industry unit vs the realised arc shock") +
  theme_minimal(base_size = 9)
ggsave(file.path(OUT_D, "fig_d3_shock_distributions.pdf"), p,
       width = 9, height = 5.5, device = grDevices::pdf)

# =============================================================================
# STEP 8 — WRITE
# =============================================================================
saveRDS(g_dt, file.path(OUT_D, "D3_g_dt.rds"))
saveRDS(Z_jt, file.path(OUT_D, "D3_Z_jt.rds"))

md <- function(df, digits = 4) {
  d <- df |> mutate(across(where(is.double), ~ signif(.x, digits))) |>
    mutate(across(everything(), as.character))
  rows <- do.call(paste, c(unname(as.list(d)), sep = " | "))
  paste(c(paste0("| ", paste(names(d), collapse = " | "), " |"),
          paste0("| ", paste(rep("---", ncol(d)), collapse = " | "), " |"),
          paste0("| ", rows, " |")), collapse = "\n")
}
writeLines(c(
  "# Packet D — Stage 1, step 3: shocks",
  "",
  paste0("Generated ", format(Sys.time()), " by `códigos/packet_D/D3_shocks.R`."),
  paste0("Primary baseline: **", SHOCK_BASELINE,
         "** (cumulative, ladder-comparable — `[D-32]`). No outcome regression."),
  "",
  "## 1. `[A1]` Shock dispersion — before any Rotemberg weight",
  "",
  md(dispersion |> select(shock, ano, n, sd, min, median, max, iqr,
                          max_abs_over_sd, eff_units_by_magnitude)),
  "",
  paste0("`sd` is in each shock's own units and is **not** comparable across ",
         "rows — `g_jt` is USD per worker, the arc rates are dimensionless. ",
         "`max_abs_over_sd` and `eff_units_by_magnitude` are dimensionless and ",
         "are. `eff_units_by_magnitude = (sum|g|)^2 / sum(g^2)` is the effective ",
         "number of units by shock magnitude alone, before any exposure weight."),
  "",
  "### Across cycles",
  "",
  md(dispersion |> group_by(shock, unit) |>
       summarise(n = first(n), mean_sd = mean(sd), min_all = min(min),
                 max_all = max(max),
                 mean_max_abs_over_sd = mean(max_abs_over_sd),
                 mean_eff_units = mean(eff_units_by_magnitude), .groups = "drop")),
  "",
  paste0("## 2. Units with |shock| > ", BIG_SHOCK_CUT),
  "",
  paste0("`g_dt`: ", sum(big$shock == "g_dt"), " of ", nrow(g_dt),
         " destination-cycles. `Z_jt`: ", sum(big$shock == "Z_jt"), " of ",
         nrow(Z_jt), " industry-cycles."),
  "",
  if (nrow(big)) md(big |> slice_head(n = 25)) else "_none_",
  "",
  "## 3. `[D-32]` Baseline sensitivity: cumulative-2010 vs rolling t-4",
  "",
  md(base_cmp),
  "",
  "2014 is identical by construction; 2018 and 2022 are not.",
  ""
), file.path(OUT_D, "tab_d3_shocks.md"))

cat("\n[D3] wrote", OUT_D, "\n")
sink(); close(log_con)
