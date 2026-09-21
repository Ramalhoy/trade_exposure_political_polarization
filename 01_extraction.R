# =============================================================================
# 01_extraction.R  (pipeline stage 1 — data extraction)
# -----------------------------------------------------------------------------
# Single entry point for all RAW data pulls, merged from three former scripts:
#     "00 - dados RAIS.R"                    -> BLOCK A (employment)
#     "00 - dados de exportação nacional.R"  -> BLOCK B (trade)
#     "00 - limpeza de dados eleitorais.R"   -> BLOCK C (elections)
#
# Every output is written to the canonical DATA_DIR (see _config.R) so nothing
# is scattered across sibling folders. Each block is independent — you can run
# one block at a time. Network/BigQuery calls are heavy; rerun only when needed.
#
# OUTPUTS (all in DATA_DIR):
#   municipios_ibge.rds                                  (shared IBGE directory)
#   rais_2010_micro.rds        rais_fte.rds              (employment: head + FTE)
#   exports_national_ncm.rds   imports_national_ncm.rds  (Comex national flows)
#   painel_votos_presidenciais_microregioes_2010_2022.rds
#   painel_votos_governador_microregioes_2010_2022.rds
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")

library(basedosdados)
library(dplyr)
library(jsonlite)
library(writexl)
library(electionsBR)
library(tidyr)
library(stringr)
library(readr)
library(readxl)
library(httr)          # [PL-28] browser-header transport for the TSE CDN

set_billing_id(GCP_BILLING)

# =============================================================================
# SHARED — IBGE municipality -> microregion/mesoregion directory
# Superset build that satisfies every downstream consumer (RAIS aggregation,
# election mapping, and 04_controls.R, which needs mesoregion_code).
# =============================================================================
municipios_ibge <- fromJSON(
  "https://servicodados.ibge.gov.br/api/v1/localidades/municipios?view=nivelado"
) |>
  select(
    municipality_code_ibge   = `municipio-id`,
    municipality_name        = `municipio-nome`,
    microregion_code         = `microrregiao-id`,
    microregion_name         = `microrregiao-nome`,
    mesoregion_code          = `mesorregiao-id`,
    mesoregion_name          = `mesorregiao-nome`,
    state                    = `UF-sigla`,
    UF_id                    = `UF-id`,
    intermediary_region_code = `regiao-intermediaria-id`
  ) |>
  mutate(municipality_code_ibge = as.character(municipality_code_ibge))

saveRDS(municipios_ibge, "municipios_ibge.rds")


# =============================================================================
# BLOCK A — RAIS FORMAL EMPLOYMENT (2010), by microregion x CNAE 2.0
# Two measures: (A1) headcount of active links on 31/12; (A2) annualized FTE
# from contract dates (replicates Rettl 2025, Appendix G).
# =============================================================================

# ---- A1: headcount (vínculo ativo em 31/12) --------------------------------
query_head <- "
SELECT
  dados.ano, dados.sigla_uf, dados.id_municipio,
  diretorio_id_municipio.nome AS municipio_nome,
  dados.cnae_2, dados.cnae_2_subclasse,
  COUNT(*) as total_vinculos
FROM `basedosdados.br_me_rais.microdados_vinculos` AS dados
LEFT JOIN `basedosdados.br_bd_diretorios_brasil.municipio` AS diretorio_id_municipio
  ON dados.id_municipio = diretorio_id_municipio.id_municipio
LEFT JOIN `basedosdados.br_bd_diretorios_brasil.cnae_2` AS diretorio_cnae
  ON dados.cnae_2_subclasse = diretorio_cnae.subclasse
WHERE dados.ano = 2010
  AND dados.vinculo_ativo_3112 = '1'
GROUP BY
  dados.ano, dados.sigla_uf, dados.id_municipio,
  diretorio_id_municipio.nome, dados.cnae_2, dados.cnae_2_subclasse,
  diretorio_cnae.descricao_classe
"

rais_2010 <- read_sql(query_head) |>
  mutate(total_vinculos = as.numeric(total_vinculos))

rais_2010_micro <- rais_2010 |>
  left_join(municipios_ibge, by = c("id_municipio" = "municipality_code_ibge")) |>
  group_by(microregion_code, microregion_name,
           mesoregion_code, mesoregion_name, state, cnae_2) |>
  summarise(total_vinculos = sum(total_vinculos, na.rm = TRUE), .groups = "drop")

saveRDS(rais_2010_micro, "rais_2010_micro.rds")
write_xlsx(rais_2010_micro, "rais_2010_emprego_microregiao_cnae.xlsx")

# ---- A2: annualized FTE via contract months --------------------------------
#   mes_admissao   > 0 : new hire in 2010 ; = 0/NULL : ongoing from prior year
#   mes_desligamento > 0 : ended in 2010 ; = 0/NULL : active on Dec 31
query_fte <- "
SELECT
  dados.ano, dados.sigla_uf, dados.id_municipio,
  diretorio_id_municipio.nome AS municipio_nome,
  dados.cnae_2, dados.cnae_2_subclasse,
  SUM(
    CASE
      WHEN mes_admissao > 0 AND mes_desligamento > 0
        THEN (mes_desligamento - mes_admissao + 1) / 12.0
      WHEN mes_admissao > 0 AND (mes_desligamento = 0 OR mes_desligamento IS NULL)
        THEN (12 - mes_admissao + 1) / 12.0
      WHEN (mes_admissao = 0 OR mes_admissao IS NULL) AND mes_desligamento > 0
        THEN mes_desligamento / 12.0
      ELSE 1.0
    END
  ) AS total_fte
FROM `basedosdados.br_me_rais.microdados_vinculos` AS dados
LEFT JOIN `basedosdados.br_bd_diretorios_brasil.municipio` AS diretorio_id_municipio
  ON dados.id_municipio = diretorio_id_municipio.id_municipio
WHERE dados.ano = 2010
GROUP BY
  dados.ano, dados.sigla_uf, dados.id_municipio,
  diretorio_id_municipio.nome, dados.cnae_2, dados.cnae_2_subclasse
"

rais_FTE <- read_sql(query_fte) |>
  mutate(total_fte = as.numeric(total_fte))

rais_fte_micro <- rais_FTE |>
  left_join(municipios_ibge, by = c("id_municipio" = "municipality_code_ibge")) |>
  group_by(microregion_code, microregion_name,
           mesoregion_code, mesoregion_name, state, cnae_2) |>
  summarise(total_fte = sum(total_fte, na.rm = TRUE), .groups = "drop")

# sanity anchors: ~45–55M FTE, 558 micros, ~600–680 CNAE classes
cat("RAIS FTE total:", round(sum(rais_fte_micro$total_fte)),
    "| micros:", n_distinct(rais_fte_micro$microregion_code),
    "| cnae_2:", n_distinct(rais_fte_micro$cnae_2), "\n")

saveRDS(rais_fte_micro, "rais_fte.rds")
write_xlsx(rais_fte_micro, "rais_fte.xlsx")


# =============================================================================
# BLOCK B — COMEX NATIONAL TRADE FLOWS, by year x NCM (2010–2022)
# Nominal FOB USD; deflation happens later in 03_epw_construction.R.
# =============================================================================
exports <- read_sql("
  SELECT dados.ano AS ano, dados.id_ncm AS id_ncm,
         SUM(dados.valor_fob_dolar) AS valor_fob_dolar
  FROM `basedosdados.br_me_comex_stat.ncm_exportacao` AS dados
  WHERE dados.ano BETWEEN 2010 AND 2022
  GROUP BY dados.ano, dados.id_ncm
", billing_project_id = get_billing_id()) |>
  mutate(ano = as.numeric(ano), valor_fob_dolar = as.numeric(valor_fob_dolar))

saveRDS(exports, "exports_national_ncm.rds")
write_xlsx(exports, "exports_national.xlsx")

imports <- read_sql("
  SELECT dados.ano AS ano, dados.id_ncm AS id_ncm,
         SUM(dados.valor_fob_dolar) AS valor_fob_dolar
  FROM `basedosdados.br_me_comex_stat.ncm_importacao` AS dados
  WHERE dados.ano BETWEEN 2010 AND 2022
  GROUP BY dados.ano, dados.id_ncm
", billing_project_id = get_billing_id()) |>
  mutate(ano = as.numeric(ano), valor_fob_dolar = as.numeric(valor_fob_dolar))

saveRDS(imports, "imports_national_ncm.rds")
write_xlsx(imports, "imports_national.xlsx")


# =============================================================================
# BLOCK B2 — COMEX IMPORTS FROM CHINA, by year x NCM (2010–2022)
# Feeds the IPW_china variant in 03d (Brazil's import competition from China
# specifically). IDEMPOTENT + CACHED: skipped whole if the cache already exists,
# so re-running 01 does not re-hit BigQuery. China's SISCOMEX país code is 160
# (mainland China; Hong Kong 158 and Macao 159 are DELIBERATELY excluded to
# match the "China only" definition). 03d currently sources IPW_china from BACI
# (Brazil<-China, i=156,j=76) as an already-available fallback; this block
# produces the Comex-native series so IPW_china is on the SAME source/units as
# IPW_total. Once run, point 03d at imports_china_ncm.rds.
# =============================================================================
CHINA_COMEX_PAIS <- 160L      # SISCOMEX país code for mainland China

if (!file.exists("imports_china_ncm.rds")) {
  imports_china <- read_sql(sprintf("
    SELECT dados.ano AS ano, dados.id_ncm AS id_ncm,
           SUM(dados.valor_fob_dolar) AS valor_fob_dolar
    FROM `basedosdados.br_me_comex_stat.ncm_importacao` AS dados
    WHERE dados.ano BETWEEN 2010 AND 2022
      AND dados.id_pais = '%d'
    GROUP BY dados.ano, dados.id_ncm
  ", CHINA_COMEX_PAIS), billing_project_id = get_billing_id()) |>
    mutate(ano = as.numeric(ano), valor_fob_dolar = as.numeric(valor_fob_dolar))

  # sanity: China should be ~15-25% of Brazil's total imports by value
  chn_share <- sum(imports_china$valor_fob_dolar) / sum(imports$valor_fob_dolar)
  cat(sprintf("[B2] China import share of Brazil total (2010-2022): %.1f%%\n",
              100 * chn_share))
  stopifnot("[B2] China import share implausible (check id_pais=160)" =
              chn_share > 0.05 & chn_share < 0.40)

  saveRDS(imports_china, "imports_china_ncm.rds")
  write_xlsx(imports_china, "imports_china.xlsx")
} else {
  cat("[B2] imports_china_ncm.rds already cached — skipping BigQuery re-pull.\n")
}


# =============================================================================
# BLOCK C — TSE ELECTIONS: microregion vote panels (2010–2022)
# One helper for both races (Presidente / Governador): pull -> dedup by natural
# key -> aggregate to municipality -> map TSE->IBGE->microregion -> aggregate.
# For governor, 'state' stays in the aggregation key so that same-name/party
# candidates from different states are never pooled (microregions do not cross
# state lines, so the aggregation is clean).
# =============================================================================
years <- election_years

# TSE <-> IBGE municipality equivalence (Passuelo crosswalk)
depara <- read.csv(
  "https://raw.githubusercontent.com/yuripassuelo/codigos_mun_tse_ibge/master/relacao_mun_tse_ibge.csv",
  encoding = "UTF-8"
) |>
  transmute(
    municipality_code      = as.character(cd_mun_tse),
    municipality_code_ibge = as.character(cd_mun_ibge)
  )

# TSE -> IBGE -> microregion (one row per TSE municipality)
mapeamento <- depara |>
  mutate(municipality_code = as.character(as.integer(municipality_code))) |>
  left_join(
    municipios_ibge |>
      distinct(municipality_code_ibge, .keep_all = TRUE) |>
      select(municipality_code_ibge, microregion_code, microregion_name),
    by = "municipality_code_ibge"
  )

# =============================================================================
# STAGE 0b RETROFIT — [PL-28] / [PL-29] / [PL-30], diagnosed in packet_L.
# -----------------------------------------------------------------------------
# WITHOUT THIS BLOCK, BLOCK C SILENTLY REBUILDS THE PRESIDENTIAL AND GOVERNOR
# PANELS AS EMPTY FRAMES. Two independent failures, neither of which raises an
# error. Full diagnosis and evidence: RATIONALE_L.md §1, CODE_CHANGES_TODO.md §B.
#
#   [PL-28] The TSE CDN answers header-less requests with HTTP 403 and a
#           492-byte HTML page. electionsBR:::download_unzip() writes that page
#           to the .zip path; unzip() then fails with a mere WARNING and
#           elections_tse() returns a 0x0 tibble. Accept-Encoding is the
#           discriminating header: with the full browser set the CDN returns 200,
#           and dropping Accept-Encoding alone returns 403. Fix: pre-seed
#           tempdir() with a correctly fetched archive. download_unzip() skips
#           its own download when the file is already there, so electionsBR
#           still does ALL of the parsing — only the transport is replaced.
#
#   [PL-29] DATA_DIR carries non-ASCII characters ("dissertação", "versão",
#           "vínculos"); macOS stores them on disk in NFD while R's string is
#           partly NFC, and readr/vroom cannot resolve the mixture. Inside
#           electionsBR:::juntaDados() every read is wrapped in
#           tryCatch(..., error = function(e) NULL), so ALL reads return NULL,
#           rbindlist() yields an empty table, and the function again returns
#           0x0 WITHOUT ERROR. Fix: run the pull from an ASCII scratch directory.
#
#   [PL-30] Both failures are SILENT, so the pull is asserted non-empty, and the
#           cargo filter is asserted to have selected rows, before anything
#           downstream can consume the result.
#
# This retrofit changes NO data semantics. When the network behaves it is a
# no-op; when it does not, the run stops instead of writing an empty panel.
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

# `slug` is the TSE dataset directory; `cache_name` is the filename electionsBR
# looks for in tempdir(), which differs by type: vote_mun_zone caches as a bare
# "<year>.zip", party_mun_zone as "votacao_partido_munzona_<year>.zip".
tse_seed_archive <- function(y, slug = "votacao_candidato_munzona",
                             cache_name = paste0(y, ".zip")) {
  dest <- file.path(tempdir(), cache_name)
  if (file.exists(dest) && file.size(dest) > 1e6) return(invisible(dest))
  url  <- sprintf("https://cdn.tse.jus.br/estatistica/sead/odsele/%s/%s_%d.zip",
                  slug, slug, y)
  resp <- httr::GET(url, httr::write_disk(dest, overwrite = TRUE),
                    httr::user_agent(TSE_UA), tse_browser_headers())
  if (httr::status_code(resp) != 200)
    stop(sprintf("[PL-28] TSE CDN returned HTTP %d for %s_%d.zip",
                 httr::status_code(resp), slug, y))
  members <- utils::unzip(dest, list = TRUE)$Name
  if (!any(grepl("\\.csv$|\\.txt$", members)))
    stop(sprintf("[PL-28] %s_%d.zip downloaded but carries no data member", slug, y))
  cat(sprintf("[PL-28] %s_%d.zip fetched: %.1f MB, %d members\n",
              slug, y, file.size(dest) / 1e6, length(members)))
  invisible(dest)
}

with_ascii_wd <- function(expr) {
  scratch <- file.path(tempdir(), "tse_wd")
  dir.create(scratch, showWarnings = FALSE, recursive = TRUE)
  owd <- getwd(); on.exit(setwd(owd), add = TRUE)
  setwd(scratch)
  force(expr)
}

build_vote_panel <- function(cargo, out_slug) {

  panel_mun <- lapply(years, \(y) {
    tse_seed_archive(y)                                                # [PL-28]
    raw <- with_ascii_wd(                                              # [PL-29]
      elections_tse(year = y, type = "vote_mun_zone", br_archive = TRUE)
    )
    # [PL-30] both failures above are SILENT — assert before consuming.
    if (nrow(raw) == 0L)
      stop(sprintf("[PL-30] elections_tse returned 0 rows for %d. See [PL-28] (CDN 403) and [PL-29] (non-ASCII wd).", y))
    if (!any(raw$DS_CARGO == cargo, na.rm = TRUE))
      stop(sprintf("[PL-30] no rows for cargo '%s' in %d. Labels present: %s",
                   cargo, y, paste(sort(unique(raw$DS_CARGO)), collapse = ", ")))
    raw |>
      filter(DS_CARGO == cargo) |>
      distinct(NR_TURNO, CD_MUNICIPIO, NR_ZONA, NM_CANDIDATO, SG_PARTIDO,
               QT_VOTOS_NOMINAIS, .keep_all = TRUE) |>
      transmute(
        year              = y,
        candidato         = NM_CANDIDATO,
        round             = as.integer(NR_TURNO),
        municipality      = as.character(NM_MUNICIPIO),
        municipality_code = as.character(CD_MUNICIPIO),
        state             = SG_UF,
        party             = SG_PARTIDO,
        votes             = as.numeric(QT_VOTOS_NOMINAIS)
      )
  }) |>
    bind_rows() |>
    group_by(year, round, municipality_code, municipality, state, party, candidato) |>
    summarise(votes = sum(votes, na.rm = TRUE), .groups = "drop") |>
    filter(!state %in% c("ZZ", "VT")) |>                       # remove exterior
    mutate(municipality_code = as.character(as.integer(municipality_code)))

  panel_micro <- panel_mun |>
    left_join(mapeamento, by = "municipality_code") |>
    summarise(
      votes = sum(votes, na.rm = TRUE),
      .by   = c(year, round, microregion_code, microregion_name, party, candidato, state)
    )

  # diagnostics
  lost <- panel_mun |>
    left_join(mapeamento, by = "municipality_code") |>
    filter(is.na(microregion_code)) |>
    summarise(votos_perdidos = sum(votes)) |> pull(votos_perdidos)
  cat(sprintf("[%s] micros: %d | vote rows: %d | votes w/o microregion: %s\n",
              cargo, n_distinct(panel_micro$microregion_code),
              nrow(panel_micro), format(lost, big.mark = ",")))

  write_xlsx(panel_micro,
             paste0("painel_votos_", out_slug, "_microregioes_2010_2022.xlsx"))
  saveRDS(panel_micro,
          paste0("painel_votos_", out_slug, "_microregioes_2010_2022.rds"))
  invisible(panel_micro)
}

build_vote_panel("Presidente", "presidenciais")
build_vote_panel("Governador", "governador")

cat("\n01_extraction.R complete — all raw outputs written to DATA_DIR.\n")
