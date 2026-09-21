# =============================================================================
# 02c_sensitivity_levels.R  —  L7 : [PL-40] / [PL-41] retrofit
# -----------------------------------------------------------------------------
# ADDITIVE. 02_polarization_indices.R is NOT modified. Everything here is written
# with a `_sens` suffix or into output/packet_L/.
#
# [PL-40] 02_polarization_indices.R substitutes the BOLSONARO 2022 estimate for
#   PSL in 2018 and that imputation is invisible in every table the dissertation
#   reports. It is the same class of imputation as [PL-37], on the same party, in
#   the same year, in the direction that most favours the hypothesis — and it is
#   WORSE in one respect: it scores a CANDIDATE and applies it to a PARTY. The
#   object `ideologia_psl` is shared by the presidential AND governor builds.
#
#   This script: (1) flags the patched cells with [PL-38] provenance columns at
#   both levels; (2) measures what share of each year's vote rests on the patch;
#   (3) runs the [PL-39] three-way for every cell over the 3% threshold; and
#   (4) adds a FOURTH arm at these levels only — PSL-2018 scored from the 2021
#   PSL PARTY entry instead of the BOLSONARO CANDIDATE estimate. That is the
#   apples-to-apples comparison the Chamber level uses, and it isolates whether
#   the candidate/party distinction moves anything.
#
# [PL-41] The 15% coverage gate has never been applied at these levels —
#   diagnostico_na() prints, nothing stops. Run retrospectively, report whatever
#   it says, and do not stop the packet on it.
#
# OUTPUTS: output/packet_L/tab_pl40_*.csv, tab_pl41_coverage_gate.csv
#          dalton_panel_{presidencial,governador}_sens.rds
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
suppressMessages({library(dplyr); library(tidyr); library(stringr); library(tibble); library(fixest)})

write_csv_safe <- function(x, path) {            # [PL-35]
  utils::write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8"); invisible(path)
}
dir.create(file.path("output", "packet_L"), recursive = TRUE, showWarnings = FALSE)
SENS_THRESHOLD <- 3

ideologia <- readRDS("bls9_estimates_partiespresidents_long.rds") |>
  mutate(ano_eleicao = year + 1)

# the patch exactly as 02_polarization_indices.R builds it
psl_patch <- ideologia |>
  filter(party.or.pres == "BOLSONARO", ano_eleicao == 2022) |>
  mutate(party.or.pres = "PSL", ano_eleicao = 2018)
psl_party_2021 <- ideologia |> filter(party.or.pres == "PSL", year == 2021)

cat("--- [PL-40] THE TWO CANDIDATE SCORES FOR PSL 2018 ---\n")
cat(sprintf("  (a) BOLSONARO 2022 candidate estimate : ideo = %.4f (se %.4f)  <- status quo\n",
            psl_patch$ideo, psl_patch$ideo.se))
cat(sprintf("  (d) PSL 2021 PARTY estimate           : ideo = %.4f (se %.4f)\n",
            psl_party_2021$ideo, psl_party_2021$ideo.se))

# ---- panel builder with [PL-38] provenance ---------------------------------
build_level <- function(votes_path, psl_ideo, psl_se, arm) {
  ide <- ideologia
  if (!is.na(psl_ideo)) {
    add <- psl_patch |> mutate(ideo = psl_ideo, ideo.se = psl_se)
    ide <- bind_rows(ide, add)
  }
  readRDS(votes_path) |>
    filter(round == 1) |>
    mutate(party = str_trim(toupper(party))) |>
    left_join(ide |> select(party.or.pres, ano_eleicao, ideo, ideo.se, wave = year),
              by = c("party" = "party.or.pres", "year" = "ano_eleicao")) |>
    mutate(ideo_wave       = wave,
           ideo_carry      = case_when(
             is.na(ideo)                      ~ NA_character_,
             party == "PSL" & year == 2018    ~ "patch_candidate",
             TRUE                             ~ "none"),
           ideo_carry_dist = ifelse(ideo_carry == "none", 0L, 1L),
           arm             = arm)
}

idx_of <- function(p) {
  p |> filter(!is.na(ideo)) |>
    group_by(microregion_code, year) |>
    mutate(v_rpt = votes / sum(votes, na.rm = TRUE),
           y_bar = sum(v_rpt * ideo, na.rm = TRUE)) |>
    summarise(y_bar = first(y_bar),
              P_dalton = sqrt(sum(v_rpt * (ideo - y_bar)^2, na.rm = TRUE)),
              P_center = first(1 - sum(v_rpt * (ideo >= -0.25 & ideo <= 0.25))),
              .groups = "drop")
}

LEVELS <- list(
  presidencial = "painel_votos_presidenciais_microregioes_2010_2022.rds",
  governador   = "painel_votos_governador_microregioes_2010_2022.rds"
)

# =============================================================================
# [PL-41] retrospective coverage gate, and [PL-40].2 patch load
# =============================================================================
gate <- list(); load_tab <- list()
for (nv in names(LEVELS)) {
  p <- build_level(LEVELS[[nv]], psl_patch$ideo, psl_patch$ideo.se, "(a) point")
  tot <- p |> summarise(tot = sum(votes, na.rm = TRUE), .by = year)
  gate[[nv]] <- p |> filter(is.na(ideo)) |>
    summarise(votos_na = sum(votes, na.rm = TRUE), .by = year) |>
    right_join(tot, by = "year") |>
    mutate(nivel = nv, votos_na = coalesce(votos_na, 0),
           unscored_pct = round(100 * votos_na / tot, 2),
           passes_PL19  = unscored_pct <= 15) |>
    select(nivel, year, unscored_pct, passes_PL19) |> arrange(year)
  load_tab[[nv]] <- p |>
    mutate(bucket = ifelse(is.na(ideo), "unscored", ideo_carry)) |>
    summarise(votes = sum(votes, na.rm = TRUE), .by = c(year, bucket)) |>
    mutate(pct = round(100 * votes / sum(votes), 2), .by = year) |>
    select(-votes) |> pivot_wider(names_from = bucket, values_from = pct, values_fill = 0) |>
    mutate(nivel = nv, .before = 1) |> arrange(year)
}
gate <- bind_rows(gate); load_tab <- bind_rows(load_tab)

cat("\n--- [PL-41] 15% GATE ON THE RAW-LABEL (V0) JOIN — NOT THE CANONICAL RUNG ---\n")
cat("This reproduces 02_polarization_indices.R's raw `party` join, which is packet I's\n",
    "V0 rung. It is NOT what the manuscript uses. See [PL-44] below for the real gate.\n")
print(as.data.frame(gate), row.names = FALSE)
write_csv_safe(gate, file.path("output", "packet_L", "tab_pl41_coverage_gate.csv"))
if (any(!gate$passes_PL19))
  cat("\n>>> [PL-41] THE GATE FAILS ON RESULTS ALREADY IN THE MANUSCRIPT:",
      paste(sprintf("%s %d (%.2f%%)", gate$nivel[!gate$passes_PL19],
                    gate$year[!gate$passes_PL19], gate$unscored_pct[!gate$passes_PL19]),
            collapse = "; "), "\n")

# =============================================================================
# [PL-44] THE GATE AT THE CANONICAL RUNG — AND A PROVENANCE DEFECT IN PACKET I
# -----------------------------------------------------------------------------
# CORRECTION to the first reading of [PL-41]. The governor coverage "failure" at
# V0 is a LABEL artefact, not a coverage problem, and packet I ([I-2] crosswalk,
# [I-3] carry, [I-4] UNIAO) already established and fixed it. Measured at the
# canonical rung the gate passes at both levels in every year, with margin.
#
# But reading those panels surfaces something else. At V3, PSL-2018 carries
# ideo = 0.8620139, which is EXACTLY the BOLSONARO 2022 CANDIDATE estimate -- the
# `02` patch -- and NOT the PSL 2021 party score (0.8033588). The 2017 wave does
# not score PSL at all. Yet the cell is labelled `ideo_source = "onda"`, i.e. a
# contemporaneous own-wave party score.
#
# So packet I's provenance system -- built precisely to track imputation -- carries
# the single largest imputation in the data as NON-imputed. It inherited
# `ideologia_psl` from 02 before applying its own carry logic, so the patch was
# already baked into the table that [I-3] treats as "onda". The consequence: of
# the 96.13% of the 2018 presidential vote that packet I reports as own-wave,
# about 46 points are a candidate-score imputation.
# =============================================================================
canon <- list(presidencial = "painel_ideologico_presidencial_V3.rds",
              governador   = "painel_ideologico_governador_V3.rds")
gate_canon <- lapply(names(canon), function(nv) {
  readRDS(canon[[nv]]) |>
    summarise(unscored_pct = round(100 * sum(votes[is.na(ideo)], na.rm = TRUE) /
                                         sum(votes, na.rm = TRUE), 2), .by = year) |>
    mutate(nivel = nv, passes_PL19 = unscored_pct <= 15) |>
    select(nivel, year, unscored_pct, passes_PL19) |> arrange(year)
}) |> bind_rows()

cat("\n--- [PL-44] 15% GATE AT THE CANONICAL RUNG (packet I V3) ---\n")
print(as.data.frame(gate_canon), row.names = FALSE)
write_csv_safe(gate_canon, file.path("output", "packet_L", "tab_pl44_gate_canonical.csv"))
cat(ifelse(all(gate_canon$passes_PL19),
           ">>> [PL-44] The gate PASSES at both levels in every year.\n",
           ">>> [PL-44] The gate still fails somewhere; see the table.\n"))

# ---- the provenance audit --------------------------------------------------
bols <- ideologia |> filter(party.or.pres == "BOLSONARO", year == 2021) |> pull(ideo)
pslp <- psl_party_2021$ideo
audit <- lapply(names(canon), function(nv) {
  p <- readRDS(canon[[nv]]) |> filter(party == "PSL", year == 2018)
  tot <- readRDS(canon[[nv]]) |> filter(year == 2018) |> summarise(v = sum(votes, na.rm = TRUE)) |> pull(v)
  tibble(nivel = nv, ideo = unique(p$ideo), labelled_source = unique(p$ideo_source),
         equals_bolsonaro_candidate = isTRUE(all.equal(unique(p$ideo), bols)),
         equals_psl_party_2021      = isTRUE(all.equal(unique(p$ideo), pslp)),
         wave_2017_scores_psl       = any(ideologia$year == 2017 & ideologia$party.or.pres == "PSL"),
         pct_of_2018_vote           = round(100 * sum(p$votes, na.rm = TRUE) / tot, 2))
}) |> bind_rows()

cat("\n--- [PL-44] PSL-2018 PROVENANCE AUDIT AT THE CANONICAL RUNG ---\n")
print(as.data.frame(audit), row.names = FALSE)
write_csv_safe(audit, file.path("output", "packet_L", "tab_pl44_psl_provenance_audit.csv"))
if (any(audit$labelled_source == "onda" & audit$equals_bolsonaro_candidate & !audit$wave_2017_scores_psl))
  cat(">>> [PL-44] DEFECT CONFIRMED: an imputed candidate score is labelled 'onda'\n",
      ">>> at", paste(audit$nivel[audit$labelled_source == "onda"], collapse = ", "),
      "- covering", paste(sprintf("%.2f%%", audit$pct_of_2018_vote), collapse = " / "),
      "of the 2018 vote.\n")

cat("\n--- [PL-40].2 SHARE OF THE VOTE RESTING ON THE PSL PATCH, V0 RUNG (%) ---\n")
print(as.data.frame(load_tab), row.names = FALSE)
write_csv_safe(load_tab, file.path("output", "packet_L", "tab_pl40_patch_load.csv"))

# =============================================================================
# [PL-39] arms (a) point / (b) drop / (d) party-score, both levels
# =============================================================================
arms <- list("(a) point"       = c(psl_patch$ideo, psl_patch$ideo.se),
             "(b) drop"        = c(NA_real_, NA_real_),
             "(d) party score" = c(psl_party_2021$ideo, psl_party_2021$ideo.se))
res <- list()
for (nv in names(LEVELS)) for (a in names(arms)) {
  p <- build_level(LEVELS[[nv]], arms[[a]][1], arms[[a]][2], a)
  res[[paste(nv,a)]] <- idx_of(p) |>
    summarise(across(c(y_bar, P_dalton, P_center), ~ round(mean(.x), 4)), .by = year) |>
    mutate(nivel = nv, arm = a, .before = 1) |> arrange(year)
  if (a == "(a) point") saveRDS(idx_of(p), paste0("dalton_panel_", nv, "_sens.rds"))
}
res <- bind_rows(res)
cat("\n--- [PL-39] INDEX MEANS BY ARM (2018 is the only year that can move) ---\n")
print(as.data.frame(res |> filter(year == 2018) |> arrange(nivel, arm)), row.names = FALSE)
write_csv_safe(res, file.path("output", "packet_L", "tab_pl40_arms.csv"))

# =============================================================================
# [PL-39](c) BREAK-EVEN — presidential level, where a conclusion exists
# -----------------------------------------------------------------------------
# Main specification, from 07_regression_inference.R:
#   feols(delta_P_dalton ~ delta_EPW + ln_gdp_pc + ln_pop + tradable_emp_share
#         | state^year), clustered by mesoregion_code^year.
# delta_P_dalton is the common-2010-base difference. Only 2018 moves with the
# PSL score, so delta_EPW and every control are held EXACTLY fixed, taken from
# df_estimation_v7.rds. We vary only the outcome.
# =============================================================================
df0   <- readRDS("df_estimation_v7.rds")
ctrl  <- c("ln_gdp_pc", "ln_pop", "tradable_emp_share")
zvars <- c("delta_P_dalton", "delta_EPW", ctrl)

fit_for <- function(y_psl) {
  d  <- idx_of(build_level(LEVELS$presidencial, y_psl, psl_patch$ideo.se, "x"))
  b  <- d |> filter(year == 2010) |> select(microregion_code, P0 = P_dalton)
  dd <- d |> filter(year != 2010) |> left_join(b, by = "microregion_code") |>
        transmute(microregion_code = as.character(microregion_code), year,
                  delta_P_dalton_new = P_dalton - P0)
  # microregion_code is <character> in the vote panels and <integer> in the
  # estimation frame; coerce on the frame's side so the join key types agree.
  m <- df0 |>
    mutate(microregion_code = as.character(microregion_code)) |>
    left_join(dd, by = c("microregion_code", "year")) |>
    mutate(delta_P_dalton = delta_P_dalton_new) |>
    filter(!is.na(delta_P_dalton)) |>
    mutate(across(all_of(zvars), ~ as.numeric(scale(.))))
  fe <- feols(delta_P_dalton ~ delta_EPW + ln_gdp_pc + ln_pop + tradable_emp_share |
                state^year, data = m, cluster = ~ mesoregion_code^year)
  ct <- coeftable(fe)["delta_EPW", ]
  c(beta = unname(ct[1]), se = unname(ct[2]), t = unname(ct[3]), p = unname(ct[4]))
}

cat("\n--- [PL-39](c) BREAK-EVEN, presidential, delta_EPW on delta_P_dalton ---\n")
grid <- seq(-1, 1, by = 0.1)
be <- lapply(grid, function(y) c(psl_ideo = y, fit_for(y))) |> bind_rows() |> as_tibble()
be <- be |> mutate(sig05 = p < 0.05)
print(as.data.frame(be |> mutate(across(c(beta,se,t,p), ~round(.x,4)))), row.names = FALSE)
write_csv_safe(be, file.path("output", "packet_L", "tab_pl40_breakeven.csv"))

obs <- fit_for(psl_patch$ideo)
cat(sprintf("\nAt the status-quo patch (ideo = %.3f): beta = %.4f, t = %.2f, p = %.4f\n",
            psl_patch$ideo, obs["beta"], obs["t"], obs["p"]))
cat(sprintf("At the PSL party score  (ideo = %.3f): beta = %.4f, t = %.2f, p = %.4f\n",
            psl_party_2021$ideo, fit_for(psl_party_2021$ideo)["beta"],
            fit_for(psl_party_2021$ideo)["t"], fit_for(psl_party_2021$ideo)["p"]))

sgn <- sign(obs["beta"])
flip_sign <- be |> filter(sign(beta) != sgn)
flip_sig  <- be |> filter(!sig05)
cat("\nSign of beta flips at psl_ideo in:",
    if (nrow(flip_sign) == 0) "NOWHERE on [-1, 1]" else paste(range(flip_sign$psl_ideo), collapse = " .. "), "\n")
cat("Significance (p<0.05) lost at psl_ideo in:",
    if (nrow(flip_sig) == 0) "NOWHERE on [-1, 1]" else paste(range(flip_sig$psl_ideo), collapse = " .. "), "\n")
cat("\nObserved BLS score range in the 2021 wave: ",
    sprintf("%.3f to %.3f", min(ideologia$ideo[ideologia$year==2021]),
            max(ideologia$ideo[ideologia$year==2021])), "\n")
