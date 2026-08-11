# =============================================================================
# revision/R00_setup.R  —  shared bootstrap for the ANPEC revision battery
# -----------------------------------------------------------------------------
# ADDITIVE. Nothing in the existing pipeline is modified or deleted. This file
# rebuilds EXACTLY the estimation frame that 07_regression_inference.R builds
# (same inputs, same universe rule, same standardisation, same W and g_mat) so
# that every revision task estimates on the identical sample. H2 asserts the
# reproduction against the published Table 3.
#
# Provides:
#   df_scaled, df (raw), sd_epw, ctrl_base, ctrl_ext, outcomes
#   W, g_mat, share_wide, shares, shocks, centroids
#   make_epw_star(perm), ri_fast_factory(), p_ri()
#   REV_DIR(task) -> output/revision/<task>/ (created on demand)
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
source("/Users/solenoide/Documents/dissertação/data/códigos/_estimation_functions.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(fixest)
})
setFixest_notes(FALSE)
# One thread per process. These scripts are run several at a time; fixest's
# default (all cores) oversubscribes the machine and, under that contention,
# a long RI loop can die with a bus error inside combine_fixef(). Override with
# REV_NTHREADS if running a single script.
setFixest_nthreads(as.integer(Sys.getenv("REV_NTHREADS", "1")))
set.seed(2026)

# readr cannot OVERWRITE a file whose absolute path contains the decomposed-UTF8
# "dissertação"/"versão" segments (it normalises the path on the overwrite branch
# and libc then rejects it); creating a new file is fine. Every re-run of a
# revision script would therefore fail on its second pass. Unlink first.
write_csv <- function(x, file, ...) {
  if (file.exists(file)) unlink(file)
  readr::write_csv(x, file, ...)
}

REV_ROOT <- file.path("output", "revision")
dir.create(REV_ROOT, showWarnings = FALSE, recursive = TRUE)
REV_DIR <- function(task) {
  d <- file.path(REV_ROOT, task)
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  d
}

# ---- inputs (all _v7, identical to 07) --------------------------------------
df_raw    <- readRDS("df_estimation_v7.rds")
shares    <- readRDS("exposure_shares_isic_v7.rds")
shocks    <- readRDS("sectoral_shocks_isic_v7.rds")
epw_v7    <- readRDS("epw_panel_isic_v7.rds")
sumsh     <- readRDS("tradable_emp_share_2010_v7.rds")
centroids <- readRDS("micro_centroids.rds") |> mutate(micro = as.character(micro))

df_raw <- df_raw |> mutate(micro = as.character(microregion_code))
shares <- shares |> mutate(micro = as.character(micro))
sumsh  <- sumsh  |> mutate(micro = as.character(micro))
epw_v7 <- epw_v7 |> mutate(micro = as.character(micro))

df_raw <- df_raw |>
  select(-any_of("delta_EPW")) |>
  left_join(epw_v7 |> filter(year != 2010) |> select(micro, year, delta_EPW = EPW),
            by = c("micro", "year"))

epw_micros <- unique(epw_v7$micro)
df <- df_raw |> filter(year != 2010) |> filter(micro %in% epw_micros)

if ("tradable_emp_share" %in% names(df)) {
  chk <- df |> distinct(micro, tradable_emp_share) |> inner_join(sumsh, by = "micro")
  stopifnot(max(abs(chk$tradable_emp_share.x - chk$tradable_emp_share.y)) < 1e-12)
} else {
  df <- df |> left_join(sumsh, by = "micro")
}
df <- df |> mutate(tradable_emp_share = replace_na(tradable_emp_share, 0),
                   delta_EPW          = replace_na(delta_EPW, 0))

undefined_micro <- df |>
  filter(tradable_emp_share <= 0 | is.na(manuf_share_of_tradable)) |>
  distinct(micro)
if (nrow(undefined_micro)) df <- df |> filter(!micro %in% undefined_micro$micro)

stopifnot(all(df$year %in% c(2014, 2018, 2022)),
          !anyNA(df$tradable_emp_share), !anyNA(df$manuf_share_of_tradable),
          all(df$tradable_emp_share > 0), !anyNA(df$delta_EPW), !anyNA(df$state))
N_SAMPLE <- nrow(df)

ctrl_base <- c("ln_gdp_pc", "ln_pop", "tradable_emp_share")
ctrl_ext  <- c(ctrl_base, "urban_share", "educ_share", "manuf_share_of_tradable")
outcomes  <- c("delta_P_dalton", "delta_P_center")
zvars     <- unique(c(outcomes, "delta_EPW", ctrl_ext))

df_scaled <- df |>
  mutate(delta_EPW_raw = delta_EPW, theta_raw = tradable_emp_share) |>
  mutate(across(all_of(zvars), ~ as.numeric(scale(.)))) |>
  select(-any_of(c("lat", "lon", "long"))) |>
  left_join(centroids, by = "micro") |>
  rename(long = lon)
stopifnot(!anyNA(df_scaled$lat), !anyNA(df_scaled$long))

sd_epw <- sd(df$delta_EPW)

# ---- share matrix W and shock matrix g_mat (identical construction to 07) ----
share_wide <- shares |> select(micro, isic4, s_rj) |>
  pivot_wider(names_from = isic4, values_from = s_rj, values_fill = 0)

W <- df_scaled |> select(micro) |>
  left_join(share_wide, by = "micro") |> select(-micro) |>
  mutate(across(everything(), ~ replace_na(., 0))) |> as.matrix()
stopifnot(nrow(W) == nrow(df_scaled), !anyNA(W))

g_wide <- shocks |> filter(year %in% c(2014, 2018, 2022)) |>
  select(isic4, year, g_jt) |>
  pivot_wider(names_from = year, values_from = g_jt, values_fill = 0)
g_mat <- g_wide |> column_to_rownames("isic4") |> as.matrix()
stopifnot(all(colnames(W) %in% rownames(g_mat)))
g_mat <- g_mat[colnames(W), , drop = FALSE]

YEARS    <- c("2014", "2018", "2022")
year_chr <- as.character(df_scaled$year)
yr_idx   <- cbind(seq_len(nrow(W)), match(year_chr, YEARS))

make_epw_star <- function(perm, Wm = W, gm = g_mat, idx = yr_idx) {
  g_star  <- gm[perm, , drop = FALSE]
  epw_mat <- sapply(YEARS, function(t) as.numeric(Wm %*% g_star[, t]))
  epw_mat[idx]
}

p_ri <- function(stars, hat) (1 + sum(abs(stars) >= abs(hat))) / (length(stars) + 1)

cat(sprintf("[R00] setup OK | N_SAMPLE = %d | micros = %d | industries = %d | sd_epw = %.6f\n",
            N_SAMPLE, n_distinct(df$micro), ncol(W), sd_epw))
