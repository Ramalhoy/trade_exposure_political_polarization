# =============================================================================
# 02b_sens_legislativo.R  —  L6 : [PL-39] sensitivity, Chamber level
# -----------------------------------------------------------------------------
# Every IMPUTED cell holding >= 3% of a year's valid Chamber votes is reported
# three ways. Threshold declared in the amendment, before the indices existed.
#
#   (a) POINT       the carried score, the headline, reported with provenance
#   (b) DROP        party excluded, shares RENORMALISED over scored parties only
#                   -- the same rule the index already applies to unmatched votes,
#                   so this is not a new device
#   (c) BREAK-EVEN  the score the party would need for the conclusion to reverse
#
#   AUXILIARY       +/- 2 * ideo.se around the carried score (ideo.se is in the
#                   BLS file and costs nothing)
#
# ON ARM (c) AT THIS LEVEL: break-even is defined in [PL-39] as the value at which
# "the sign / significance verdict on the relevant ΔP coefficient flips". The
# Chamber outcome has never entered the estimation frame -- no ΔP regression has
# ever been run at this level -- so there is no verdict yet to flip, and (c) is
# NOT YET DEFINED here. It becomes computable once the Chamber ΔP joins the
# design, which is a separate decision. Arm (c) IS defined and IS run at the
# presidential and governor levels, where conclusions already exist: 02c.
# This script therefore reports (a), (b) and the SE band, and states the gap.
#
# OUTPUTS: output/packet_L/tab_pl_sens_chamber.csv
#          output/packet_L/tab_pl_sens_chamber_detail.csv
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
suppressMessages({library(dplyr); library(tidyr); library(stringr); library(tibble)})

write_csv_safe <- function(x, path) {            # [PL-35]
  utils::write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8"); invisible(path)
}
NEUTRAL_BAND <- 0.25
ER_ALPHA     <- c(1.0, 1.4)
SENS_THRESHOLD <- 3

er_one <- function(v, y, alpha) { D <- abs(outer(y, y, "-")); sum((v^(1 + alpha)) * (D %*% v)) }
rq_one <- function(v) 1 - sum(((0.5 - v) / 0.5)^2 * v)

painel <- readRDS("painel_ideologico_deputado_federal.rds")

# index builder, identical formulas to 02b, on an arbitrary scored subset
build_idx <- function(df) {
  df |>
    filter(!is.na(ideo)) |>
    summarise(votes = sum(votes, na.rm = TRUE), ideo = first(ideo),
              .by = c(microregion_code, year, bls_label)) |>
    mutate(v_rpt = votes / sum(votes, na.rm = TRUE), .by = c(microregion_code, year)) |>
    summarise(n_parties = n(),
              y_bar    = sum(v_rpt * ideo),
              P_dalton = sqrt(sum(v_rpt * (ideo - sum(v_rpt * ideo))^2)),
              P_center = 1 - sum(v_rpt * (ideo >= -NEUTRAL_BAND & ideo <= NEUTRAL_BAND)),
              P_er_10  = er_one(v_rpt, ideo, ER_ALPHA[1]),
              P_er_14  = er_one(v_rpt, ideo, ER_ALPHA[2]),
              P_rq     = rq_one(v_rpt),
              .by = c(microregion_code, year))
}

summarise_idx <- function(idx, arm) {
  idx |> summarise(across(c(y_bar, P_dalton, P_center, P_er_10, P_er_14, P_rq),
                          ~ round(mean(.x), 4)), .by = year) |>
    mutate(arm = arm, .before = 1) |> arrange(year)
}

# cells over the threshold
tot <- painel |> summarise(tot = sum(votes, na.rm = TRUE), .by = year)
cells <- painel |>
  filter(!is.na(ideo), ideo_carry != "none") |>
  summarise(votes = sum(votes, na.rm = TRUE),
            .by = c(year, bls_label, ideo_carry, ideo_wave, ideo, ideo.se)) |>
  left_join(tot, by = "year") |>
  mutate(pct = round(100 * votes / tot, 2)) |>
  filter(pct >= SENS_THRESHOLD) |> arrange(year, desc(pct))

cat("--- [PL-39] CELLS AT OR ABOVE", SENS_THRESHOLD, "% ---\n")
print(as.data.frame(cells |> select(year, bls_label, pct, ideo, ideo.se, ideo_wave, ideo_carry)),
      row.names = FALSE)

# ---- (a) POINT --------------------------------------------------------------
out <- summarise_idx(build_idx(painel), "(a) point")

detail <- list()

for (i in seq_len(nrow(cells))) {
  cl <- cells[i, ]
  tag <- sprintf("%s %d", cl$bls_label, cl$year)

  # ---- (b) DROP: remove the cell, renormalise over remaining scored parties --
  dropped <- painel |>
    mutate(ideo = ifelse(year == cl$year & bls_label == cl$bls_label, NA_real_, ideo))
  idx_d <- build_idx(dropped)
  cov_d <- dropped |>
    summarise(unscored_pct = round(100 * sum(votes[is.na(ideo)], na.rm = TRUE) /
                                        sum(votes, na.rm = TRUE), 2), .by = year)
  out <- bind_rows(out, summarise_idx(idx_d, sprintf("(b) drop %s", tag)))

  # ---- AUXILIARY: +/- 2 * ideo.se on the carried score ----------------------
  for (k in c(-2, 2)) {
    shifted <- painel |>
      mutate(ideo = ifelse(year == cl$year & bls_label == cl$bls_label,
                           ideo + k * ideo.se, ideo))
    out <- bind_rows(out, summarise_idx(build_idx(shifted),
                      sprintf("aux %s %+d*se", tag, k)))
  }

  detail[[tag]] <- tibble(
    cell = tag, pct_of_vote = cl$pct, ideo_point = cl$ideo, ideo_se = cl$ideo.se,
    carry = cl$ideo_carry, from_wave = cl$ideo_wave,
    unscored_pct_after_drop = cov_d$unscored_pct[cov_d$year == cl$year],
    passes_PL19_after_drop  = cov_d$unscored_pct[cov_d$year == cl$year] <= 15)
}

detail <- bind_rows(detail)
cat("\n--- DROP ARM: COVERAGE CONSEQUENCE ---\n")
print(as.data.frame(detail), row.names = FALSE)
write_csv_safe(detail, file.path("output", "packet_L", "tab_pl_sens_chamber_detail.csv"))

cat("\n--- INDEX MEANS UNDER EVERY ARM ---\n")
print(as.data.frame(out |> arrange(year, arm)), row.names = FALSE)
write_csv_safe(out, file.path("output", "packet_L", "tab_pl_sens_chamber.csv"))

# ---- does the [PL-27] verdict itself survive the arms? ----------------------
cat("\n--- [PL-27] R2 UNDER EVERY ARM (the verdict L5 turned on) ---\n")
r2_of <- function(df, arm) {
  idx <- build_idx(df)
  fp  <- df |> filter(!is.na(ideo)) |>
    mutate(v = votes / sum(votes), .by = c(microregion_code, year)) |>
    summarise(v_max = max(v), .by = c(microregion_code, year))
  idx |> left_join(fp, by = c("microregion_code", "year")) |>
    summarise(r2 = round(summary(lm(P_dalton ~ v_max))$r.squared, 4), .by = year) |>
    mutate(arm = arm, .before = 1) |> arrange(year)
}
r2 <- r2_of(painel, "(a) point")
for (i in seq_len(nrow(cells))) {
  cl <- cells[i, ]; tag <- sprintf("%s %d", cl$bls_label, cl$year)
  r2 <- bind_rows(r2, r2_of(painel |> mutate(
    ideo = ifelse(year == cl$year & bls_label == cl$bls_label, NA_real_, ideo)),
    sprintf("(b) drop %s", tag)))
}
print(as.data.frame(r2 |> pivot_wider(names_from = arm, values_from = r2)), row.names = FALSE)
cat("\nPresidential benchmark: 0.96 (2022). The verdict survives an arm only if\n",
    "the Chamber R2 stays far below it.\n")

cat("\nARM (c) break-even is not computed here: no ΔP regression has ever been run\n",
    "at the Chamber level, so there is no verdict to reverse. See the header.\n")
