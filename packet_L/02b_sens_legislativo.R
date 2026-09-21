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


# =============================================================================
# [PL-45] THE TRIGGER WAS SCOPED WRONGLY — PL-2022 SLIPS THROUGH IT
# -----------------------------------------------------------------------------
# [PL-39] fires on IMPUTED cells. It misses the symmetric case: a party that
# CHANGED CHARACTER between the wave and the election while keeping a perfectly
# contemporaneous score. Such a cell reads "none" on every provenance column, so
# nothing flags it.
#
# PL-2022 is exactly that case, and it is the largest Chamber delegation.
#
# RESOLVED FROM THE SOURCE, not inferred. Zucco & Power, "The Ideology of
# Brazilian Parties and Presidents", Latin American Politics and Society 66(1),
# 2024 — the research note that reports BLS 9:
#
#   "just as survey fieldwork was drawing to an end in 2021 ... Bolsonaro — after
#    a period in which he had no formal party affiliation — joined the PL in
#    order to launch his 2022 reelection bid."
#
#   "We also modified the estimated position of the PL by averaging it with the
#    position of Bolsonaro, as he himself and many of his close associates
#    joined the PL AFTER BLS 9."
#
# So the 2021 PL score PREDATES Bolsonaro's arrival. The BLS series confirms it:
# +0.328 (2009) -> +0.409 (2013) -> +0.434 (2017) -> +0.493 (2021), a smooth
# centrão trajectory with no Bolsonarist break. The cell is therefore too
# MODERATE for the party that actually contested 2022, biasing polarization DOWN
# — the opposite direction to PSL-2018, and on a larger vote share.
#
# ARMS. (a) point and (b) drop as usual, plus two substantive alternatives:
#   (d) PSL 2021 party score (+0.803) — the amendment's natural comparator, the
#       Bolsonarist vehicle of the previous cycle.
#   (e) ZUCCO & POWER'S OWN CORRECTION — PL averaged with Bolsonaro's 2021
#       position. This is not our invention; it is what the source authors do,
#       for this exact reason. It is the defensible headline alternative.
# =============================================================================
ideologia_raw <- readRDS("bls9_estimates_partiespresidents_long.rds")
pl_2021   <- ideologia_raw$ideo[ideologia_raw$party.or.pres == "PL"   & ideologia_raw$year == 2021]
psl_2021  <- ideologia_raw$ideo[ideologia_raw$party.or.pres == "PSL"  & ideologia_raw$year == 2021]
bols_2021 <- ideologia_raw$ideo[ideologia_raw$party.or.pres == "BOLSONARO" & ideologia_raw$year == 2021]
zp_corrected <- mean(c(pl_2021, bols_2021))

cat("\n\n================ [PL-45] PL-2022 ================\n")
cat(sprintf("  PL trajectory 2009->2021 : %s\n",
    paste(sprintf("%+.3f", ideologia_raw$ideo[ideologia_raw$party.or.pres == "PL" &
                   ideologia_raw$year %in% c(2009,2013,2017,2021)]), collapse = " -> ")))
cat(sprintf("  (a) point   PL 2021           = %+.4f\n", pl_2021))
cat(sprintf("  (d) PSL 2021 party score      = %+.4f\n", psl_2021))
cat(sprintf("  (e) Zucco & Power correction  = %+.4f  (mean of PL and BOLSONARO 2021)\n", zp_corrected))

pl_share <- painel |> filter(year == 2022) |>
  summarise(p = round(100 * sum(votes[bls_label == "PL"], na.rm = TRUE) /
                            sum(votes, na.rm = TRUE), 2)) |> pull(p)
cat(sprintf("  PL share of the 2022 Chamber vote = %.2f%%  (threshold %d%%)\n",
            pl_share, SENS_THRESHOLD))

set_pl <- function(v) painel |> mutate(ideo = ifelse(year == 2022 & bls_label == "PL", v, ideo))
drop_pl <- painel |> mutate(ideo = ifelse(year == 2022 & bls_label == "PL", NA_real_, ideo))

pl_arms <- bind_rows(
  summarise_idx(build_idx(painel),            "(a) point  PL 2021 +0.493"),
  summarise_idx(build_idx(drop_pl),           "(b) drop   PL 2022"),
  summarise_idx(build_idx(set_pl(psl_2021)),  "(d) PSL21  +0.803"),
  summarise_idx(build_idx(set_pl(zp_corrected)), "(e) Z&P    +0.678")
) |> filter(year == 2022)

cat("\n--- [PL-45] 2022 CHAMBER INDEX BY ARM ---\n")
print(as.data.frame(pl_arms), row.names = FALSE)
write_csv_safe(pl_arms, file.path("output", "packet_L", "tab_pl45_pl2022_arms.csv"))

drop_cov <- drop_pl |> filter(year == 2022) |>
  summarise(unscored = round(100 * sum(votes[is.na(ideo)], na.rm = TRUE) /
                                   sum(votes, na.rm = TRUE), 2)) |> pull(unscored)
cat(sprintf("\n[PL-46] drop arm leaves %.2f%% of the 2022 vote unscored -> %s\n",
            drop_cov, ifelse(drop_cov <= 15, "ADMISSIBLE", "a BOUND, fails [PL-19]")))

cat("\n--- [PL-45] does the [PL-27] verdict move? ---\n")
r2_pl <- bind_rows(
  r2_of(painel,                "(a) point"),
  r2_of(set_pl(psl_2021),      "(d) PSL21"),
  r2_of(set_pl(zp_corrected),  "(e) Z&P")
) |> filter(year == 2022)
print(as.data.frame(r2_pl), row.names = FALSE)
cat("Presidential benchmark 0.96. The L5 verdict holds only if all arms stay far below it.\n")
