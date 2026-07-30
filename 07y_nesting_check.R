# =============================================================================
# 07y_nesting_check.R  —  [T-5] acceptance criterion 7, standalone
# -----------------------------------------------------------------------------
# Verifies that imposing b_boom = -b_bust recovers the pooled beta exactly, i.e.
# that sd_epw is the correct scale anchor for the boom/bust magnitudes. The check
# also runs inside 07_regression_inference.R; this file exists so it can be run
# against a SNAPSHOT vintage without re-running the pipeline (the "tradable"
# artefacts are preserved in vintage_tradable/ before the [T-2b] flip).
#
# Usage:  Rscript 07y_nesting_check.R [vintage_dir]
#         no argument -> the live artefacts in DATA_DIR
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
suppressMessages(library(tidyverse)); suppressMessages(library(fixest))
setFixest_notes(FALSE)

args <- commandArgs(trailingOnly = TRUE)
vdir <- if (length(args)) args[1] else "."
rd   <- function(f) readRDS(file.path(vdir, f))
cat("[07y] vintage dir:", normalizePath(vdir), "\n")

df_raw <- rd("df_estimation_v7.rds") |> mutate(micro = as.character(microregion_code))
epw    <- rd("epw_panel_isic_v7.rds") |> mutate(micro = as.character(micro))

df <- df_raw |>
  select(-any_of("delta_EPW")) |>
  left_join(epw |> filter(year != 2010) |> select(micro, year, delta_EPW = EPW),
            by = c("micro", "year")) |>
  filter(year != 2010, micro %in% unique(epw$micro)) |>
  mutate(tradable_emp_share = replace_na(tradable_emp_share, 0),
         delta_EPW = replace_na(delta_EPW, 0)) |>
  filter(tradable_emp_share > 0, !is.na(manuf_share_of_tradable))

ctrl_base <- c("ln_gdp_pc", "ln_pop", "tradable_emp_share")
outcomes  <- c("delta_P_dalton", "delta_P_center")
zvars     <- unique(c(outcomes, "delta_EPW", ctrl_base))

sd_epw    <- sd(df$delta_EPW)
df_scaled <- df |>
  mutate(delta_EPW_raw = delta_EPW) |>
  mutate(across(all_of(zvars), ~ as.numeric(scale(.)))) |>
  mutate(epw_boom = pmax( delta_EPW_raw, 0) / sd_epw,
         epw_bust = pmax(-delta_EPW_raw, 0) / sd_epw,
         epw_net  = epw_boom - epw_bust)

gap <- map_dbl(set_names(outcomes), function(oc) {
  f <- function(x) feols(as.formula(paste(oc, "~", x, "+",
                                          paste(ctrl_base, collapse = " + "),
                                          "| state^year")), data = df_scaled)
  abs(coef(f("epw_net"))[["epw_net"]] - coef(f("delta_EPW"))[["delta_EPW"]])
})
cat(sprintf("N = %d | sd(dEPW) = %.6f\n", nobs(feols(delta_P_dalton ~ delta_EPW |
                                                       state^year, data = df_scaled)), sd_epw))
for (oc in outcomes) cat(sprintf("  %-16s |b(boom-bust) - b_pooled| = %.3e\n", oc, gap[[oc]]))
stopifnot("nesting fails: sd_epw is not the right anchor" = max(gap) < 1e-9)
cat("[07y] PASS: b+ = -b- recovers the pooled beta.\n")
