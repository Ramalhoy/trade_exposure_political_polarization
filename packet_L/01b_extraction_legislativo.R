# =============================================================================
# 01b_extraction_legislativo.R  (pipeline stage 1b — legislative vote panel)
# -----------------------------------------------------------------------------
# Builds the microregion x party vote panel for DEPUTADO FEDERAL, 2010-2022,
# on exactly the conventions of 01_extraction.R BLOCK C. Additive: 01_extraction.R
# is NOT modified.
#
# WHY THIS EXISTS
#   The BLS ideology file (bls9_estimates_partiespresidents_long.rds) carries
#   ~12/19/26/20 PARTY scores for the 2010/2014/2018/2022 elections. The
#   presidential panel uses five or six of them. A Chamber panel uses nearly all,
#   and turns P_dalton / P_er from transformations of the first-place vote share
#   into genuine distributional statistics. See [PL-1] in RATIONALE_L.md.
#
# WHAT IS DIFFERENT FROM BLOCK C, AND WHY
#   [PL-2] PROPORTIONAL RACES HAVE TWO VOTE TYPES. A party's total in a Chamber
#          race is (nominal votes for its candidates) + (legenda votes cast for
#          the party list). BLOCK C reads `vote_mun_zone`, which carries nominal
#          votes ONLY -- correct for a majoritarian race, WRONG here: it would
#          understate brand-voting parties (PT, PSOL) relative to candidate-centric
#          ones. This script reads `party_mun_zone`, which carries both, and
#          reports the legenda share so the choice is auditable.
#   [PL-3] ONE ROUND. Proportional races have no runoff. NR_TURNO is 1 throughout;
#          asserted rather than filtered silently.
#   [PL-4] COALITIONS. Until 2018, proportional coalitions (coligações) pooled
#          seats, not votes: TSE records both nominal and legenda votes against
#          the PARTY the voter selected. Party-level attribution is therefore
#          valid. The coalition label is retained for diagnostics only.
#
# INPUTS  : municipios_ibge.rds (from 01_extraction.R), Passuelo TSE<->IBGE crosswalk
# OUTPUTS : painel_votos_deputado_federal_microregioes_2010_2022.rds / .xlsx
#           output/packet_L/pl_extraction_log.txt
#           output/packet_L/tab_pl_vote_types.csv
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")

library(dplyr)
library(jsonlite)
library(writexl)
library(electionsBR)
library(tidyr)
library(stringr)
library(readr)
library(httr)

# =============================================================================
# [PL-28] TSE CDN BOT FILTER — the request must look like a browser
# -----------------------------------------------------------------------------
# electionsBR:::download_unzip() fetches the archive with httr::GET() and a
# randomised user agent but NO other browser headers. The TSE Akamai edge answers
# such a request with HTTP 403 and a 492-byte HTML error page. electionsBR writes
# that page to the .zip path; unzip() then fails with a mere WARNING ("error 1 in
# extracting from zip file") and the function returns a 0x0 tibble. NOTHING STOPS.
#
# Empirically Accept-Encoding is the discriminating header: with the full set
# below the CDN returns 200; dropping Accept-Encoding alone returns 403.
#
# The fix pre-seeds tempdir() with a correctly fetched archive. download_unzip()
# skips its own download when the file is already there, so electionsBR still
# does ALL of the parsing — only the transport is replaced.
#
# NOTE FOR THE REST OF THE PIPELINE: 01_extraction.R BLOCK C calls elections_tse()
# the same way and has the identical, equally silent, failure mode.
# =============================================================================
TSE_UA <- paste("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
                "AppleWebKit/537.36 (KHTML, like Gecko)",
                "Chrome/125.0.0.0 Safari/537.36")

tse_browser_headers <- function() httr::add_headers(
  `Accept`             = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
  `Accept-Language`    = "pt-BR,pt;q=0.9,en;q=0.8",
  `Accept-Encoding`    = "gzip, deflate, br",          # <- the one that matters
  `sec-ch-ua`          = '"Chromium";v="125", "Not.A/Brand";v="24"',
  `sec-ch-ua-platform` = '"macOS"',
  `Sec-Fetch-Dest`     = "document",
  `Sec-Fetch-Mode`     = "navigate",
  `Sec-Fetch-Site`     = "same-site",
  `Referer`            = "https://dadosabertos.tse.jus.br/"
)

tse_seed_archive <- function(y) {
  fn   <- sprintf("votacao_partido_munzona_%d.zip", y)
  dest <- file.path(tempdir(), fn)
  if (file.exists(dest) && file.size(dest) > 1e6) return(invisible(dest))
  url  <- sprintf(
    "https://cdn.tse.jus.br/estatistica/sead/odsele/votacao_partido_munzona/%s", fn)
  resp <- httr::GET(url, httr::write_disk(dest, overwrite = TRUE),
                    httr::user_agent(TSE_UA), tse_browser_headers())
  if (httr::status_code(resp) != 200)
    stop(sprintf("[PL-28] TSE CDN returned HTTP %d for %s",
                 httr::status_code(resp), fn))
  members <- utils::unzip(dest, list = TRUE)$Name
  if (!any(grepl("\\.csv$", members)))
    stop(sprintf("[PL-28] %s downloaded but carries no CSV member", fn))
  cat(sprintf("[PL-28] %s fetched: %.1f MB, %d members\n",
              fn, file.size(dest) / 1e6, length(members)))
  invisible(dest)
}

# =============================================================================
# [PL-29] NON-ASCII WORKING DIRECTORY — readr cannot open the extracted files
# -----------------------------------------------------------------------------
# electionsBR:::juntaDados() extracts into "./<year>" RELATIVE to the working
# directory and reads each member by bare filename. DATA_DIR contains non-ASCII
# characters ("dissertação", "versão", "vínculos"). macOS stores those on disk in
# NFD while R holds the string in NFC, so the absolute path readr composes mixes
# the two normalisations and file() fails with "cannot open the connection".
# juntaDados() wraps every read in tryCatch(..., error = function(e) NULL), so
# EVERY read returns NULL, rbindlist() yields an empty table, and the function
# returns a 0x0 tibble — again WITHOUT ERROR.
#
# The fix runs the pull with the working directory set to an ASCII-only scratch
# path and restores it afterwards. Nothing else about the call changes.
# =============================================================================
with_ascii_wd <- function(expr) {
  scratch <- file.path(tempdir(), "tse_wd")
  dir.create(scratch, showWarnings = FALSE, recursive = TRUE)
  owd <- getwd()
  on.exit(setwd(owd), add = TRUE)
  setwd(scratch)
  force(expr)
}

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
log_con <- file(file.path("output", "packet_L", "pl_extraction_log.txt"), open = "wt")
sink(log_con, split = TRUE)

cat("=== 01b_extraction_legislativo.R:", format(Sys.time()), "===\n")

CARGO_LEG <- "DEPUTADO FEDERAL"
years     <- election_years          # from 00_config.R: 2010, 2014, 2018, 2022

# =============================================================================
# SHARED MAPPING — identical to 01_extraction.R BLOCK C, reproduced (not sourced)
# so this script runs standalone. Asserted against the stored directory.
# =============================================================================
municipios_ibge <- readRDS("municipios_ibge.rds")

depara <- read.csv(
  "https://raw.githubusercontent.com/yuripassuelo/codigos_mun_tse_ibge/master/relacao_mun_tse_ibge.csv",
  encoding = "UTF-8"
) |>
  transmute(
    municipality_code      = as.character(cd_mun_tse),
    municipality_code_ibge = as.character(cd_mun_ibge)
  )

mapeamento <- depara |>
  mutate(municipality_code = as.character(as.integer(municipality_code))) |>
  left_join(
    municipios_ibge |>
      distinct(municipality_code_ibge, .keep_all = TRUE) |>
      select(municipality_code_ibge, microregion_code, microregion_name),
    by = "municipality_code_ibge"
  )

stopifnot(
  "[PL-5] TSE->IBGE map has duplicate TSE codes" =
    !any(duplicated(mapeamento$municipality_code)),
  "[PL-6] microregion directory does not cover the map" =
    mean(is.na(mapeamento$microregion_code)) < 0.01
)

# =============================================================================
# PULL — party x municipality x zone, both vote types
# electionsBR reads TSE directly: NO BigQuery, NO GCP billing. See [PL-7].
# =============================================================================
pull_party_zone <- function(y) {

  tse_seed_archive(y)                                                  # [PL-28]
  raw <- with_ascii_wd(                                                  # [PL-29]
    elections_tse(year = y, type = "party_mun_zone", br_archive = TRUE)
  )

  # [PL-30] Both failure modes above are SILENT — they yield an empty frame, not
  # an error. Assert non-emptiness before anything else touches `raw`.
  if (nrow(raw) == 0L)
    stop(sprintf("[PL-30] elections_tse returned 0 rows for %d. See [PL-28] (CDN 403) and [PL-29] (non-ASCII wd).", y))

  # [PL-8] Column names drift across TSE vintages. Resolve by pattern, assert,
  # and print what was resolved -- never index positionally.
  nm  <- names(raw)
  pick <- function(pat, label) {
    hit <- nm[str_detect(nm, regex(pat, ignore_case = TRUE))]
    if (length(hit) != 1L)
      stop(sprintf("[PL-8] %s: expected 1 column matching '%s' in %d, got %d (%s)",
                   label, pat, y, length(hit), paste(hit, collapse = ", ")))
    hit
  }
  c_cargo <- pick("^DS_CARGO$|^DESCRICAO_CARGO$", "cargo")
  c_turno <- pick("^NR_TURNO$|^NUM_TURNO$",       "turno")
  c_mun   <- pick("^CD_MUNICIPIO$|^COD_MUN_TSE$", "municipality_code")
  c_munnm <- pick("^NM_MUNICIPIO$|^NOME_MUNICIPIO$", "municipality")
  c_uf    <- pick("^SG_UF$|^SIGLA_UF$",           "state")
  c_part  <- pick("^SG_PARTIDO$|^SIGLA_PARTIDO$", "party")
  # [PL-32] THE VOTE COLUMNS ARE NOT STABLE ACROSS CYCLES, AND THE 2018+ CHANGE
  # IS SEMANTIC, NOT COSMETIC.
  #   2010, 2014:  QT_VOTOS_NOMINAIS            QT_VOTOS_LEGENDA
  #   2018, 2022:  QT_VOTOS_NOMINAIS_VALIDOS    QT_VOTOS_LEGENDA_VALIDOS
  #                QT_VOTOS_NOMINAIS_CONVR_LEG  (2022: QT_VOTOS_NOM_CONVR_LEG_VALIDOS)
  #                QT_TOTAL_VOTOS_LEG_VALIDOS
  #                QT_VOTOS_{LEGENDA,NOMINAIS}_ANUL_SUBJUD  (+ _ANULADOS in 2022)
  #
  # From 2018 TSE splits the count into VALID, CONVERTED and ANNULLED parts.
  # "Converted" are nominal votes for a candidate whose registration failed,
  # which the law reassigns to the party list. The verified identity is
  #     QT_TOTAL_VOTOS_LEG_VALIDOS = QT_VOTOS_LEGENDA_VALIDOS + <converted>
  # (asserted below), so TAKING THE TOTAL AND THE TWO PARTS WOULD DOUBLE COUNT.
  #
  # DECISION: the index is a vote-SHARE statistic, so it is built on VALID votes,
  # which is exactly what 2010/2014's two columns already are. Annulled votes are
  # excluded — they are 0 in 2018 and ~0.9M of 109M (0.85%) in 2022.
  #   votes_nominal := QT_VOTOS_NOMINAIS[_VALIDOS]
  #   votes_legenda := QT_VOTOS_LEGENDA | QT_TOTAL_VOTOS_LEG_VALIDOS
  # The alternations below still resolve to EXACTLY ONE column per year, so the
  # [PL-8] guard keeps its force.
  c_nom   <- pick("^QT_VOTOS_NOMINAIS$|^QT_VOTOS_NOMINAIS_VALIDOS$",  "votos_nominais")
  c_leg   <- pick("^QT_VOTOS_LEGENDA$|^QT_TOTAL_VOTOS_LEG_VALIDOS$",  "votos_legenda")

  # [PL-32] assert the decomposition identity wherever the parts are present,
  # so the "total" column can never quietly stop being the sum of its parts.
  c_legv  <- nm[str_detect(nm, regex("^QT_VOTOS_LEGENDA_VALIDOS$", ignore_case = TRUE))]
  c_conv  <- nm[str_detect(nm, regex("^QT_VOTOS_NOMINAIS_CONVR_LEG$|^QT_VOTOS_NOM_CONVR_LEG_VALIDOS$",
                                     ignore_case = TRUE))]
  if (length(c_legv) == 1L && length(c_conv) == 1L) {
    bad <- sum(raw[[c_leg]] != raw[[c_legv]] + raw[[c_conv]], na.rm = TRUE)
    if (bad > 0)
      stop(sprintf("[PL-32] %d rows in %d where total legenda != valid + converted", bad, y))
    cat(sprintf("[%d] [PL-32] legenda decomposition identity holds (%s = %s + %s)\n",
                y, c_leg, c_legv, c_conv))
  }
  c_zona  <- pick("^NR_ZONA$|^NUM_ZONA$",         "zona")
  c_colig <- nm[str_detect(nm, regex("^NM_COLIGACAO$|^NOME_COLIGACAO$", ignore_case = TRUE))]

  cat(sprintf("\n[%d] resolved columns: cargo=%s turno=%s mun=%s party=%s nom=%s leg=%s\n",
              y, c_cargo, c_turno, c_mun, c_part, c_nom, c_leg))

  # [PL-31] TSE re-published the historical archives with TITLE-CASE cargo
  # labels ("Deputado Federal"), not the upper case of older vintages — note
  # 01_extraction.R BLOCK C matches "Presidente", also title case. Match on a
  # normalised string, and assert below that the filter selected rows, so a
  # future label change can never silently produce an empty panel.
  out <- raw |>
    filter(toupper(str_trim(.data[[c_cargo]])) == CARGO_LEG) |>
    transmute(
      year              = y,
      round             = as.integer(.data[[c_turno]]),
      municipality      = as.character(.data[[c_munnm]]),
      municipality_code = as.character(.data[[c_mun]]),
      state             = .data[[c_uf]],
      party             = str_trim(toupper(.data[[c_part]])),
      zona              = as.integer(.data[[c_zona]]),
      votes_nominal     = as.numeric(.data[[c_nom]]),
      votes_legenda     = as.numeric(.data[[c_leg]]),
      coligacao         = if (length(c_colig) == 1L)
                            as.character(.data[[c_colig]]) else NA_character_
    )

  if (nrow(out) == 0L)
    stop(sprintf("[PL-31] no rows for cargo '%s' in %d. Labels present: %s",
                 CARGO_LEG, y, paste(sort(unique(raw[[c_cargo]])), collapse = ", ")))

  # [PL-3] proportional races have exactly one round
  stopifnot("[PL-3] more than one round in a proportional race" =
              all(out$round == 1L))

  # [PL-9]/[PL-33] party x municipality x zone is the natural key. TSE can emit
  # the SAME party twice in one mun x zona under two agremiação records — in 2018
  # a "Coligação" row plus a "Partido isolado" row, in 2022 two records with
  # different SQ_COLIGACAO. Summing blindly double-counts legenda; keeping one
  # record drops nominal votes. The two years behave DIFFERENTLY, so the rule
  # below was read off the data rather than assumed:
  #
  #   NOMINAL  are disjoint candidate tallies on each record -> SUM, always.
  #   LEGENDA  is a PARTY-level total for the mun x zona. Verified directly:
  #            within a 2018 coalition, legenda DIFFERS across member parties in
  #            94.3% of coalition x mun x zona groups (the 5.7% of ties are almost
  #            all zeros — 882 non-zero out of 43,380). So legenda is not a shared
  #            coalition figure and [PL-4]'s party-level attribution holds.
  #            Where one party carries two records, 2018 REPEATS the identical
  #            number on both (74 keys, all non-zero, 7,048 votes) while 2022
  #            SPLITS disjoint tallies across them (2,094 keys, 21,128 votes).
  #            Hence: count a replicated value once, sum genuinely distinct ones.
  #
  # Scale: affected votes are 0.007% (2018) and 0.019% (2022) of the year's valid
  # total. This is a correctness fix, not something any result turns on.
  dup <- out |> count(municipality_code, zona, party) |> filter(n > 1L)
  if (nrow(dup) > 0) {
    leg_before <- sum(out$votes_legenda, na.rm = TRUE)
    out <- out |>
      summarise(
        round         = first(round),
        municipality  = first(municipality),
        state         = first(state),
        votes_nominal = sum(votes_nominal, na.rm = TRUE),
        votes_legenda = {
          nz <- unique(votes_legenda[!is.na(votes_legenda) & votes_legenda > 0])
          if (length(nz) <= 1L) max(votes_legenda, na.rm = TRUE)
          else                  sum(votes_legenda, na.rm = TRUE)
        },
        coligacao     = paste(sort(unique(coligacao)), collapse = " | "),
        .by = c(year, municipality_code, zona, party)
      )
    cat(sprintf("[%d] [PL-33] %d party x mun x zona keys carried multiple agremiação records; collapsed (legenda %s -> %s)\n",
                y, nrow(dup), format(leg_before, big.mark = ","),
                format(sum(out$votes_legenda, na.rm = TRUE), big.mark = ",")))
  }

  stopifnot("[PL-9] party x mun x zona still duplicated after the [PL-33] collapse" =
              !any(duplicated(out[, c("municipality_code", "zona", "party")])))

  out
}

panel_zone <- lapply(years, pull_party_zone) |> bind_rows()

# ---- [PL-2] how much of the vote is legenda? --------------------------------
vote_types <- panel_zone |>
  summarise(nominal = sum(votes_nominal, na.rm = TRUE),
            legenda = sum(votes_legenda, na.rm = TRUE), .by = year) |>
  mutate(total = nominal + legenda,
         pct_legenda = round(100 * legenda / total, 2)) |>
  arrange(year)
cat("\n--- [PL-2] VOTE COMPOSITION BY YEAR ---\n"); print(vote_types)
cat("If pct_legenda is non-trivial (it is normally 3-8%), reading `vote_mun_zone`\n",
    "as BLOCK C does would have dropped exactly this, unevenly across parties.\n")
write_csv_safe(vote_types, file.path("output", "packet_L", "tab_pl_vote_types.csv"))

# =============================================================================
# AGGREGATE — zone -> municipality -> microregion (BLOCK C order preserved)
# =============================================================================
panel_mun <- panel_zone |>
  summarise(votes = sum(votes_nominal + votes_legenda, na.rm = TRUE),
            votes_nominal = sum(votes_nominal, na.rm = TRUE),
            votes_legenda = sum(votes_legenda, na.rm = TRUE),
            .by = c(year, round, municipality_code, municipality, state, party)) |>
  filter(!state %in% c("ZZ", "VT")) |>                      # remove exterior
  mutate(municipality_code = as.character(as.integer(municipality_code)))

panel_micro <- panel_mun |>
  left_join(mapeamento, by = "municipality_code") |>
  summarise(votes         = sum(votes, na.rm = TRUE),
            votes_nominal = sum(votes_nominal, na.rm = TRUE),
            votes_legenda = sum(votes_legenda, na.rm = TRUE),
            .by = c(year, round, microregion_code, microregion_name, party, state))

# ---- diagnostics, in BLOCK C's format ---------------------------------------
lost <- panel_mun |>
  left_join(mapeamento, by = "municipality_code") |>
  filter(is.na(microregion_code)) |>
  summarise(votos_perdidos = sum(votes)) |> pull(votos_perdidos)

cat(sprintf("\n[%s] micros: %d | vote rows: %d | votes w/o microregion: %s\n",
            CARGO_LEG, n_distinct(panel_micro$microregion_code),
            nrow(panel_micro), format(lost, big.mark = ",")))

cat("\n--- PARTIES PER YEAR (the point of the exercise) ---\n")
panel_micro |>
  summarise(n_parties = n_distinct(party),
            total_votes = sum(votes), .by = year) |>
  arrange(year) |> print()
cat("Presidential comparison: 5-8 parties per year. See [PL-1].\n")

# [PL-10] Anchors. Chamber turnout is ~100-110M valid votes in 2018/2022 and
# ~95-100M in 2010/2014; microregion count must match the presidential panel.
stopifnot(
  "[PL-10] microregion count does not match the presidential panel" =
    n_distinct(panel_micro$microregion_code) ==
    n_distinct(readRDS("painel_votos_presidenciais_microregioes_2010_2022.rds")$microregion_code),
  "[PL-11] unmapped votes exceed 0.5% of the total" =
    lost / sum(panel_mun$votes) < 0.005
)

saveRDS(panel_micro, "painel_votos_deputado_federal_microregioes_2010_2022.rds")
write_xlsx(panel_micro, "painel_votos_deputado_federal_microregioes_2010_2022.xlsx")

cat("\n01b_extraction_legislativo.R complete.\n")
sink(); close(log_con)


# =============================================================================
# [PL-7] BIGQUERY ALTERNATIVE — validation only, NOT the default path
# -----------------------------------------------------------------------------
# The electionsBR route above reads TSE directly and costs nothing. The queries
# below hit basedosdados and WILL be billed to GCP_BILLING. Run them only to
# cross-validate the pull, deliberately, with a billing cap set.
#
# STEP 0 — ALWAYS run the schema check first. basedosdados column names have
# changed between releases and the queries below assume the current names.
#
#   SELECT * FROM `basedosdados.br_tse_eleicoes.resultados_partido_municipio_zona`
#   WHERE ano = 2018 LIMIT 10
#
# STEP 1 — party x municipality, both vote types, all four cycles.
# Mirrors panel_mun above. Compare row-for-row.
#
# query_leg_partido <- "
# SELECT
#   ano                        AS year,
#   turno                      AS round,
#   sigla_uf                   AS state,
#   id_municipio               AS municipality_code_ibge,
#   id_municipio_tse           AS municipality_code,
#   UPPER(TRIM(sigla_partido)) AS party,
#   SUM(votos_nominais)        AS votes_nominal,
#   SUM(votos_legenda)         AS votes_legenda,
#   SUM(votos_nominais) + SUM(votos_legenda) AS votes
# FROM `basedosdados.br_tse_eleicoes.resultados_partido_municipio_zona`
# WHERE ano IN (2010, 2014, 2018, 2022)
#   AND cargo = 'deputado federal'
#   AND sigla_uf NOT IN ('ZZ', 'VT')
# GROUP BY ano, turno, sigla_uf, id_municipio, id_municipio_tse, sigla_partido
# "
#
# NOTE: basedosdados already carries id_municipio (IBGE), so the BigQuery route
# does NOT need the Passuelo crosswalk -- which makes it a genuine independent
# check of the TSE->IBGE mapping, not just of the vote totals. Join
# municipios_ibge on municipality_code_ibge and compare microregion assignment
# against `mapeamento`. Any disagreement is a finding about BLOCK C, not only
# about this script.
#
# STEP 2 — candidate-level, if you ever need within-party dispersion
# (open-list voting means a party's candidates are ideologically heterogeneous;
# this is the data you would need to say anything about that).
#
# query_leg_candidato <- "
# SELECT
#   ano AS year, sigla_uf AS state, id_municipio AS municipality_code_ibge,
#   UPPER(TRIM(sigla_partido)) AS party,
#   numero_candidato, SUM(votos) AS votes
# FROM `basedosdados.br_tse_eleicoes.resultados_candidato_municipio_zona`
# WHERE ano IN (2010, 2014, 2018, 2022)
#   AND cargo = 'deputado federal'
#   AND sigla_uf NOT IN ('ZZ', 'VT')
# GROUP BY ano, sigla_uf, id_municipio, sigla_partido, numero_candidato
# "
#
# STEP 3 — reconciliation assertion to run after either pull:
#   stopifnot(
#     "[PL-12] BigQuery and electionsBR party totals disagree by >0.1%" =
#       max(abs(bq_totals$votes - tse_totals$votes) / tse_totals$votes) < 0.001
#   )
# =============================================================================
