# =============================================================================
# packet_I/I0_setup.R  —  shared bootstrap for Packet I (ideology-join repair)
# -----------------------------------------------------------------------------
# ADDITIVE. Nothing in the existing pipeline is modified, moved or overwritten.
# `revision/` is LOCKED: this file SOURCES revision/R00_setup.R (read-only use)
# so that Packet I estimates on the identical estimation frame as the published
# Table 3 -- same inputs, same universe rule, same standardisation, same W and
# g_mat. I1 asserts that reproduction before anything else runs.
#
# WHAT THIS FILE ADDS on top of R00:
#   I_DIR(task)            -> output/packet_I/<task>/ (created on demand)
#   votes_pres, votes_gov  -- first-round microregion vote panels
#   bls_waves              -- BLS party scores, presidents' personal scores split off
#   CROSSWALK              -- data/party_crosswalk.csv (versioned artefact, [I-2])
#   sigla_key()            -- accent/case-insensitive join key
#   build_ideo(variant)    -- the ladder: V0 | V1 | V2 | V3   ([I-2],[I-3],[I-4])
#   attach_ideo(), build_index(), build_delta(), coverage_by_year()
#
# THE LADDER ([D-1] discipline: one change per rung)
#   V0  baseline  = exactly what 02_polarization_indices.R does today
#   V1  + crosswalk  (TSE sigla -> BLS label, time-windowed)
#   V2  + carry      (adjacent-wave carry for parties unscored in the own wave)
#   V3  + UNIAO 2022 by succession from DEM and PSL
#
# ONE RULE PRESERVED ACROSS ALL FOUR RUNGS: the PSL-2018 <- BOLSONARO-2021
# imputation that 02 already performs. It is part of the BASELINE, so removing
# or re-deriving it would make V1/V2/V3 multi-change rungs. Under a pure carry
# rule PSL-2018 would instead take the PSL party score of the 2021 wave
# (+0.803 rather than +0.862); that is a substantive change of the same class as
# the PL-2022 question and is OUT OF SCOPE here (P3 anomaly 5). Recorded in
# RATIONALE_I.md [I-3].
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")

suppressPackageStartupMessages(library(stringi))

# ---- [D-6] a UTF-8 locale is a hard prerequisite, not cosmetic ---------------
.lc <- c(Sys.getenv("LC_ALL"), Sys.getenv("LANG"), Sys.getlocale("LC_CTYPE"))
if (!any(grepl("UTF-8", .lc, fixed = TRUE)))
  stop("Packet I requires a UTF-8 locale. Run with:\n",
       "  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 Rscript ...")

I_ROOT <- file.path("output", "packet_I")
dir.create(I_ROOT, showWarnings = FALSE, recursive = TRUE)
I_DIR <- function(task) {
  d <- file.path(I_ROOT, task)
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  d
}

# =============================================================================
# INPUTS
# =============================================================================
votes_pres <- readRDS(paths$votos_pres) |> filter(round == 1)
votes_gov  <- readRDS(paths$votos_gov)  |> filter(round == 1)
VOTE_PANELS <- list(presidencial = votes_pres, governador = votes_gov)

# BLS: eight labels are individual politicians, not parties. They can never be
# matched by a party sigla, and leaving them in the party table would let a
# crosswalk or carry rule reach them by accident.
PRES_LABELS <- c("BOLSONARO", "COLLOR", "DILMA", "FHC", "ITAMAR", "LULA",
                 "SARNEY", "TEMER")
bls_raw <- readRDS(paths$bls9) |> mutate(ano_eleicao = year + 1,
                                         label = as.character(party.or.pres))
bls_waves <- bls_raw |> filter(!label %in% PRES_LABELS) |>
  select(rotulo_bls = label, wave = year, ano_eleicao, ideo)
WAVES <- sort(unique(bls_waves$wave))          # 1990 1993 1997 2001 2005 2009 2013 2017 2021

# The baseline PSL-2018 imputation, kept identical on every rung (see header).
PSL_2018_PATCH <- bls_raw |>
  filter(label == "BOLSONARO", ano_eleicao == 2022) |>
  transmute(rotulo_bls = "PSL", wave = 2017L, ano_eleicao = 2018, ideo)
stopifnot("PSL-2018 patch must be exactly one row" = nrow(PSL_2018_PATCH) == 1)

# =============================================================================
# CROSSWALK ([I-2])
# -----------------------------------------------------------------------------
# readr::read_csv fails on this project's decomposed-UTF8 paths in BOTH
# directions (revision/README, quirk 1), so the versioned artefact is read with
# base read.csv. Joins run on sigla_key(): upper-cased, accent-stripped,
# whitespace-squished, so "PC do B" == "PC DO B" and an NFC/NFD mismatch on
# "UNIAO" cannot silently break a join. Injectivity of the key is asserted.
# =============================================================================
sigla_key <- function(x) {
  x <- stringi::stri_trans_general(as.character(x), "Latin-ASCII")
  gsub("\\s+", " ", trimws(toupper(x)))
}

CROSSWALK <- read.csv(file.path(CODE_DIR, "data", "party_crosswalk.csv"),
                      stringsAsFactors = FALSE, na.strings = "",
                      encoding = "UTF-8") |>
  as_tibble() |>
  mutate(key = sigla_key(sigla_tse),
         vigencia_ini = as.integer(vigencia_ini),
         vigencia_fim = as.integer(vigencia_fim))
stopifnot("crosswalk: duplicated sigla_tse rows" = !any(duplicated(CROSSWALK$key)),
          "crosswalk: sigla_key is not injective over sigla_tse" =
            n_distinct(CROSSWALK$key) == n_distinct(sigla_key(CROSSWALK$sigla_tse)),
          "crosswalk: window ends before it starts" =
            all(CROSSWALK$vigencia_fim >= CROSSWALK$vigencia_ini))

# rotulo_bls must be a label the BLS actually uses (or blank = decided no-match)
.bad <- setdiff(na.omit(unique(CROSSWALK$rotulo_bls)), unique(bls_waves$rotulo_bls))
stopifnot("crosswalk maps to a label absent from the BLS table" = length(.bad) == 0)

# The observed universe: every (sigla, election year) that actually casts a vote
# in either panel. This is the set over which the crosswalk must be complete and
# over which V1/V2/V3 must nest V0.
OBS_SIGLA_YEARS <- bind_rows(
  votes_pres |> transmute(nivel = "presidencial", party, year, votes),
  votes_gov  |> transmute(nivel = "governador",   party, year, votes)) |>
  mutate(key = sigla_key(party)) |>
  group_by(nivel, year, party, key) |>
  summarise(votes = sum(votes, na.rm = TRUE), .groups = "drop")

# [I-2] contract: EVERY observed sigla-year resolves to exactly one crosswalk
# row -- either a BLS label or a recorded decision that no label exists.
.cov <- OBS_SIGLA_YEARS |> distinct(key, year) |>
  left_join(CROSSWALK |> select(key, vigencia_ini, vigencia_fim, rotulo_bls),
            by = "key", relationship = "many-to-many") |>
  filter(is.na(vigencia_ini) | (year >= vigencia_ini & year <= vigencia_fim))
.missing <- OBS_SIGLA_YEARS |> distinct(key, year) |>
  anti_join(.cov |> filter(!is.na(vigencia_ini)), by = c("key", "year"))
.dupes <- .cov |> count(key, year) |> filter(n > 1)
if (nrow(.missing))
  stop("crosswalk does not cover these observed sigla-years:\n",
       paste(sprintf("  %s %d", .missing$key, .missing$year), collapse = "\n"))
if (nrow(.dupes))
  stop("crosswalk windows overlap for:\n",
       paste(sprintf("  %s %d", .dupes$key, .dupes$year), collapse = "\n"))

# =============================================================================
# THE LADDER
# -----------------------------------------------------------------------------
# Every variant returns ONE table: sigla_key x ano_eleicao -> ideo, ideo_source,
# with ideo_source in {onda, carry, fusao}. Rows are only created where a score
# exists; an absent row means "no score", which is what the index build drops.
# =============================================================================

# --- V0: 02_polarization_indices.R, verbatim ---------------------------------
# 02 joins the raw BLS table on party == party.or.pres, so the effective party
# table is "BLS label == TSE sigla" plus the PSL patch. Reproduced here as a
# sigla-keyed table so all four rungs share one downstream code path.
ideo_V0 <- function() {
  bind_rows(bls_waves, PSL_2018_PATCH) |>
    filter(ano_eleicao %in% election_years) |>
    transmute(key = sigla_key(rotulo_bls), ano_eleicao, ideo, ideo_source = "onda")
}

# --- V1: + crosswalk ---------------------------------------------------------
ideo_V1 <- function() {
  cw <- CROSSWALK |> filter(!is.na(rotulo_bls))
  own <- tidyr::crossing(cw |> select(key, rotulo_bls, vigencia_ini, vigencia_fim),
                         ano_eleicao = election_years) |>
    filter(ano_eleicao >= vigencia_ini, ano_eleicao <= vigencia_fim) |>
    left_join(bind_rows(bls_waves, PSL_2018_PATCH) |>
                select(rotulo_bls, ano_eleicao, ideo),
              by = c("rotulo_bls", "ano_eleicao")) |>
    filter(!is.na(ideo)) |>
    transmute(key, ano_eleicao, ideo, ideo_source = "onda")
  # V1 must NEST V0 over the OBSERVED universe: any (sigla, year) that V0 scored
  # and that actually votes must still be scored, at the same value. The
  # crosswalk adds matches; it may never move or remove one. (V0 also emits rows
  # for BLS labels that are not TSE siglas -- REP, CID, PCDOB, PPold, PDC, PRN --
  # which never meet a vote and are irrelevant to the comparison.)
  obs <- OBS_SIGLA_YEARS |> distinct(key, ano_eleicao = year)
  chk <- ideo_V0() |> inner_join(obs, by = c("key", "ano_eleicao")) |>
    left_join(own, by = c("key", "ano_eleicao"), suffix = c("_0", "_1"))
  stopifnot("V1 drops a V0 match" = !anyNA(chk$ideo_1),
            "V1 moves a V0 score" = max(abs(chk$ideo_0 - chk$ideo_1)) < 1e-12)
  own
}

# --- V2: + adjacent-wave carry ([I-3]) ---------------------------------------
# A party scored in a wave ADJACENT to the election's own wave, but not in that
# wave, carries the nearest wave. "Adjacent" = distance 1 in the BLS wave
# sequence; a party scored only in a distant wave (PSTU, 1993 only) is NOT
# carried. Ties (scored in both neighbours) resolve to the EARLIER wave, which
# is the pre-electoral one -- consistent with 02's note that the index is taken
# from the year before the election, and the conservative choice with respect to
# anticipation.
CARRY_MAX_DIST <- 1L
ideo_V2 <- function() {
  base <- ideo_V1()
  cw   <- CROSSWALK |> filter(!is.na(rotulo_bls))
  grid <- tidyr::crossing(cw |> select(key, rotulo_bls, vigencia_ini, vigencia_fim),
                          ano_eleicao = election_years) |>
    filter(ano_eleicao >= vigencia_ini, ano_eleicao <= vigencia_fim) |>
    anti_join(base, by = c("key", "ano_eleicao"))       # only the still-unscored

  wave_of <- function(y) y - 1L
  cand <- grid |>
    mutate(own_wave = wave_of(ano_eleicao),
           own_idx  = match(own_wave, WAVES)) |>
    inner_join(bls_waves |> select(rotulo_bls, wave, ideo_carry = ideo),
               by = "rotulo_bls", relationship = "many-to-many") |>
    mutate(dist = abs(match(wave, WAVES) - own_idx)) |>
    filter(dist >= 1, dist <= CARRY_MAX_DIST) |>
    arrange(key, ano_eleicao, dist, wave) |>            # nearest, then earlier
    distinct(key, ano_eleicao, .keep_all = TRUE) |>
    transmute(key, ano_eleicao, rotulo_bls, own_wave, carry_from_wave = wave,
              ideo = ideo_carry, ideo_source = "carry")

  out <- bind_rows(base, cand |> select(key, ano_eleicao, ideo, ideo_source))
  attr(out, "carry_detail") <- cand
  stopifnot("V2 duplicated a (sigla, year)" =
              !any(duplicated(out |> select(key, ano_eleicao))))
  out
}

# --- V3: + UNIAO 2022 by succession ([I-4]) ----------------------------------
# w_psl is supplied by the caller (I4 reports it under both weighting schemes);
# the default is set only after the [I-4] decision is recorded in RATIONALE_I.
uniao_score <- function(w_psl) {
  d <- bls_waves$ideo[bls_waves$wave == 2021 & bls_waves$rotulo_bls == "DEM"]
  p <- bls_waves$ideo[bls_waves$wave == 2021 & bls_waves$rotulo_bls == "PSL"]
  stopifnot(length(d) == 1, length(p) == 1, w_psl >= 0, w_psl <= 1)
  (1 - w_psl) * d + w_psl * p
}
ideo_V3 <- function(w_psl) {
  bind_rows(ideo_V2(),
            tibble(key = sigla_key("UNIAO"), ano_eleicao = 2022,
                   ideo = uniao_score(w_psl), ideo_source = "fusao"))
}

build_ideo <- function(variant, w_psl = NULL) {
  switch(variant,
         V0 = ideo_V0(), V1 = ideo_V1(), V2 = ideo_V2(),
         V3 = ideo_V3(w_psl %||% stop("V3 needs w_psl ([I-4] decision)")),
         stop("unknown variant: ", variant))
}

# =============================================================================
# INDEX BUILD -- 02_polarization_indices.R formulas, verbatim
# =============================================================================
NEUTRAL_BAND <- 0.25

attach_ideo <- function(votes, ideo_tbl) {
  votes |> mutate(key = sigla_key(party)) |>
    left_join(ideo_tbl, by = c("key", "year" = "ano_eleicao"))
}

build_index <- function(painel_ideologico) {
  painel_ideologico |> filter(!is.na(ideo)) |>
    group_by(microregion_code, year) |>
    mutate(total_votes = sum(votes, na.rm = TRUE),
           v_rpt       = votes / total_votes,
           y_bar       = sum(v_rpt * ideo, na.rm = TRUE)) |>
    summarise(P_dalton = sqrt(sum(v_rpt * (ideo - y_bar)^2, na.rm = TRUE)),
              P_center = first(1 - sum(v_rpt * (ideo >= -NEUTRAL_BAND &
                                                  ideo <=  NEUTRAL_BAND))),
              n_scored = n(), sum_v = sum(v_rpt), .groups = "drop")
}

# 06_panel_consolidation.R: cumulative change from the 2010 baseline.
build_delta <- function(idx) {
  b10 <- idx |> filter(year == 2010) |>
    select(microregion_code, P_dalton_0 = P_dalton, P_center_0 = P_center)
  idx |> filter(year != 2010) |> left_join(b10, by = "microregion_code") |>
    transmute(micro = as.character(microregion_code), year,
              dPD = P_dalton - P_dalton_0, dPN = P_center - P_center_0)
}

coverage_by_year <- function(painel_ideologico) {
  painel_ideologico |> group_by(year) |>
    summarise(total_votes  = sum(votes, na.rm = TRUE),
              scored_votes = sum(votes * !is.na(ideo), na.rm = TRUE),
              pct_scored   = 100 * scored_votes / total_votes,
              n_parties    = n_distinct(party),
              n_scored     = n_distinct(party[!is.na(ideo)]), .groups = "drop")
}

`%||%` <- function(a, b) if (is.null(a)) b else a

cat(sprintf("[I0] setup OK | crosswalk rows = %d (%d mapped, %d decided no-match) | waves = %s\n",
            nrow(CROSSWALK), sum(!is.na(CROSSWALK$rotulo_bls)),
            sum(is.na(CROSSWALK$rotulo_bls)), paste(WAVES, collapse = " ")))
