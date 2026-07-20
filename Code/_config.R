# =============================================================================
# _config.R  —  single source of truth for paths and global constants.
#
# Every pipeline script starts with:
#     source("C:/Users/Yago Ramalho/Documents/tema mestrado/data/códigos/_config.R")
# which sets the working directory to the ONE canonical data folder and defines
# the shared constants. No script should call setwd() on its own anymore.
#
# Canonical data directory ("versão com vínculos totais"): this is where the
# audited v7/v3 pipeline already lives and where every input and output for
# stages 02–07 is read/written. Raw extraction (stage 01) also writes here so
# nothing is scattered across sibling folders again.
# =============================================================================

DATA_DIR <- "C:/Users/Yago Ramalho/Documents/tema mestrado/data/dados consolidados/versão com vínculos totais"
CODE_DIR <- "C:/Users/Yago Ramalho/Documents/tema mestrado/data/códigos"

if (!dir.exists(DATA_DIR))
  stop("Canonical data directory not found:\n  ", DATA_DIR)

setwd(DATA_DIR)
for (d in c("output", "tables", "figures")) dir.create(d, showWarnings = FALSE)

# ---- Google Cloud billing project (BigQuery: RAIS, Comex, PIB) --------------
GCP_BILLING <- "gen-lang-client-0768793544"

# ---- Election years used throughout the panel ------------------------------
election_years <- c(2010, 2014, 2018, 2022)

# ---- Canonical filenames (relative to DATA_DIR) ----------------------------
# Kept here so a rename only has to happen in one place. Scripts may still use
# the bare string; these are the documented, current names.
paths <- list(
  # raw / extraction outputs
  exports_ncm   = "exports_national_ncm.rds",
  imports_ncm   = "imports_national_ncm.rds",
  rais_fte      = "rais_fte.rds",
  rais_head     = "rais_2010_micro.rds",
  municipios    = "municipios_ibge.rds",
  votos_pres    = "painel_votos_presidenciais_microregioes_2010_2022.rds",
  votos_gov     = "painel_votos_governador_microregioes_2010_2022.rds",
  # external reference tables (not produced by the pipeline)
  bls9          = "bls9_estimates_partiespresidents_long.rds",
  cnae_isic     = "CNAE20_ISIC4.xls",
  un_weighted   = "un_hs2012_isic4_weighted.csv",
  un_uniform    = "un_hs2012_isic4_tradable.csv",
  # index-building outputs
  dalton_pres   = "dalton_panel_presidencial.rds",
  dalton_gov    = "dalton_panel_governador.rds",
  epw_v7        = "epw_panel_isic_v7.rds",
  shares_v7     = "exposure_shares_isic_v7.rds",
  shocks_v7     = "sectoral_shocks_isic_v7.rds",
  controls      = "controls_micro.rds",
  centroids     = "micro_centroids.rds",
  # panel-consolidation outputs
  df_estimation = "df_estimation_v7.rds"
)

cat("[_config] working dir set to canonical DATA_DIR\n")
