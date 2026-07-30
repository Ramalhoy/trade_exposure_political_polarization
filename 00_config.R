# =============================================================================
# _config.R  —  single source of truth for paths and global constants.
#
# Every pipeline script starts with:
#     source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
# which sets the working directory to the ONE canonical data folder and defines
# the shared constants. No script should call setwd() on its own anymore.
#
# Canonical data directory ("versão com vínculos totais"): this is where the
# audited v7/v3 pipeline already lives and where every input and output for
# stages 02–07 is read/written. Raw extraction (stage 01) also writes here so
# nothing is scattered across sibling folders again.
# =============================================================================

DATA_DIR <- "/Users/solenoide/Documents/dissertação/data/dados consolidados/versão com vínculos totais"
CODE_DIR <- "/Users/solenoide/Documents/dissertação/data/códigos"

if (!dir.exists(DATA_DIR))
  stop("Canonical data directory not found:\n  ", DATA_DIR)

setwd(DATA_DIR)
for (d in c("output", "tables", "figures")) dir.create(d, showWarnings = FALSE)

# ---- Google Cloud billing project (BigQuery: RAIS, Comex, PIB) --------------
GCP_BILLING <- "gen-lang-client-0768793544"

# ---- Election years used throughout the panel ------------------------------
election_years <- c(2010, 2014, 2018, 2022)

# ---- SHARE DENOMINATOR (the Bartik exposure-share normalisation) -----------
# The exposure shares are  s_rj = L_rj,2010 / D_r,2010 . This flag chooses D_r.
#
#   "tradable"  D_r = tradable employment in the numerator set. Shares sum to
#               ONE within each microregion, so the treatment measures the
#               shock per TRADABLE worker and differences out cross-regional
#               variation in tradable intensity. This is the construction
#               behind the ANPEC tables and Equation (eq:theta) of the paper.
#
#   "total"     D_r = TOTAL formal employment, all sectors (rais_fte.rds over
#               all 670 CNAE classes). Shares are INCOMPLETE: they sum to
#               theta_r, the tradable share of total formal employment. This
#               is the ADH/Rettl convention the paper cites, and it is the
#               correct one -- exposure then scales with tradable intensity.
#
# The two are related by a region-specific MULTIPLICATIVE rescaling
#       s_total[r,j] = theta_r * s_tradable[r,j]
#   =>  EPW_total[r,t] = theta_r * EPW_tradable[r,t]
# so adding theta_r as an ADDITIVE control does NOT recover "total" from
# "tradable". The identity is asserted at construction in 03 and 03a.
#
# WARNING: flipping this to "total" MOVES THE TREATMENT.
# cor(EPW_tradable, EPW_total) = 0.933 (rank 0.927), below the 0.99 guard in
# 03a. Rotemberg weights, the effective-shock count (the "~2.4" quoted
# throughout the paper), balance tests, AKM/AKM0, Conley and every table are
# functions of the shares and MUST be recomputed, not carried over. Re-run in
# order: 03 -> 03a -> 03b -> 03c -> 03d -> 04 -> 06/06b -> 07/07b.
SHARE_DENOM <- "tradable"          # "tradable" (status quo) | "total" (ADH/Rettl)
stopifnot("SHARE_DENOM must be 'tradable' or 'total'" =
            SHARE_DENOM %in% c("tradable", "total"))

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
  df_estimation = "df_estimation_v7.rds",
  # realized sum-of-shares (the BHJ incomplete-shares control). Identically 1
  # under SHARE_DENOM="tradable"; equal to theta_r under "total".
  share_sum     = "share_sum_theta_v9.rds",           # export-bilateral numerator (03)
  share_sum_com = "share_sum_theta_common_v9.rds"     # full-tradable numerator (03a)
)

cat("[_config] working dir set to canonical DATA_DIR | SHARE_DENOM =",
    SHARE_DENOM, "\n")
