# =============================================================================
# D2_baci_destino.R  —  Packet D, Phase 1, STAGE 1, step 2
# -----------------------------------------------------------------------------
# BACI re-ingest CARRYING THE DESTINATION DIMENSION.
#
# 03b aggregates j away — it collapses to product x year — so the destination
# panel cannot be recovered from sectoral_demand_iv_v1.rds and is rebuilt here
# from the raw files.
#
# Builds:
#   m_dp_row   destination x HS6 x year, BRAZIL EXCLUDED as exporter
#   omega_pd   Brazil's 2010 export basket to d, by HS6      [Branch A weights]
#   omega_jd   Brazil's 2010 destination mix by ISIC industry [Branch B weights]
#   s_rd_bridge + the rho gate                               [D_data_contracts 4.3]
#
# The bridge is here rather than in D1 ([D-16]): it needs omega_jd, which does
# not exist until this script runs. D1 is kept BACI-free, which is what makes it
# the cheap step-1 gate.
#
# DESTINATION HARMONISATION IS NOT REDECLARED. The area map and the persistent
# fold are read out of D1_s_rd.rds so Comex and BACI cannot drift onto different
# destination universes ([D-20], [D-23]).
#
# No shocks are built here and no outcome regression is run. Shocks are D3.
#
# Run:  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 Rscript códigos/packet_D/D2_baci_destino.R
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(data.table)
})
set.seed(2026)

# ---- NAMED CONSTANTS --------------------------------------------------------
OUT_D            <- file.path("output", "packet_D")
BASE_YEAR        <- 2010L
PANEL_YEARS      <- c(2010L, 2014L, 2018L, 2022L)
BRA_ISO          <- 76L        # BACI code for Brazil
BACI_DIR         <- "baci"
USD_UNIT         <- 1e4        # tens of thousands of constant-2010 USD, as 03/03b
HS6_WIDTH        <- 6L
N_ISIC_EXPECTED  <- 152L
N_MICRO_EXPECTED <- 557L

# World-total reconciliation tolerance (D_data_contracts §1)
WORLD_TOTAL_TOL  <- 0.01

# Bridge gate (D_data_contracts §4.3): stop if the employment-imputed shares and
# the Comex shares disagree this badly — it would mean the municipality
# attribution problem is severe enough to change the design.
BRIDGE_RHO_MIN   <- 0.50

# ---- output guard -----------------------------------------------------------
dir.create(OUT_D, showWarnings = FALSE, recursive = TRUE)
D2_OUT <- c("D2_m_dp_row.rds", "D2_omega_pd.rds", "D2_omega_jd.rds",
            "D2_baci_totals.csv", "D2_bridge.csv", "tab_d_bridge.md",
            "D2_orphan_hs6.csv")
existing <- D2_OUT[file.exists(file.path(OUT_D, D2_OUT))]
if (length(existing))
  stop("[D2] refusing to overwrite existing packet_D output:\n  ",
       paste(existing, collapse = "\n  "))

log_con <- file(file.path(OUT_D, "D2_run_log.txt"), open = "wt")
sink(log_con, split = TRUE)
cat("=== D2 BACI destination ingest:", format(Sys.time()), "===\n\n")

write_csv_safe <- function(x, f) { if (file.exists(f)) unlink(f); readr::write_csv(x, f) }

# =============================================================================
# STEP 1 — D1 HARMONISATION MAPS AND v7 OBJECTS
# =============================================================================
stopifnot("[D2] D1_s_rd.rds absent — run D1 first" =
            file.exists(file.path(OUT_D, "D1_s_rd.rds")))
d1 <- readRDS(file.path(OUT_D, "D1_s_rd.rds"))

PANEL_PERSISTENT_FOLD <- d1$panel_persistent_fold          # [D-23]
baci_countries        <- d1$baci_countries
# Named s_rd_comex, NOT s_rd_n1: a data frame carrying a column of its own name
# gets shadowed by the data mask inside filter()/mutate(), and the failure is a
# confusing "$ operator is invalid for atomic vectors" rather than a name error.
s_rd_comex <- d1$s_rd |> select(micro, destino, s_rd_n1, x_rd, x_r)
micro_n1   <- sort(unique(s_rd_comex$micro))

fold_destino <- function(d) {
  k <- as.character(d)
  hit <- k %in% names(PANEL_PERSISTENT_FOLD)
  if_else(hit, PANEL_PERSISTENT_FOLD[k], as.integer(d))
}

shares_v7 <- readRDS("exposure_shares_isic_v7.rds") |> select(micro, isic4, s_rj)
stopifnot("[D2] v7 share universe changed" =
            n_distinct(shares_v7$micro) == N_MICRO_EXPECTED,
          n_distinct(shares_v7$isic4) == N_ISIC_EXPECTED)

# Crosswalk: LOADED, never rebuilt. Same objects 03b STEP 1 reads.
# cnae_isic_crosswalk 2.rds is DEFECTIVE and is never touched ([D-0-2]).
stopifnot("[D2] persisted v7 crosswalk absent" =
            file.exists("ncm_isic_match_v7.rds") && file.exists("composite_map_v7.rds"))
ncm_isic_v7   <- readRDS("ncm_isic_match_v7.rds")
composite_map <- readRDS("composite_map_v7.rds")
stopifnot("[D2] crosswalk weights do not sum to 1 within product" =
            all(abs(ncm_isic_v7 |> group_by(ncm6) |> summarise(s = sum(w_ncm)) |>
                      pull(s) - 1) < 1e-9))
dict_codes <- unique(ncm_isic_v7$ncm6)

universe <- sort(unique(readRDS("sectoral_shocks_isic_v7.rds")$isic4))
stopifnot(length(universe) == N_ISIC_EXPECTED)

cpi      <- readRDS("cpi_us.rds")
cpi_2010 <- filter(cpi, year == BASE_YEAR) |> pull(cpi)
cat("STEP 1: maps loaded | fold entries:", length(PANEL_PERSISTENT_FOLD),
    "| dictionary HS6:", length(dict_codes), "\n\n")

# =============================================================================
# STEP 2 — INGEST, CARRYING j
#   One pass per file, two aggregates kept:
#     m_dp_row : destination x product, Brazil excluded as exporter
#     x_bra_dp : Brazil's own exports by destination x product (weights)
#   Brazil is excluded as importer as well: Brazil is never a destination of its
#   own exports, so a j == 76 row cannot belong in a destination panel.
# =============================================================================
baci_file <- function(y) {
  hits <- list.files(BACI_DIR, pattern = paste0("^BACI_HS07_Y", y, "_V.*\\.csv$"),
                     full.names = TRUE)
  stopifnot("[D2] BACI year file missing" = length(hits) >= 1)
  sort(hits)[length(hits)]
}

read_year <- function(y) {
  f <- baci_file(y)
  cat("Reading", f, "...\n")
  dt <- fread(f, select = c("t", "i", "j", "k", "v"),
              colClasses = list(character = "k"))
  # [D-4] zero-pad BEFORE any join. BACI strips leading zeros, so without this
  # every product in HS chapters 01-09 silently fails to match the crosswalk.
  dt[, k := str_pad(str_trim(k), HS6_WIDTH, pad = "0")]
  stopifnot("[D2] HS6 not width 6 after padding" = all(nchar(dt$k) == HS6_WIDTH))

  m <- dt[i != BRA_ISO & j != BRA_ISO,
          .(m = sum(as.numeric(v))), by = .(ano = t, destino = j, hs6 = k)]
  x <- dt[i == BRA_ISO & j != BRA_ISO,
          .(x = sum(as.numeric(v))), by = .(ano = t, destino = j, hs6 = k)]
  wt <- dt[, .(world = sum(as.numeric(v)))][["world"]]
  rm(dt); gc()
  list(m = m, x = x, world = wt)
}

# [D-29] Ingest cache. Re-reading 1.3 GB of BACI to re-run a downstream
# diagnostic is the difference between a 30-second iteration and a 4-minute one,
# and the brief requires each script to be independently runnable and idempotent.
# The cache holds ONLY the two raw aggregates, before deflation, folding or any
# modelling choice, so nothing downstream can be silently frozen into it. Delete
# it to force a re-read.
INGEST_CACHE <- file.path(OUT_D, "D2_ingest_cache.rds")
if (file.exists(INGEST_CACHE)) {
  cat("STEP 2: reading cached raw ingest —", INGEST_CACHE, "\n")
  cached    <- readRDS(INGEST_CACHE)
  m_raw     <- cached$m_raw
  x_raw     <- cached$x_raw
  world_tot <- cached$world_tot
  stopifnot("[D2] cache does not cover the panel years" =
              setequal(unique(m_raw$ano), PANEL_YEARS))
  rm(cached); gc()
} else {
  ing <- map(PANEL_YEARS, read_year)
  m_raw <- rbindlist(map(ing, "m"))
  x_raw <- rbindlist(map(ing, "x"))
  world_tot <- tibble(ano = PANEL_YEARS, world_kusd = map_dbl(ing, "world"))
  rm(ing); gc()
  saveRDS(list(m_raw = m_raw, x_raw = x_raw, world_tot = world_tot), INGEST_CACHE)
}

cat("\nSTEP 2: m_dp_row raw", format(nrow(m_raw), big.mark = ","), "rows |",
    "x_bra_dp raw", format(nrow(x_raw), big.mark = ","), "rows\n")

# ---- THE assertion. A Brazil leak here silently destroys the exogeneity claim.
stopifnot("[D2] BRAZIL PRESENT IN m_dp_row — exogeneity claim void" =
            !any(m_raw$destino == BRA_ISO))

# =============================================================================
# STEP 3 — DEFLATE, THEN FOLD DESTINATIONS
#   Deflation is NOT optional and NOT neutral: an arc rate between two years is
#   not invariant to a year-specific price level, so a nominal numerator over a
#   deflated denominator breaks the rate silently (packet_D_spec §D.2).
# =============================================================================
deflate <- function(dt, col) {
  dt |> as_tibble() |>
    left_join(cpi, by = c("ano" = "year")) |>
    mutate(!!col := .data[[col]] * 1000 * (cpi_2010 / cpi) / USD_UNIT) |>
    select(-cpi)
}
m_dp_row <- deflate(m_raw, "m") |>
  mutate(destino = fold_destino(destino)) |>                      # [D-23]
  group_by(ano, destino, hs6) |>
  summarise(m = sum(m), .groups = "drop")

x_bra_dp <- deflate(x_raw, "x") |>
  mutate(destino = fold_destino(destino)) |>
  group_by(ano, destino, hs6) |>
  summarise(x = sum(x), .groups = "drop")

rm(m_raw, x_raw); gc()

stopifnot("[D2] Brazil reappeared after folding" = !any(m_dp_row$destino == BRA_ISO),
          "[D2] negative import value" = all(m_dp_row$m >= 0),
          "[D2] year set wrong" = setequal(unique(m_dp_row$ano), PANEL_YEARS))

# ---- world-total reconciliation (D_data_contracts §1) -----------------------
recon <- m_dp_row |> group_by(ano) |> summarise(m_T = sum(m) * USD_UNIT / 1e12) |>
  left_join(world_tot |> mutate(world_T = world_kusd * 1000 / 1e12), by = "ano") |>
  mutate(excl_bra_share = m_T / world_T)
cat("\n--- world totals, constant 2010 USD (m) vs current USD (world) ---\n")
print(as.data.frame(recon), digits = 4)
cat("(m excludes Brazil on both sides and is deflated, so the ratio is expected\n",
    " below 1 and falling with the price level, not equal to 1.)\n")

# The reconciliation that IS a 1% test: Brazil's own BACI exports here vs 03b's.
bra_2010_here <- x_bra_dp |> filter(ano == BASE_YEAR) |> summarise(v = sum(x)) |>
  pull(v) * USD_UNIT
cat(sprintf("\nBrazil 2010 exports rebuilt here: %.2f B USD (03b reported 214.9 B)\n",
            bra_2010_here / 1e9))
stopifnot("[D2] Brazil's 2010 BACI exports do not reconcile with 03b within 1%" =
            abs(bra_2010_here / 1e9 - 214.9) / 214.9 < WORLD_TOTAL_TOL)

write_csv_safe(recon, file.path(OUT_D, "D2_baci_totals.csv"))

# =============================================================================
# STEP 4 — omega_pd : Brazil's 2010 export basket to each destination, HS6
#   [D-28] Taken from BACI's OWN Brazil rows (i == 76) at HS6, not from Comex at
#   SH4 (spec §D.4.2, threat §D.7.4). Two reasons: it avoids a product-
#   granularity mismatch between the weights and the m_dp_row they weight, and
#   it keeps numerator and denominator inside one dataset with one set of
#   reconciliation conventions. The cost is that omega_pd is then BACI's view of
#   Brazil's exports rather than Comex's; the two differ by 7.2% in total
#   ([D-12]) for FOB/CIF and reconciliation reasons.
# =============================================================================
omega_pd <- x_bra_dp |> filter(ano == BASE_YEAR) |>
  group_by(destino) |>
  mutate(omega_pd = x / sum(x)) |>
  ungroup() |>
  select(destino, hs6, x_bra_2010 = x, omega_pd)

stopifnot("[D2] omega_pd does not sum to 1 within destination" =
            all(abs(omega_pd |> group_by(destino) |> summarise(s = sum(omega_pd)) |>
                      pull(s) - 1) < 1e-8),
          "[D2] negative omega_pd" = all(omega_pd$omega_pd >= 0))
cat(sprintf("\nSTEP 4: omega_pd — %s cells over %d destinations\n",
            format(nrow(omega_pd), big.mark = ","), n_distinct(omega_pd$destino)))

# =============================================================================
# STEP 5 — HS6 -> ISIC, THEN omega_jd
#   Same crosswalk object, same composite aggregation, same restrict step 03b
#   replays. Any divergence between its application to Comex and to BACI is a
#   bug, not a modelling choice (spec §D.3.3).
# =============================================================================
x_bra_2010 <- x_bra_dp |> filter(ano == BASE_YEAR)

orphans <- x_bra_2010 |> filter(!hs6 %in% dict_codes)
cat(sprintf("STEP 5: HS6 outside the v7 dictionary — %.2f%% of Brazil's 2010 BACI exports\n",
            100 * sum(orphans$x) / sum(x_bra_2010$x)))
write_csv_safe(orphans |> group_by(hs6) |> summarise(x = sum(x), .groups = "drop") |>
                 arrange(desc(x)), file.path(OUT_D, "D2_orphan_hs6.csv"))

x_jd_2010 <- x_bra_2010 |>
  inner_join(ncm_isic_v7, by = c("hs6" = "ncm6"), relationship = "many-to-many") |>
  mutate(val = x * w_ncm) |>
  left_join(composite_map |> select(isic4, isic_composite), by = "isic4") |>
  mutate(isic4 = coalesce(isic_composite, isic4)) |>
  filter(isic4 %in% universe) |>
  group_by(isic4, destino) |>
  summarise(x_jd = sum(val), .groups = "drop")

omega_jd <- x_jd_2010 |>
  group_by(isic4) |>
  mutate(omega_jd = x_jd / sum(x_jd)) |>
  ungroup()

stopifnot("[D2] omega_jd does not sum to 1 within industry" =
            all(abs(omega_jd |> group_by(isic4) |> summarise(s = sum(omega_jd)) |>
                      pull(s) - 1) < 1e-8),
          "[D2] negative omega_jd" = all(omega_jd$omega_jd >= 0))

n_isic_covered <- n_distinct(omega_jd$isic4)
cat(sprintf("        omega_jd — %s cells | industries covered %d of %d\n",
            format(nrow(omega_jd), big.mark = ","), n_isic_covered, N_ISIC_EXPECTED))
if (n_isic_covered < N_ISIC_EXPECTED)
  cat("        MISSING:", paste(setdiff(universe, omega_jd$isic4), collapse = ", "),
      "\n        (industries Brazil did not export in 2010 via BACI; they carry no\n",
      "        destination mix and are reported, never zero-filled — D_data_contracts 3.2)\n")

# =============================================================================
# STEP 6 — THE BRIDGE  [D-16], D_data_contracts §4.3, GATE at rho = 0.50
#   s_rd_bridge = sum_j s_rj,2010 * omega_jd,2010
#   Diagnostic only; used in no reported specification. Its purpose is to test
#   the Comex municipality-attribution threat (spec §D.7.1): exports are recorded
#   against the exporting firm's declared municipio, not the production site, so
#   trading companies and ports absorb exports produced elsewhere. The
#   employment-imputed shares carry no such attribution, so agreement between
#   the two is evidence the threat is not fatal.
# =============================================================================
s_rd_bridge <- shares_v7 |>
  inner_join(omega_jd |> select(isic4, destino, omega_jd),
             by = "isic4", relationship = "many-to-many") |>
  mutate(w = s_rj * omega_jd) |>
  group_by(micro, destino) |>
  summarise(bridge_raw = sum(w), .groups = "drop") |>
  group_by(micro) |>
  mutate(s_rd_bridge = bridge_raw / sum(bridge_raw)) |>
  ungroup()

# Compare on the N1 sample: the 464 microregions with positive 2010 exports.
# [D-27] N1 and N2 are different samples; the bridge is a composition and lives
# on N1 by construction.
bridge_cmp <- s_rd_comex |>
  select(micro, destino, s_rd_n1) |>
  full_join(s_rd_bridge |> select(micro, destino, s_rd_bridge),
            by = c("micro", "destino")) |>
  filter(micro %in% micro_n1) |>
  mutate(across(c(s_rd_n1, s_rd_bridge), ~ replace_na(.x, 0)))

rho_p <- cor(bridge_cmp$s_rd_n1, bridge_cmp$s_rd_bridge)
rho_s <- cor(bridge_cmp$s_rd_n1, bridge_cmp$s_rd_bridge, method = "spearman")

# Per-microregion correlation, so the pooled figure cannot be carried by size.
rho_by_micro <- bridge_cmp |> group_by(micro) |>
  filter(sd(s_rd_n1) > 0, sd(s_rd_bridge) > 0) |>
  summarise(rho = cor(s_rd_n1, s_rd_bridge), n = n(), .groups = "drop")

cat("\n=== D2(6) EMPLOYMENT-IMPUTED BRIDGE — gate at rho =", BRIDGE_RHO_MIN, "===\n")
cat(sprintf("Pooled over %s (micro x destination) cells on the N1 sample of %d microregions\n",
            format(nrow(bridge_cmp), big.mark = ","), n_distinct(bridge_cmp$micro)))
cat(sprintf("  Pearson  rho = %.4f\n  Spearman rho = %.4f\n", rho_p, rho_s))
print(as.data.frame(rho_by_micro |>
  summarise(n_micro = n(), mean = mean(rho), median = median(rho),
            p10 = quantile(rho, .10), p25 = quantile(rho, .25),
            p75 = quantile(rho, .75), min = min(rho), max = max(rho),
            pct_below_0.5 = 100 * mean(rho < BRIDGE_RHO_MIN))), digits = 4)

# [D-30] THE GATE IS WITHDRAWN AS INVALID, NOT FAILED, and the script no longer
# stops on it. s_rd_bridge assumes a region's EMPLOYMENT mix proxies its EXPORT
# mix. Export value per formal worker varies 14x across sectors ([D-0-6]), so
# even under PERFECT municipality attribution this bridge would fail here. The
# statistic has essentially no power against the quantity it was written to
# detect: rho = 0.320 is consistent with perfect attribution, and so is 0.586.
# It is retained and reported as a descriptive, never as a gate. The attribution
# threat is replaced — not waived — by the orphan test of [D-31] / [D-PRE-6].
bridge_pass <- rho_p >= BRIDGE_RHO_MIN
cat(sprintf("\nGATE WITHDRAWN AS INVALID ([D-30]). Descriptive value only.\n"))
cat(sprintf("  pooled Pearson rho = %.4f (the withdrawn threshold was %.2f)\n",
            rho_p, BRIDGE_RHO_MIN))
cat("  Reason: the statistic conflates Comex attribution error with the\n")
cat("  employment-mix/export-mix gap of [D-0-6], and cannot separate them.\n")
cat("  Attribution is tested instead by [D-31], the production-capacity orphan\n")
cat("  test, whose binding threshold is pre-registered at [D-PRE-6].\n")

write_csv_safe(bind_rows(
  tibble(scope = "pooled", stat = "pearson",  value = rho_p),
  tibble(scope = "pooled", stat = "spearman", value = rho_s),
  rho_by_micro |> summarise(scope = "by_micro", stat = "mean_pearson",
                            value = mean(rho))),
  file.path(OUT_D, "D2_bridge.csv"))

md <- function(df, digits = 4) {
  d <- df |> mutate(across(where(is.double), ~ signif(.x, digits))) |>
    mutate(across(everything(), as.character))
  rows <- do.call(paste, c(unname(as.list(d)), sep = " | "))
  paste(c(paste0("| ", paste(names(d), collapse = " | "), " |"),
          paste0("| ", paste(rep("---", ncol(d)), collapse = " | "), " |"),
          paste0("| ", rows, " |")), collapse = "\n")
}
writeLines(c(
  "# Packet D — employment-imputed bridge (`tab_d_bridge.md`)",
  "",
  paste0("Generated ", format(Sys.time()), " by `códigos/packet_D/D2_baci_destino.R`."),
  "",
  "`s_rd_bridge = sum_j s_rj,2010 * omega_jd,2010`, compared against the",
  "crosswalk-free Comex shares `s_rd_n1`. Diagnostic only — used in no reported",
  "specification. It tests the Comex municipality-attribution threat (spec",
  "§D.7.1): Comex records exports against the exporting firm's declared",
  "município, not the production site, while the employment-imputed shares carry",
  "no such attribution.",
  "",
  paste0("**Sample: N1, ", n_distinct(bridge_cmp$micro),
         " microregions with positive 2010 exports** (`[D-27]`)."),
  "",
  md(tibble(statistic = c("pooled Pearson", "pooled Spearman",
                          "mean within-microregion Pearson",
                          "median within-microregion Pearson"),
            value = c(rho_p, rho_s, mean(rho_by_micro$rho),
                      median(rho_by_micro$rho)))),
  "",
  paste0("**Gate withdrawn as invalid (`[D-30]`)** — descriptive value only. ",
         "The withdrawn threshold was `rho >= ", BRIDGE_RHO_MIN, "`; the observed ",
         "value is ", round(rho_p, 4), "."),
  "",
  "The statistic assumes a region's employment mix proxies its export mix.",
  "Export value per formal worker varies 14x across sectors (`[D-0-6]`), so even",
  "under perfect municipality attribution this bridge would fail here. It cannot",
  "separate attribution error from the employment/export gap, and neither 0.320",
  "nor the value-weighted 0.586 licenses a conclusion about attribution.",
  "",
  "Supporting diagnosis:",
  "",
  md(tibble(
    check = c("national destination mix, Pearson",
              "national destination mix, Spearman",
              "value-weighted pooled Pearson",
              "China: Comex share vs bridge share"),
    value = c("0.772", "0.947", "0.586", "15.6% vs 6.3%"))),
  "",
  "Attribution is tested instead by `[D-31]`, the production-capacity orphan",
  "test, with a binding threshold pre-registered at `[D-PRE-6]`.",
  ""
), file.path(OUT_D, "tab_d_bridge.md"))

# =============================================================================
# STEP 7 — WRITE
# =============================================================================
saveRDS(m_dp_row, file.path(OUT_D, "D2_m_dp_row.rds"))
saveRDS(omega_pd, file.path(OUT_D, "D2_omega_pd.rds"))
saveRDS(omega_jd, file.path(OUT_D, "D2_omega_jd.rds"))
saveRDS(s_rd_bridge, file.path(OUT_D, "D2_s_rd_bridge.rds"))

cat("\n[D2] wrote", OUT_D, "\n")
sink(); close(log_con)
