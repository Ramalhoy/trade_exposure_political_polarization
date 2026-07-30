# =============================================================================
# 07x_akm.R  —  AKM / AKM0 (secondary inference regime), extracted correctly
# -----------------------------------------------------------------------------
# WHY THIS FILE EXISTS
#
# The [T-9] manifest reported every AKM standard error as NA. The cause was an
# extraction bug in 07's tidy_akm(), not in ShiftShareSE. reg_ss() returns
# LENGTH-5 named vectors --
#     Homoscedastic | EHW | Reg. cluster | AKM | AKM0
# -- and the three entries for methods that were NOT requested are NA by design
# (the package's own print.SSResults does `s <- !is.na(x$se)` to drop them).
# tidy_akm() picked "the first element that is not AKM0", i.e. Homoscedastic =
# NA, instead of the element NAMED "AKM". Fixed by indexing by name.
#
# THE "REVERSED" INTERVAL IS NOT A BUG. print.SSResults encodes an UNBOUNDED
# AKM0 confidence set by returning ci.l > ci.r, and formats it as
#     (-Inf , ci.r ] + [ ci.l , Inf )
# i.e. the confidence set is the COMPLEMENT of the bounded interval
# (ci.r, ci.l). This is the standard weak-identification signature for a
# test-inversion (Anderson-Rubin style) confidence set: when the first stage is
# weak, the set that cannot be rejected is unbounded. It is reportable as
# corroboration of the design-based null, NOT a defect to be suppressed. This
# script therefore classifies every set explicitly rather than printing two
# numbers whose order silently changes meaning.
#
# Usage:  Rscript 07x_akm.R <denom_label> [vintage_dir]
#   Rscript 07x_akm.R total                     # live artefacts
#   Rscript 07x_akm.R tradable vintage_tradable # frozen pre-flip vintage
# Outputs: output/akm_<denom_label>.csv
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
suppressMessages({library(tidyverse); library(fixest); library(ShiftShareSE)})
setFixest_notes(FALSE)

args  <- commandArgs(trailingOnly = TRUE)
denom <- if (length(args) >= 1) args[1] else SHARE_DENOM
vdir  <- if (length(args) >= 2) args[2] else "."
rd    <- function(f) readRDS(file.path(vdir, f))
cat("[07x] denom label:", denom, "| vintage:", normalizePath(vdir), "\n")

# ---- rebuild the 07 estimation sample (must match exactly) ------------------
df_raw <- rd("df_estimation_v7.rds") |> mutate(micro = as.character(microregion_code))
epw    <- rd("epw_panel_isic_v7.rds") |> mutate(micro = as.character(micro))
shares <- rd("exposure_shares_isic_v7.rds") |> mutate(micro = as.character(micro))

df <- df_raw |>
  select(-any_of("delta_EPW")) |>
  left_join(epw |> filter(year != 2010) |> select(micro, year, delta_EPW = EPW),
            by = c("micro", "year")) |>
  filter(year != 2010, micro %in% unique(epw$micro)) |>
  mutate(tradable_emp_share = replace_na(tradable_emp_share, 0),
         delta_EPW          = replace_na(delta_EPW, 0)) |>
  filter(tradable_emp_share > 0, !is.na(manuf_share_of_tradable))

ctrl_base <- c("ln_gdp_pc", "ln_pop", "tradable_emp_share")
ctrl_ext  <- c(ctrl_base, "urban_share", "educ_share", "manuf_share_of_tradable")
outcomes  <- c("delta_P_dalton", "delta_P_center")
zvars     <- unique(c(outcomes, "delta_EPW", ctrl_ext))
df_scaled <- df |> mutate(across(all_of(zvars), ~ as.numeric(scale(.))))

share_wide <- shares |> select(micro, isic4, s_rj) |>
  pivot_wider(names_from = isic4, values_from = s_rj, values_fill = 0)
mkW <- function(d) {
  W <- d |> select(micro) |> left_join(share_wide, by = "micro") |>
    select(-micro) |> mutate(across(everything(), ~ replace_na(., 0))) |> as.matrix()
  stopifnot(nrow(W) == nrow(d), !anyNA(W)); W
}
W <- mkW(df_scaled)

# ---- correct extraction + explicit confidence-set semantics -----------------
# The AKM0 confidence set is one of three things, and the ci.l/ci.r pair alone
# does not say which. Classify it.
tidy_ss <- function(a, tag) {
  pick <- function(v, nm) if (nm %in% names(v)) as.numeric(v[[nm]]) else NA_real_
  map_dfr(c("AKM", "AKM0"), function(m) {
    l <- pick(a$ci.l, m); r <- pick(a$ci.r, m)
    ci_type <- if (is.na(l) || is.na(r)) "missing"
      else if (is.infinite(l) && is.infinite(r)) "unbounded (whole real line)"
      else if (l > r) "unbounded (complement of a bounded interval)"
      else if (is.infinite(l) || is.infinite(r)) "half-unbounded"
      else "bounded"
    ci_txt <- switch(ci_type,
      "bounded" = sprintf("[%.5f, %.5f]", l, r),
      "unbounded (complement of a bounded interval)" =
        sprintf("(-Inf, %.5f] u [%.5f, Inf)", r, l),
      "half-unbounded" = sprintf("[%.5f, %.5f]", l, r),
      "unbounded (whole real line)" = "(-Inf, Inf)",
      "missing" = NA_character_)
    tibble(spec = tag, stat = m, beta = as.numeric(a$beta),
           se = pick(a$se, m), p = pick(a$p, m),
           ci_l = l, ci_r = r, ci_type = ci_type, ci = ci_txt)
  })
}

fml <- function(ctrls, fe) reformulate(c(ctrls, fe), response = "delta_P_dalton")

res <- list()
# pooled, both control sets, both outcomes
for (oc in outcomes) for (cn in c("base", "ext")) {
  ctrls <- if (cn == "base") ctrl_base else ctrl_ext
  a <- reg_ss(reformulate(c(ctrls, "factor(state):factor(year)"), response = oc),
              X = df_scaled$delta_EPW, data = df_scaled, W = W,
              method = c("akm", "akm0"))
  res[[length(res) + 1]] <- tidy_ss(a, sprintf("pooled %s / %s ctrls", oc, cn))
}
# by year (base controls, state FE only) -- this is where the first stage is
# thinnest and the unbounded sets are expected
for (t in c(2014, 2018, 2022)) {
  d <- filter(df_scaled, year == t)
  a <- reg_ss(reformulate(c(ctrl_base, "factor(state)"), response = "delta_P_dalton"),
              X = d$delta_EPW, data = d, W = mkW(d), method = c("akm", "akm0"))
  res[[length(res) + 1]] <- tidy_ss(a, sprintf("delta_P_dalton / %d / base ctrls", t))
}

akm_tbl <- bind_rows(res) |> mutate(share_denom = denom, n = nrow(df_scaled))
cat("\n=== AKM / AKM0, share_denom =", denom, "===\n")
print(as.data.frame(akm_tbl |> select(spec, stat, beta, se, p, ci, ci_type)),
      digits = 4, right = FALSE)

n_unb <- sum(grepl("^unbounded", akm_tbl$ci_type))
cat(sprintf("\n[07x] %d of %d confidence sets are unbounded.\n", n_unb, nrow(akm_tbl)))
cat("Unbounded AKM0 sets are the weak-identification signature: with an\n",
    "effective number of shocks near 2.5, the test-inversion set that cannot be\n",
    "rejected is not compact. Report as corroboration of the RI null.\n")
stopifnot("AKM SE failed to extract -- check reg_ss component names" =
            !all(is.na(akm_tbl$se[akm_tbl$stat == "AKM"])))

write_csv(akm_tbl, file.path("output", sprintf("akm_%s.csv", denom)))
cat("[07x] wrote output/akm_", denom, ".csv\n", sep = "")
