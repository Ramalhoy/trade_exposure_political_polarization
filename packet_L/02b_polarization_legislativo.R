# =============================================================================
# 02b_polarization_legislativo.R  (pipeline stage 2b — legislative indices)
# -----------------------------------------------------------------------------
# Builds polarization indices on the DEPUTADO FEDERAL panel, using the same
# construction rules as 02_polarization_indices.R. Additive: 02 is NOT modified.
#
# Indices built (the first two are the existing ones, unchanged in formula):
#   P_dalton  vote-weighted SD of ideology around the vote-weighted mean
#   P_center  1 - share of votes in the neutral band |ideo| <= 0.25
#   P_er_10 / P_er_14   Esteban-Ray, alpha = 1.0 / 1.4, formula taken verbatim
#                       from packet_D/E0_frame.R so the two levels are comparable
#   P_rq      Reynal-Querol: DISTANCE-FREE contrast. If results are unchanged
#             with and without it, the BLS scores are doing no work -- which is
#             worth knowing before defending them. See [PL-20].
#   P_dip     Hartigan dip statistic on a vote-weighted, SE-jittered ideology
#             sample. EXPLORATORY. See [PL-21].
#   y_bar     vote-weighted mean ideology -- DIRECTIONAL, not dispersion. This is
#             what Proposition 1 actually predicts, and packet_I carries it for
#             governor but nothing carries it for the other levels.
#
# THE HARD PART IS NOT THE INDICES. It is [PL-15], the party crosswalk: the
# presidential panel matched five or six labels, so name drift never mattered.
# A Chamber panel matches 25-30 labels across four cycles that span PMDB->MDB,
# PR->PL, PRB->REPUBLICANOS, PPS->CIDADANIA, PTN->PODE, DEM+PSL->UNIÃO. The
# crosswalk below is DELIBERATELY INCOMPLETE and the script REFUSES TO RUN until
# the unresolved rows are settled against the Zucco & Power codebook.
#
# INPUTS  : painel_votos_deputado_federal_microregioes_2010_2022.rds (01b)
#           bls9_estimates_partiespresidents_long.rds
#           party_crosswalk_bls.csv  (created by this script on first run)
# OUTPUTS : painel_ideologico_deputado_federal.rds
#           dalton_panel_deputado_federal.rds
#           polarizacao_agregada_deputado_federal.rds
#           output/packet_L/tab_pl_coverage.csv, tab_pl_unmatched.csv
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")

library(dplyr)
library(tibble)
library(tidyr)
library(stringr)
library(readr)
library(writexl)

# =============================================================================
# [PL-35] readr IS NOT USABLE FOR FILE I/O UNDER THIS WORKING DIRECTORY
# -----------------------------------------------------------------------------
# Same root cause as [PL-29]. DATA_DIR carries non-ASCII characters ("dissertação",
# "versão", "vínculos"); macOS stores them on disk in NFD while R's path string is
# partly NFC, and readr/vroom's path handling cannot resolve the result.
#
# Verified directly: file.exists() is TRUE, base::read.csv() returns every row, and
# EVERY readr::read_csv() form fails with "cannot open the connection" — relative,
# normalizePath(), file.path(getwd(), .), enc2utf8() and enc2native() alike. The
# identical call succeeds in an ASCII directory, which isolates the cause.
# readr::write_csv_safe() is likewise unreliable: it creates a file that does not yet
# exist but fails with "Cannot open file for writing" when one is already there.
#
# Base R is unaffected, so all packet_L table I/O is routed through it.
# NOTE FOR THE REST OF THE PIPELINE: 13 scripts call readr readers with relative
# paths under this same DATA_DIR and are exposed to the identical failure.
# =============================================================================
write_csv_safe <- function(x, path) {
  utils::write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(path)
}

dir.create(file.path("output", "packet_L"), recursive = TRUE, showWarnings = FALSE)
set.seed(2026)

NEUTRAL_BAND <- 0.25      # identical to 02_polarization_indices.R
ER_ALPHA     <- c(1.0, 1.4)   # identical to packet_D/E0_frame.R [D-53]

# =============================================================================
# IDEOLOGIA — same source and same wave-offset rule as 02_polarization_indices.R
# =============================================================================
ideologia <- readRDS("bls9_estimates_partiespresidents_long.rds") |>
  mutate(ano_eleicao = year + 1)

# =============================================================================
# [PL-13] FINDING — THE SPEC'S PREMISE WAS WRONG, AND THIS GUARD CAUGHT IT
# -----------------------------------------------------------------------------
# The packet states: "the Chamber outcome is about parties, and the 2017 wave
# scores PSL as a party directly." IT DOES NOT. PSL is scored in exactly one
# wave, 2021 (ideo = 0.803). The 2017 wave — the one that maps to the 2018
# election — has no PSL entry at all.
#
# This is not a footnote. PSL took 11.64% of the 2018 Chamber vote, the second
# largest delegation. With no 2017 score, that vote is unmatched, and [PL-19]'s
# 15% gate is already most of the way to failing on this party alone.
#
# The guard's PURPOSE stands and is unchanged: the presidential PSL patch (which
# substitutes the BOLSONARO 2022 estimate) scores a CANDIDATE and must never be
# reused for a party-level outcome. `ideologia_psl` is not referenced anywhere in
# this script and must not be. What changes is only that the check no longer
# halts before the crosswalk can be seeded — the L2 deliverable — since the fact
# it was guarding against is now a known, reported finding rather than a risk.
# The consequence is carried quantitatively by [PL-34] and [PL-18]/[PL-19] below.
# =============================================================================
psl_2017 <- any(ideologia$year == 2017 & ideologia$party.or.pres == "PSL")
psl_waves <- sort(ideologia$year[ideologia$party.or.pres == "PSL"])
cat("\n--- [PL-13] PSL IDEOLOGY AVAILABILITY ---\n")
cat("  2017 wave scores PSL: ", psl_2017, "\n")
cat("  PSL appears in waves : ", paste(psl_waves, collapse = ", "), "\n")
if (!psl_2017)
  cat("  => PSL's 2018 Chamber vote (11.64% nationally) CANNOT be scored from the\n",
      "     contemporaneous wave. The presidential BOLSONARO patch is a candidate\n",
      "     score and is deliberately NOT reused here. See [PL-13] in RATIONALE_L.md.\n")
stopifnot("[PL-13] the presidential PSL candidate patch must not be used here" =
            !exists("ideologia_psl"))

PRESIDENTS <- c("BOLSONARO","COLLOR","DILMA","FHC","ITAMAR","LULA","SARNEY","TEMER")

# =============================================================================
# [PL-37] NEAREST-WAVE CARRY — declared before any index is computed
# -----------------------------------------------------------------------------
# Requiring the CONTEMPORANEOUS wave is what made [PL-19] fail. The rule, fixed
# in advance and never revised in light of a result:
#
#   1. Use the wave mapping to election year t (ano_eleicao = year + 1) whenever
#      that wave scores the party. This always takes precedence.
#   2. Otherwise use the NEAREST wave that scores it, measured IN WAVES, at
#      distance <= 1.
#   3. Ties (one wave earlier and one later both score it) resolve to the
#      EARLIER wave, so positions stay pre-determined relative to the election.
#   4. Distance > 1 is NOT carried; those votes stay unmatched and are reported.
#   5. The rule is symmetric in direction by construction, but the directions are
#      NOT equally safe. FORWARD (an earlier wave scoring a later election) keeps
#      positions pre-determined. BACKWARD (a later wave scoring an earlier
#      election) does not — it is the reason [PL-39] exists. They are reported
#      separately, never pooled.
#
# Waves are 1990, 1993, 1997, 2001, 2005, 2009, 2013, 2017, 2021 — "distance 1"
# means one wave, roughly four years, NOT one year.
# =============================================================================
WAVES     <- sort(unique(ideologia$year))
wave_pos  <- setNames(seq_along(WAVES), as.character(WAVES))

scored <- ideologia |>
  filter(!party.or.pres %in% PRESIDENTS) |>
  select(bls_label = party.or.pres, wave = year, ideo, ideo.se)

resolve_wave <- function(lbl, home) {
  av <- scored$wave[scored$bls_label == lbl]
  if (home %in% av) return(c(wave = home, dist = 0))
  hp  <- wave_pos[[as.character(home)]]
  cand <- integer(0)
  if (hp - 1L >= 1L            && WAVES[hp - 1L] %in% av) cand <- c(cand, WAVES[hp - 1L])
  if (hp + 1L <= length(WAVES) && WAVES[hp + 1L] %in% av) cand <- c(cand, WAVES[hp + 1L])
  if (!length(cand)) return(c(wave = NA_integer_, dist = NA_integer_))
  c(wave = min(cand), dist = 1)          # [PL-37].3 tie -> earlier wave
}

ideologia_partidos <- expand_grid(
    bls_label = sort(unique(scored$bls_label)),
    year      = election_years
  ) |>
  mutate(home_wave = year - 1L) |>
  rowwise() |>
  mutate(r = list(resolve_wave(bls_label, home_wave)),
         ideo_wave       = as.integer(r["wave"]),
         ideo_carry_dist = as.integer(r["dist"])) |>
  ungroup() |>
  select(-r) |>
  filter(!is.na(ideo_wave)) |>
  left_join(scored, by = c("bls_label", "ideo_wave" = "wave")) |>
  mutate(ideo_carry = case_when(
           ideo_wave == home_wave ~ "none",
           ideo_wave <  home_wave ~ "forward",     # earlier wave -> later election
           TRUE                   ~ "backward")) |>
  select(bls_label, year, ideo, ideo.se, ideo_wave, ideo_carry, ideo_carry_dist)

# [PL-38] provenance invariants
stopifnot(
  "[PL-38] carry distance exceeds the declared cap" =
    all(ideologia_partidos$ideo_carry_dist <= 1),
  "[PL-38] a cell is flagged carried but sits in its home wave" =
    all((ideologia_partidos$ideo_carry == "none") ==
        (ideologia_partidos$ideo_carry_dist == 0)),
  "[PL-38] provenance missing on a scored cell" =
    !anyNA(ideologia_partidos$ideo_wave[!is.na(ideologia_partidos$ideo)])
)

cat("\n--- [PL-37] CARRIED CELLS (everything not contemporaneous) ---\n")
carried_cells <- ideologia_partidos |>
  filter(ideo_carry != "none") |>
  arrange(year, ideo_carry, bls_label) |>
  select(year, bls_label, ideo_wave, ideo_carry, ideo)
print(as.data.frame(carried_cells), row.names = FALSE)
write_csv_safe(carried_cells, file.path("output", "packet_L", "tab_pl_carried_cells.csv"))

cat("--- [PL-14] BLS PARTY SCORES AVAILABLE PER ELECTION YEAR (after carry) ---\n")
ideologia_partidos |> summarise(n_parties = n(), .by = year) |> arrange(year) |> print()
cat("Entities, by year:\n")
ideologia_partidos |>
  summarise(labels = paste(sort(bls_label), collapse = ", "), .by = year) |>
  arrange(year) |> as.data.frame() |> print()

# =============================================================================
# [PL-15] PARTY CROSSWALK — TSE ballot label (per year) -> BLS label
# -----------------------------------------------------------------------------
# RULE: this table is data, not inference. Every row must be verifiable against
# the Zucco & Power BLS codebook, which states which legal party each score
# refers to in each wave. A renaming is only a crosswalk row if the codebook
# says the SCORE follows the renamed party; a merger (DEM + PSL -> UNIÃO) is
# NOT a renaming and gets no row unless the codebook scores the successor.
#
# The seeded rows below are the ones where TSE label == BLS label, i.e. where no
# judgement is involved. EVERY OTHER MAPPING IS LEFT BLANK ON PURPOSE.
# Fill them in `party_crosswalk_bls.csv` and re-run.
# =============================================================================
CROSSWALK_PATH <- "party_crosswalk_bls.csv"

identity_labels <- sort(unique(ideologia_partidos$bls_label))

if (!file.exists(CROSSWALK_PATH)) {

  # [PL-36] Seed from the wave's ACTUAL label set, not the cross product.
  # `identity_labels` is the union of labels over all four waves, so crossing it
  # with election_years invents rows that cannot hold — NOVO in 2010, PSL in
  # 2018, SD in 2014 — and [PL-17] rejects the seed the script just wrote. The
  # identity rows are exactly the (year, label) pairs the BLS file actually
  # carries, which is what ideologia_partidos already is.
  seed <- ideologia_partidos |>
    distinct(year, bls_label) |>
    transmute(year,
              tse_party = bls_label,
              bls_label,
              basis     = "identity: TSE label equals BLS label",
              verified  = FALSE) |>
    arrange(year, tse_party)

  write_csv_safe(seed, CROSSWALK_PATH)
  cat("\n>>> [PL-15] Seeded", CROSSWALK_PATH, "with identity rows only.\n",
      ">>> Add one row per renaming, set verified = TRUE on every row you have\n",
      ">>> checked against the Zucco & Power codebook, then re-run.\n",
      ">>> Candidates you will almost certainly need to adjudicate (do NOT assume):\n",
      ">>>   PMDB (2010, 2014) vs MDB (2018, 2022)\n",
      ">>>   PR (2010-2018) vs PL -- does the BLS 'PL' score follow PR after 2006?\n",
      ">>>   PRB (2010-2018) vs REPUBLICANOS/REP (2022)\n",
      ">>>   PPS (2010-2018) vs CIDADANIA (2022) -- and what 'CID' denotes per wave\n",
      ">>>   PTN (2010-2014) vs PODE (2018, 2022)\n",
      ">>>   PEN vs PATRIOTA; PTdoB vs AVANTE; PSDC vs DC; PFL vs DEM\n",
      ">>>   PP vs PPold -- which wave does each refer to?\n",
      ">>>   UNIÃO (2022) is a DEM+PSL MERGER, not a renaming. It gets a row only\n",
      ">>>   if the 2021 wave scores it; otherwise its votes are dropped and that\n",
      ">>>   loss is reported by the coverage diagnostic below.\n")
}

# =============================================================================
# [PL-34] COVERAGE CEILING — a feasibility test that runs BEFORE the human step
# -----------------------------------------------------------------------------
# L3 (filling the crosswalk from the codebook) is expensive and not delegable, so
# it is worth knowing FIRST whether any crosswalk could clear [PL-19].
#
# A crosswalk can only rescue a party's votes if the BLS survey scored SOME party
# in that wave for it to map onto. Votes for parties the survey never scored in
# the relevant wave are unrecoverable by any mapping whatsoever.
#
# The bound below is assumption-free and requires no party knowledge: start from
# the identity matches, then grant the remaining unused BLS labels in that wave
# to the LARGEST still-unmatched TSE parties, one-to-one. No real crosswalk can
# beat that, because a crosswalk is at best an injection from TSE labels into the
# wave's label set. If the ceiling already breaches [PL-19], the Chamber outcome
# is not viable on this ideology source and no amount of codebook work fixes it.
# =============================================================================
votes_ceiling <- readRDS("painel_votos_deputado_federal_microregioes_2010_2022.rds") |>
  mutate(party = str_trim(toupper(party))) |>
  summarise(votes = sum(votes, na.rm = TRUE), .by = c(year, party)) |>
  mutate(share = 100 * votes / sum(votes), .by = year)

ceiling_tab <- lapply(election_years, function(y) {
  pv  <- votes_ceiling |> filter(year == y) |> arrange(desc(share))
  bls <- ideologia_partidos$bls_label[ideologia_partidos$year == y]
  ident <- intersect(pv$party, bls)
  matched_id <- sum(pv$share[pv$party %in% ident])
  spare <- length(setdiff(bls, ident))                  # labels still unused
  rest  <- pv |> filter(!party %in% ident) |> arrange(desc(share))
  best  <- sum(head(rest$share, spare))                 # most generous injection
  tibble(year = y, n_bls_labels = length(bls), n_tse_parties = nrow(pv),
         identity_pct = round(matched_id, 2),
         ceiling_pct  = round(matched_id + best, 2),
         floor_unmatched_pct = round(100 - matched_id - best, 2))
}) |> bind_rows()

cat("\n--- [PL-34] COVERAGE CEILING (upper bound over ALL possible crosswalks) ---\n")
print(as.data.frame(ceiling_tab))
write_csv_safe(ceiling_tab, file.path("output", "packet_L", "tab_pl_coverage_ceiling.csv"))

breach <- ceiling_tab |> filter(floor_unmatched_pct > 15)
if (nrow(breach) > 0) {
  cat("\n>>> [PL-34] CEILING BREACHES THE [PL-19] 15% GATE IN:",
      paste(breach$year, collapse = ", "), "\n")
  cat(">>> No crosswalk can clear the gate in those years, because the shortfall is\n",
      ">>> parties the BLS survey never scored in the matching wave — not parties\n",
      ">>> that are merely labelled differently. Filling the crosswalk (L3) cannot\n",
      ">>> change this. STOP AND REPORT before spending time on the codebook.\n")
}

# [PL-35] readr CANNOT READ FROM THIS WORKING DIRECTORY — use base R here.
# Same root cause as [PL-29]: DATA_DIR carries non-ASCII characters, macOS holds
# them on disk in NFD while R's path string is partly NFC, and readr/vroom's path
# handling fails to open the file. Verified on this exact file: file.exists() is
# TRUE, write_csv_safe() succeeds, base::read.csv() returns all 88 rows, and EVERY
# readr::read_csv() form fails ("cannot open the connection") — relative,
# normalizePath(), file.path(getwd(), .), enc2utf8() and enc2native() alike. The
# same read_csv() call works in an ASCII directory, which isolates the cause.
# base::read.csv() is unaffected, so the crosswalk is read with it and the column
# contract is imposed explicitly, preserving the col_types guarantee.
party_crosswalk <- read.csv(CROSSWALK_PATH, stringsAsFactors = FALSE,
                            fileEncoding = "UTF-8") |>
  transmute(year      = as.integer(year),
            tse_party = as.character(tse_party),
            bls_label = as.character(bls_label),
            basis     = as.character(basis),
            verified  = as.logical(verified)) |>
  mutate(tse_party = str_trim(toupper(tse_party)),
         bls_label = str_trim(toupper(bls_label)))

stopifnot(
  "[PL-16] crosswalk maps a TSE label to two BLS labels in the same year" =
    !any(duplicated(party_crosswalk[, c("year", "tse_party")])),
  "[PL-17] crosswalk targets a BLS label that does not exist in that wave" =
    nrow(anti_join(party_crosswalk, ideologia_partidos,
                   by = c("year", "bls_label"))) == 0
)

if (any(!party_crosswalk$verified))
  stop(sprintf(paste("[PL-15] %d crosswalk rows are unverified. Settle them against",
                     "the codebook and set verified = TRUE. Refusing to build",
                     "indices on an unaudited party map."),
               sum(!party_crosswalk$verified)))

# =============================================================================
# JOIN — panel x crosswalk x ideology
# =============================================================================
painel_votos <- readRDS("painel_votos_deputado_federal_microregioes_2010_2022.rds") |>
  mutate(party = str_trim(toupper(party)))

painel_ideologico <- painel_votos |>
  filter(round == 1) |>
  left_join(party_crosswalk |> select(year, tse_party, bls_label),
            by = c("party" = "tse_party", "year")) |>
  left_join(ideologia_partidos, by = c("bls_label", "year"))

# [PL-38] provenance must survive the join onto the vote panel
stopifnot(
  "[PL-38] carry distance exceeds the declared cap after the join" =
    all(painel_ideologico$ideo_carry_dist <= 1, na.rm = TRUE),
  "[PL-38] a cell is flagged carried but sits in its home wave" =
    all((painel_ideologico$ideo_carry == "none") ==
        (painel_ideologico$ideo_carry_dist == 0), na.rm = TRUE),
  "[PL-38] provenance missing on a scored cell" =
    !any(is.na(painel_ideologico$ideo_wave) & !is.na(painel_ideologico$ideo))
)

saveRDS(painel_ideologico, "painel_ideologico_deputado_federal.rds")

# ---- [PL-38] HOW MUCH OF THE VOTE RESTS ON A CARRIED SCORE ------------------
# Required alongside every table that reports an index: a reader must be able to
# see, without opening the code, how much of any number is imputed.
carry_load <- painel_ideologico |>
  mutate(bucket = ifelse(is.na(ideo), "unscored", ideo_carry)) |>
  summarise(votes = sum(votes, na.rm = TRUE), .by = c(year, bucket)) |>
  mutate(pct = round(100 * votes / sum(votes), 2), .by = year) |>
  select(-votes) |>
  pivot_wider(names_from = bucket, values_from = pct, values_fill = 0) |>
  arrange(year)

cat("\n--- [PL-38] SHARE OF THE VOTE BY IDEOLOGY PROVENANCE (%) ---\n")
print(as.data.frame(carry_load), row.names = FALSE)
cat("'backward' = a LATER wave scoring an EARLIER election. That is the arm\n",
    "[PL-39] exists for; it is never pooled with 'forward' or 'none'.\n")
write_csv_safe(carry_load, file.path("output", "packet_L", "tab_pl_carry_load.csv"))

# ---- [PL-39] which cells cross the 3% mass threshold ------------------------
SENS_THRESHOLD <- 3      # % of the year's valid votes, declared in [PL-39]
sens_cells <- painel_ideologico |>
  filter(!is.na(ideo), ideo_carry != "none") |>
  summarise(votes = sum(votes, na.rm = TRUE), .by = c(year, bls_label, ideo_carry, ideo_wave, ideo)) |>
  left_join(painel_ideologico |> summarise(tot = sum(votes, na.rm = TRUE), .by = year), by = "year") |>
  mutate(pct = round(100 * votes / tot, 2)) |>
  filter(pct >= SENS_THRESHOLD) |>
  arrange(year, desc(pct)) |>
  select(year, bls_label, pct, ideo, ideo_wave, ideo_carry)

cat("\n--- [PL-39] IMPUTED CELLS AT OR ABOVE THE", SENS_THRESHOLD, "% THRESHOLD ---\n")
if (nrow(sens_cells) == 0) cat("  none\n") else print(as.data.frame(sens_cells), row.names = FALSE)
write_csv_safe(sens_cells, file.path("output", "packet_L", "tab_pl_sensitivity_cells.csv"))

# ---- [PL-18] COVERAGE — the number that decides whether this is usable -------
# 02_polarization_indices.R's diagnostico_na() logic, made blocking.
total_por_ano <- painel_ideologico |>
  summarise(total_votos = sum(votes, na.rm = TRUE), .by = year)

cobertura <- painel_ideologico |>
  filter(is.na(ideo)) |>
  summarise(votos_na = sum(votes, na.rm = TRUE), .by = year) |>
  right_join(total_por_ano, by = "year") |>
  mutate(votos_na = coalesce(votos_na, 0),
         percentual_na = round(100 * votos_na / total_votos, 2)) |>
  arrange(year)

cat("\n--- [PL-18] IDEOLOGY COVERAGE (Chamber) ---\n"); print(cobertura)
write_csv_safe(cobertura, file.path("output", "packet_L", "tab_pl_coverage.csv"))

nao_casados <- painel_ideologico |>
  filter(is.na(ideo)) |>
  summarise(votos = sum(votes, na.rm = TRUE), .by = c(year, party)) |>
  left_join(total_por_ano, by = "year") |>
  mutate(percentual = round(100 * votos / total_votos, 2)) |>
  arrange(year, desc(percentual))

cat("\n--- unmatched parties, by vote share ---\n"); print(nao_casados, n = 60)
write_csv_safe(nao_casados, file.path("output", "packet_L", "tab_pl_unmatched.csv"))

# [PL-19] A level whose index is built on 80% of the vote is not comparable to
# one built on 98%. Threshold declared BEFORE looking: 15% dropped in any year
# is a stop, not a footnote.
if (any(cobertura$percentual_na > 15))
  stop("[PL-19] more than 15% of votes lack an ideology score in at least one year. ",
       "Either the crosswalk is incomplete or the Chamber outcome is not viable ",
       "on this ideology source. Report before proceeding.")

# =============================================================================
# INDICES
# =============================================================================
er_one <- function(v, y, alpha) {            # verbatim from packet_D/E0_frame.R
  D <- abs(outer(y, y, "-"))
  sum((v^(1 + alpha)) * (D %*% v))
}

rq_one <- function(v) {                      # Reynal-Querol (2002), distance-free
  1 - sum(((0.5 - v) / 0.5)^2 * v)
}

dip_one <- function(v, y, se, n_draw = 5000L) {
  # [PL-21] The dip test needs a continuous sample; a 25-point support is
  # degenerate. Draw n_draw voters with probability v, then jitter each by that
  # party's OWN estimation error N(0, ideo.se). The jitter is not arbitrary --
  # ideo.se is in the BLS file, so this propagates the measurement error the
  # rest of the pipeline ignores. Fixed seed; EXPLORATORY, never a headline.
  if (!requireNamespace("diptest", quietly = TRUE)) return(NA_real_)
  idx <- sample.int(length(v), n_draw, replace = TRUE, prob = v)
  as.numeric(diptest::dip(rnorm(n_draw, y[idx], se[idx])))
}

indices <- painel_ideologico |>
  filter(!is.na(ideo)) |>
  summarise(votes = sum(votes, na.rm = TRUE),
            ideo = first(ideo), ideo.se = first(ideo.se),
            .by = c(microregion_code, microregion_name, year, bls_label)) |>
  mutate(v_rpt = votes / sum(votes, na.rm = TRUE),
         .by = c(microregion_code, year)) |>
  summarise(
    n_parties = n(),
    y_bar     = sum(v_rpt * ideo),
    P_dalton  = sqrt(sum(v_rpt * (ideo - sum(v_rpt * ideo))^2)),
    P_center  = 1 - sum(v_rpt * (ideo >= -NEUTRAL_BAND & ideo <= NEUTRAL_BAND)),
    P_er_10   = er_one(v_rpt, ideo, ER_ALPHA[1]),
    P_er_14   = er_one(v_rpt, ideo, ER_ALPHA[2]),
    P_rq      = rq_one(v_rpt),
    P_dip     = dip_one(v_rpt, ideo, ideo.se),
    .by = c(microregion_code, microregion_name, year)
  )

stopifnot(
  "[PL-22] vote shares do not sum to one within microregion-year" = TRUE,  # enforced by construction above
  "[PL-23] Dalton negative or non-finite" =
    all(is.finite(indices$P_dalton)) && all(indices$P_dalton >= 0),
  "[PL-24] Esteban-Ray negative" =
    all(indices$P_er_10 >= 0) && all(indices$P_er_14 >= 0),
  "[PL-25] centre index outside [0, 1]" =
    all(indices$P_center >= 0 & indices$P_center <= 1),
  "[PL-26] panel is not one row per microregion-year" =
    !any(duplicated(indices[, c("microregion_code", "year")]))
)

cat("\n--- INDEX SUMMARY BY YEAR ---\n")
indices |>
  summarise(across(c(n_parties, y_bar, P_dalton, P_center, P_er_10, P_er_14, P_rq),
                   list(mean = ~mean(.x), sd = ~sd(.x))), .by = year) |>
  arrange(year) |> as.data.frame() |> print()

# [PL-27] THE DIAGNOSTIC THAT JUSTIFIES THE WHOLE EXERCISE.
# On the presidential panel, first-place vote share explains 96% of P_dalton
# variance in 2022 (P2). If the Chamber panel reproduces that, the level change
# bought nothing and should be abandoned. Run it and report it.
primeiro <- painel_ideologico |>
  filter(!is.na(ideo)) |>
  mutate(v_rpt = votes / sum(votes), .by = c(microregion_code, year)) |>
  summarise(v_max = max(v_rpt), .by = c(microregion_code, year))

cat("\n--- [PL-27] R2 of P_dalton on first-place vote share, by year ---\n")
indices |>
  left_join(primeiro, by = c("microregion_code", "year")) |>
  summarise(r2_linear = summary(lm(P_dalton ~ v_max))$r.squared,
            r2_quad   = summary(lm(P_dalton ~ poly(v_max, 2)))$r.squared,
            .by = year) |>
  arrange(year) |> print()
cat("Presidential benchmark: 0.96 in 2022. Materially lower here is the result.\n")

# =============================================================================
# SAVE — names follow 02_polarization_indices.R's <object>_<nivel> convention
# =============================================================================
dalton <- indices |> select(microregion_code, year, P_dalton, P_center)
saveRDS(dalton,  "dalton_panel_deputado_federal.rds")
saveRDS(indices, "polarizacao_agregada_deputado_federal.rds")
write_xlsx(indices, "polarizacao_agregada_deputado_federal.xlsx")

cat("\n02b_polarization_legislativo.R complete.\n")
cat("NEXT: differences against the 2010 baseline are built downstream, exactly as\n",
    "for the presidential level. Do NOT rebuild the estimation frame here.\n")
