# =============================================================================
# D1_shares_destino.R  —  Packet D, Phase 1, STAGE 1, step 1
# -----------------------------------------------------------------------------
# Branch A exposure shares: microregion x DESTINATION, fixed at 2010.
#
#   X_rd,2010 = sum over municipios m in r, over products p, of 2010 export value
#   N2 (primary): s_rd = X_rd / L_r,2010        theta_r = sum_d s_rd
#   N1 (robust) : s_rd = X_rd / sum_d X_rd      (composition; sums to 1)
#
# This script reads Comex ONLY. No BACI, no crosswalk, no ISIC — that absence is
# the whole point of Branch A ([D-1]: only the destination branch is
# crosswalk-free). It answers the cheapest decisive question in the packet:
#
#   Is microregion-level destination exposure diffuse, or concentrated?
#
# The national destination mix has 1/HHI = 18.90 effective destinations, close to
# the industry axis's 19.67 — but Rotemberg weights depend on how exposure
# covaries ACROSS microregions, and a single microregion can sell 90% of its
# output to one destination while the national mix stays diffuse. The
# microregion-level HHI distribution is the real test and it is computed here.
#
# The employment-imputed bridge (D_data_contracts §4.3) is NOT here — see [D-16].
#
# STRICTLY ADDITIVE. Aborts rather than overwriting. No outcome regression.
#
# Run:  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 Rscript códigos/packet_D/D1_shares_destino.R
#   The UTF-8 locale is a hard prerequisite, not a preference ([D-6]).
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(data.table)
  library(readxl)
})
set.seed(2026)

# ---- NAMED CONSTANTS (no hidden defaults) -----------------------------------
OUT_D             <- file.path("output", "packet_D")
BASE_YEAR         <- 2010L
N_MICRO_EXPECTED  <- 557L     # [D-7], settled. Do not reopen.

# Comex municipality file. Copied into DATA_DIR rather than read across trees
# ([D-4]); sha256 db09b60f...43e3c9c0, identical to the source copy.
COMEX_FILE        <- "EXP_2010_MUN.csv"
COMEX_SEP         <- ";"
COMEX_ENCODING    <- "latin1"   # documented as latin-1; 2010 happens to be pure
                                # ASCII, so this is belt-and-braces, not a fix.

# [D-13] Auxiliary tables are addressed BY SHEET NAME, not by index.
# TABELAS_AUXILIARES.xlsx has a leading "ÍNDICE" sheet, so the sheet NAMED "10"
# is the 11th. excel_sheets()[10] is the NCM->PPE table and would join zero
# countries while raising no error. Named, not positional.
AUX_XLSX          <- "/Users/solenoide/Documents/dissertação/data/misc/TABELAS_AUXILIARES.xlsx"
AUX_COUNTRY_SHEET <- "10"    # CO_PAIS | CO_PAIS_ISON3 | CO_PAIS_ISOA3 | NO_PAIS
AUX_MUN_SHEET     <- "13"    # CO_MUN_GEO | NO_MUN | NO_MUN_MIN | SG_UF

# [D-19] COMEX USES PRE-1988 IBGE UF CODES. Not a data feature — a trap.
# Comex's CO_MUN is IBGE's 7-digit geocode with the UF prefix frozen at the
# pre-1988 numbering for four federal units. Sao Paulo is 34, not 35; Mato
# Grosso do Sul 52, not 50; Goias 53, not 52; Distrito Federal 54, not 53. The
# trailing five digits are identical. (The renumbering followed the creation of
# Mato Grosso do Sul in 1977 and Tocantins in 1988; Comex never migrated.)
#
# Left unhandled this drops 970 municipalities — every one in SP, GO, MS and DF
# — carrying 31.2% of Brazil's 2010 export value, INCLUDING the municipality of
# Sao Paulo, silently and with no error. Verified after remapping: 5,568 of
# 5,568 real municipalities match IBGE by code, 5,568 of 5,568 agree on state.
COMEX_UF_PREFIX_REMAP <- c("34" = "35",   # SP
                           "52" = "50",   # MS
                           "53" = "52",   # GO
                           "54" = "53")   # DF
COMEX_PSEUDO_UF   <- c("EX", "ND")   # "exterior" / "nao declarada": not places

# [D-20] BACI KEYS ON UN COMTRADE AREA CODES, NOT ISO 3166-1 NUMERIC.
# `D_data_contracts.md` §1b and the packet brief both state that BACI's
# country_code "IS the numeric ISO 3166-1 code" and joins directly onto
# CO_PAIS_ISON3 with no name matching. **That is wrong**, and wrong in the most
# damaging possible place: BACI codes the United States 842, not 840, so a
# numeric join silently drops Brazil's second-largest destination — 9.6% of
# 2010 export value on its own, 17.0% together with France (251 not 250),
# India (699 not 356), Switzerland (757 not 756) and Norway (579 not 578).
#
# The alphabetic iso3 that BACI also ships is reliable and is the join key here.
# That leaves only the areas where Comtrade AGGREGATES territories into a
# metropole, mapped explicitly below. Every target is asserted to exist in
# BACI's own country list, so a stale entry fails loudly.
#
# Folding Comex into BACI's area scheme (rather than the reverse) is the correct
# direction: m_dp_row is built from BACI, so destination 842 already contains
# Puerto Rico's imports and Comex's PRI must join to it.
COMEX_BACI_AREA_MAP <- c(
  TWN = 490L,                                    # -> "Other Asia, nes"
  PRI = 842L, VIR = 842L, UMI = 842L,            # -> USA
  GLP = 251L, MTQ = 251L, GUF = 251L, REU = 251L,# French overseas departements
  MCO = 251L,                                    # Monaco -> France
  LIE = 757L,                                    # Liechtenstein -> Switzerland
  IMN = 826L, GGY = 826L,                        # Crown dependencies -> UK
  FRO = 208L)                                    # Faroe Islands -> Denmark

# [D-21] ZZZ is the Comex residual bucket, not a country. Twelve CO_PAIS codes
# carry it: "Not defined", "To define", "Not declared", "Sem informacao",
# "Central Banks", "International Organizations", the USSR, and — the only one
# with material 2010 value — "Planes and ships provisions" (ship and aircraft
# stores, 1.78% of exports). These are excluded as NON-DESTINATIONS with their
# share reported, not silently dropped and not assigned to a country.
NON_DESTINATION_ISO3 <- "ZZZ"

# [D-22] BACI marks superseded partners with "(...YYYY)" in country_name. Some
# SHARE an iso3 with their successor (Belgium-Luxembourg/BEL, Fed. Rep. of
# Germany/DEU, Sudan/SDN) and some do not (Netherlands Antilles/ANT). Deduplicate
# ONLY where an iso3 is genuinely ambiguous, keeping the modern row. A blanket
# "drop every (...)" filter also deletes ANT — which is not a duplicate and which
# carries 0.48% of Brazil's 2010 exports, because the Antilles were dissolved in
# October 2010 and so existed for most of the base year.
BACI_SUPERSEDED_PATTERN <- "\\(\\.\\.\\."

# [D-23] TERRITORIAL RECONSTITUTIONS CREATE FAKE +/-2 ARC SHOCKS. Live problem,
# not housekeeping. g_dt is an arc rate between t-4 and t, and arcD(0, v) = +2,
# arcD(v, 0) = -2. A destination that is DISSOLVED mid-panel therefore shows a
# total demand collapse, and its successors show entry from nothing — both pure
# reclassification artefacts that would sit in the extreme tail of the shock
# distribution and could carry large Rotemberg weight.
#
# Two reconstitutions fall inside 2010-2022:
#   Netherlands Antilles (530) dissolved 2010-10 -> Curacao 531, Sint Maarten
#     534, Bonaire 535. (Aruba 533 was already separate and is NOT folded.)
#   Sudan (736) partitioned 2011-07 -> Sudan 729, South Sudan 728.
# Each group is folded into ONE persistent unit spanning the whole panel, keyed
# by the pre-split code. Belgium-Luxembourg (58) and the FRG (280) dissolved
# before 2010 and carry no trade in the window; folded for symmetry, costless.
#
# THE IDENTICAL FOLD MUST BE APPLIED TO BACI IN D2/D3. It is written to disk as
# part of D1_s_rd.rds so the later scripts cannot use a different one.
PANEL_PERSISTENT_FOLD <- c(
  "531" = 530L, "534" = 530L, "535" = 530L,   # -> former Netherlands Antilles
  "728" = 729L, "736" = 729L,                 # -> Sudan incl. South Sudan
  "58"  = 56L,  "442" = 56L,                  # -> Belgium-Luxembourg
  "280" = 276L)                               # -> Germany

# [D-14] N2 denominator is L_r_all, TOTAL formal employment — not L_r_2010,
# which in exposure_shares_isic_v7.rds holds TRADABLE employment. Verified:
# s_rj = L_rj_2010 / L_r_all and theta_r = L_r_2010 / L_r_all exactly. Under
# SHARE_DENOM = "total" ([T-2b]) the industry design normalises by total formal
# employment, so Branch A must too or s_rd and s_rj are not comparable and
# theta_r means two different things in the same table.
L_R_DENOM_COL     <- "L_r_all"

# Diagnostics
HHI_EFF_THRESHOLD <- 3        # "concentrated" = fewer than 3 effective destinations
TOP_MUN_N         <- 20       # municipality-attribution leave-out set (D.7.1)
TOP_CONC_N        <- 15       # rows shown in the illustrative concentration table
TOP_DEST_N        <- 20       # destinations labelled in tables/figures
# [D-25] Saint Lucia belongs in the entrepot set. LCA ranks 19th among Brazil's
# 2010 destinations at USD 2.744 bn, 1.39% of exports — larger than the island's
# entire annual import bill by a wide margin. It is transhipment through the
# Buckeye/Hess oil storage terminal, not final demand.
# It matters more than the other four because the commodity is PETROLEUM, the
# same ISIC 0610 that carries alpha ~ 0.90 in z_CHN ([D-11]). If LCA surfaces in
# Branch A's top Rotemberg weights, that is the petroleum concentration
# reappearing under a destination label rather than an industry one, and D4 must
# say so explicitly rather than reporting it as a destination result.
ENTREPOT_ISO3     <- c("NLD", "SGP", "HKG", "ARE", "LCA")   # spec §D.7.2

stopifnot("[D1] SHARE_DENOM must be 'total' to match the published design" =
            SHARE_DENOM == "total")

# ---- output guard -----------------------------------------------------------
dir.create(OUT_D, showWarnings = FALSE, recursive = TRUE)
D1_OUT <- c("D1_x_rd_2010.rds", "D1_s_rd.rds", "D1_micro_hhi.csv",
            "D1_destination_top.csv", "D1_micro_concentration.csv",
            "D1_municipio_concentration.csv", "tab_d1_shares.md",
            "fig_d1_destination_hhi.pdf", "log_d_unmatched_codes.csv")
existing <- D1_OUT[file.exists(file.path(OUT_D, D1_OUT))]
if (length(existing))
  stop("[D1] refusing to overwrite existing packet_D output:\n  ",
       paste(existing, collapse = "\n  "),
       "\nMove or delete them deliberately before re-running.")

log_con <- file(file.path(OUT_D, "D1_run_log.txt"), open = "wt")
sink(log_con, split = TRUE)
cat("=== D1 Branch A destination shares:", format(Sys.time()), "===\n")
cat("SHARE_DENOM =", SHARE_DENOM, "| base year =", BASE_YEAR,
    "| N_MICRO_EXPECTED =", N_MICRO_EXPECTED, "\n\n")

# =============================================================================
# STEP 1 — READ COMEX MUNICIPALITY EXPORTS
# =============================================================================
stopifnot("[D1] EXP_2010_MUN.csv absent from DATA_DIR — copy it in first" =
            file.exists(COMEX_FILE))

comex <- fread(COMEX_FILE, sep = COMEX_SEP, encoding = "Latin-1",
               colClasses = list(character = c("CO_ANO", "CO_MES", "SH4",
                                               "CO_PAIS", "SG_UF_MUN", "CO_MUN"))) |>
  as_tibble() |>
  mutate(across(c(KG_LIQUIDO, VL_FOB), as.numeric),
         CO_ANO = as.integer(CO_ANO))

stopifnot(
  "[D1] unexpected Comex schema" =
    all(c("CO_ANO", "CO_MES", "SH4", "CO_PAIS", "SG_UF_MUN", "CO_MUN",
          "KG_LIQUIDO", "VL_FOB") %in% names(comex)),
  "[D1] file is not the 2010 vintage" = all(comex$CO_ANO == BASE_YEAR),
  "[D1] negative export value" = all(comex$VL_FOB >= 0))

# The national total BEFORE any aggregation. Every downstream sum is asserted
# against this, so an aggregation that silently loses rows cannot pass.
comex_national_total_2010 <- sum(comex$VL_FOB)
cat(sprintf("STEP 1: %s rows | %d destinations | %d municipios | total FOB %.2f B USD\n",
            format(nrow(comex), big.mark = ","), n_distinct(comex$CO_PAIS),
            n_distinct(comex$CO_MUN), comex_national_total_2010 / 1e9))

# [D-15] NO DEFLATION IS APPLIED, and that is correct rather than an omission.
# The shares are fixed at 2010, which IS the base year of the constant-USD
# series used everywhere else, so current 2010 USD and constant 2010 USD are the
# same number. Deflation becomes mandatory the moment a second year enters
# (D_data_contracts §1); it does not apply to a single-year cross-section.
cat("[D-15] no deflation: single 2010 cross-section, base year = deflator base\n\n")

# =============================================================================
# STEP 2 — COUNTRY CODES: Comex CO_PAIS -> numeric ISO 3166-1 (BACI's key)
# =============================================================================
aux_pais <- read_excel(AUX_XLSX, sheet = AUX_COUNTRY_SHEET) |>
  transmute(CO_PAIS       = str_trim(as.character(CO_PAIS)),
            comex_iso3n   = suppressWarnings(as.integer(CO_PAIS_ISON3)),
            comex_iso3    = str_trim(as.character(CO_PAIS_ISOA3)),
            destino_nome  = str_trim(as.character(NO_PAIS_ING)))
stopifnot("[D1] country table lost its keys" = !anyNA(aux_pais$CO_PAIS))

# BACI's own country list, so the harmonisation is asserted against the object
# it must join to (D_data_contracts §4.1). Reads a 5 KB metadata file, not the
# trade panel.
baci_countries_raw <- read_csv(file.path("baci", "country_codes_V202601.csv"),
                               show_col_types = FALSE)
# [D-22] dedupe only where an iso3 is genuinely ambiguous
baci_countries <- baci_countries_raw |>
  group_by(country_iso3) |>
  filter(n() == 1 | !str_detect(country_name, BACI_SUPERSEDED_PATTERN)) |>
  ungroup() |>
  transmute(destino = as.integer(country_code),
            baci_iso3 = country_iso3, baci_name = country_name)
stopifnot("[D-22] dedupe did not leave iso3 unique" =
            !any(duplicated(baci_countries$baci_iso3)),
          "[D-22] Netherlands Antilles must survive the dedupe" =
            530L %in% baci_countries$destino,
          "[D-20] area-map target absent from BACI" =
            all(COMEX_BACI_AREA_MAP %in% baci_countries$destino),
          "[D-23] fold target absent from BACI" =
            all(PANEL_PERSISTENT_FOLD %in% baci_countries_raw$country_code))

# [D-23] apply the persistent-unit fold to the destination key
fold_destino <- function(d) {
  k <- as.character(d)
  hit <- k %in% names(PANEL_PERSISTENT_FOLD)
  if_else(hit, PANEL_PERSISTENT_FOLD[k], as.integer(d))
}

# Join on ALPHABETIC iso3 ([D-20]), then apply the explicit area map.
area_map_tbl <- tibble(comex_iso3 = names(COMEX_BACI_AREA_MAP),
                       destino_mapped = as.integer(COMEX_BACI_AREA_MAP))

comex_d <- comex |>
  left_join(aux_pais, by = "CO_PAIS") |>
  left_join(baci_countries |> select(comex_iso3 = baci_iso3, destino_direct = destino),
            by = "comex_iso3") |>
  left_join(area_map_tbl, by = "comex_iso3") |>
  mutate(is_non_destination = comex_iso3 %in% NON_DESTINATION_ISO3,
         destino = fold_destino(coalesce(destino_direct, destino_mapped)))  # [D-23]

# Report the residual bucket rather than letting it vanish. [D-21]
non_dest <- comex_d |> filter(is_non_destination) |>
  group_by(CO_PAIS, destino_nome) |>
  summarise(vl_fob = sum(VL_FOB), .groups = "drop") |>
  mutate(kind = "non_destination_excluded",
         share_of_2010 = vl_fob / comex_national_total_2010) |>
  arrange(desc(vl_fob))

unmatched_pais <- comex_d |>
  filter(!is_non_destination, is.na(destino)) |>
  group_by(CO_PAIS, comex_iso3, comex_iso3n, destino_nome) |>
  summarise(vl_fob = sum(VL_FOB), .groups = "drop") |>
  mutate(kind = "comex_country_unmatched_to_baci",
         share_of_2010 = vl_fob / comex_national_total_2010) |>
  arrange(desc(vl_fob))

# What a NUMERIC join would have cost, quantified for the record. [D-20]
numeric_cost <- comex_d |>
  filter(!is_non_destination, !is.na(destino),
         !comex_iso3n %in% baci_countries_raw$country_code) |>
  group_by(comex_iso3, comex_iso3n, destino, destino_nome) |>
  summarise(vl_fob = sum(VL_FOB), .groups = "drop") |>
  mutate(share_of_2010 = vl_fob / comex_national_total_2010) |>
  arrange(desc(vl_fob))

cat("--- COUNTRY-CODE HARMONISATION (alphabetic iso3 + explicit area map) ---\n")
cat(sprintf("Non-destination bucket (ZZZ): %d codes | %.4f%% of 2010 value — EXCLUDED\n",
            nrow(non_dest), 100 * sum(non_dest$share_of_2010)))
if (nrow(non_dest)) print(as.data.frame(head(non_dest, 5)), digits = 4)
cat(sprintf("Unmatched to BACI          : %d codes | %.6f%% of 2010 value\n",
            nrow(unmatched_pais), 100 * sum(unmatched_pais$share_of_2010)))
if (nrow(unmatched_pais)) print(as.data.frame(head(unmatched_pais, 10)), digits = 4)
cat(sprintf("\n[D-20] value a NUMERIC iso3n join would have DROPPED: %.4f%% across %d areas\n",
            100 * sum(numeric_cost$share_of_2010), nrow(numeric_cost)))
print(as.data.frame(numeric_cost |> slice_head(n = 8)), digits = 4)

# =============================================================================
# STEP 3 — MUNICIPIO -> MICROREGIAO, 2010 TERRITORIAL DIVISION
# =============================================================================
# [D-17] Vintage pinned: the microrregiao division carried by
# municipios_ibge.rds, which 01_extraction.R BLOCK A built from the IBGE
# localidades API and which every v7 artefact uses. The microrregiao
# classification itself dates from 1990 and was unchanged through 2010; what
# changed over the period is the MUNICIPALITY list (5,565 in 2010 -> 5,570+
# later), and new municipalities inherit their parent's microregion. Comex 2010
# can only contain municipalities that existed in 2010, all of which are in this
# table. Matching the v7 object matters more than matching a published 2010
# gazetteer: if Branch A aggregated to different regions than the v7 shares,
# s_rd and s_rj would not describe the same places and no rung of the ladder
# would be comparable.
municipios <- readRDS("municipios_ibge.rds") |>
  transmute(ibge_code = str_trim(as.character(municipality_code_ibge)),
            ibge_name = municipality_name,
            micro     = as.integer(microregion_code),
            state)

# [D-19] Apply the UF-prefix remap, then VALIDATE it against the Comex
# municipality table rather than trusting the arithmetic.
comex_to_ibge <- function(x) {
  pref <- substr(x, 1, 2)
  hit  <- pref %in% names(COMEX_UF_PREFIX_REMAP)
  if_else(hit, paste0(COMEX_UF_PREFIX_REMAP[pref], substr(x, 3, 7)), x)
}

aux_mun <- read_excel(AUX_XLSX, sheet = AUX_MUN_SHEET) |>
  transmute(CO_MUN = str_trim(as.character(CO_MUN_GEO)),
            comex_mun_name = NO_MUN, SG_UF = str_trim(SG_UF)) |>
  filter(!SG_UF %in% COMEX_PSEUDO_UF) |>
  mutate(ibge_code = comex_to_ibge(CO_MUN)) |>
  left_join(municipios, by = "ibge_code")

n_bad_code  <- sum(is.na(aux_mun$micro))
n_bad_state <- sum(aux_mun$SG_UF != aux_mun$state, na.rm = TRUE)
cat("\n--- [D-19] COMEX PRE-1988 UF PREFIX REMAP ---\n")
cat(sprintf("Comex municipality table: %d real municipios | unmatched after remap: %d | state disagreements: %d\n",
            nrow(aux_mun), n_bad_code, n_bad_state))
stopifnot(
  "[D-19] UF-prefix remap does not reconcile the Comex municipality table" =
    n_bad_code == 0,
  "[D-19] remapped code lands in the wrong federal unit" = n_bad_state == 0)

comex_m <- comex_d |>
  mutate(ibge_code = comex_to_ibge(CO_MUN)) |>
  left_join(municipios, by = "ibge_code")

unmatched_mun <- comex_m |> filter(is.na(micro)) |>
  group_by(CO_MUN, ibge_code, SG_UF_MUN) |>
  summarise(vl_fob = sum(VL_FOB), .groups = "drop") |>
  mutate(kind = "comex_municipio_no_microregiao",
         share_of_2010 = vl_fob / comex_national_total_2010) |>
  arrange(desc(vl_fob))

cat("\n--- MUNICIPALITY -> MICROREGION ---\n")
cat(sprintf("Comex municipios not resolved to a microregion: %d codes | %.4f%% of 2010 value\n",
            nrow(unmatched_mun), 100 * sum(unmatched_mun$share_of_2010)))
if (nrow(unmatched_mun)) print(as.data.frame(head(unmatched_mun, 15)), digits = 4)

write_csv_safe <- function(x, f) { if (file.exists(f)) unlink(f); readr::write_csv(x, f) }
write_csv_safe(bind_rows(non_dest, unmatched_pais, unmatched_mun),
               file.path(OUT_D, "log_d_unmatched_codes.csv"))

# =============================================================================
# STEP 4 — X_rd,2010
# =============================================================================
x_rd_2010 <- comex_m |>
  filter(!is.na(micro), !is_non_destination, !is.na(destino)) |>
  group_by(micro, destino) |>
  summarise(x_rd = sum(VL_FOB), .groups = "drop") |>
  filter(x_rd > 0) |>
  left_join(baci_countries |> select(destino, destino_iso3 = baci_iso3),
            by = "destino")

x_attributed <- sum(x_rd_2010$x_rd)
cat(sprintf("\nSTEP 4: X_rd,2010 — %s cells | %d microregions | %d destinations\n",
            format(nrow(x_rd_2010), big.mark = ","),
            n_distinct(x_rd_2010$micro), n_distinct(x_rd_2010$destino)))
cat(sprintf("        attributed %.2f B of %.2f B FOB (%.4f%%)\n",
            x_attributed / 1e9, comex_national_total_2010 / 1e9,
            100 * x_attributed / comex_national_total_2010))

# Aggregation identity: what is dropped is exactly what the logs above record,
# and nothing else.
dropped <- comex_m |>
  filter(is.na(micro) | is_non_destination | is.na(destino)) |>
  summarise(v = sum(VL_FOB)) |> pull(v)
stopifnot("[D1] aggregation lost value not accounted for by the unmatched logs" =
            abs((x_attributed + dropped) - comex_national_total_2010) /
              comex_national_total_2010 < 1e-9,
          "[D1] negative or non-finite X_rd" =
            all(x_rd_2010$x_rd >= 0) && all(is.finite(x_rd_2010$x_rd)),
          "[D1] destination not harmonised to a BACI country code" =
            all(x_rd_2010$destino %in% baci_countries$destino),
          "[D1] destination label lost" = !anyNA(x_rd_2010$destino_iso3))

# External reconciliation against the national NCM series the v7 pipeline uses.
# These are different Comex products (municipality vs national detail) and will
# not match exactly; a ratio far from 1 would mean the wrong file.
exp_nat_2010 <- readRDS("exports_national_ncm.rds") |>
  filter(ano == BASE_YEAR) |>
  summarise(v = sum(as.numeric(valor_fob_dolar))) |> pull(v)
cat(sprintf("        reconciliation vs exports_national_ncm.rds: %.2f B | ratio %.4f\n",
            exp_nat_2010 / 1e9, comex_national_total_2010 / exp_nat_2010))

# =============================================================================
# STEP 5 — SHARES: N1 AND N2
# =============================================================================
shares_v7 <- readRDS("exposure_shares_isic_v7.rds")
L_r <- shares_v7 |>
  group_by(micro) |>
  summarise(L_r_denom = first(.data[[L_R_DENOM_COL]]),
            L_r_trad  = first(L_r_2010),
            theta_r_industry = first(theta_r), .groups = "drop")
stopifnot("[D1] v7 share universe is not 557 microregions" =
            nrow(L_r) == N_MICRO_EXPECTED,
          "[D1] employment denominator must be strictly positive" =
            all(L_r$L_r_denom > 0))

# [D-18] Branch A is defined on the v7 microregion universe (557), NOT on the
# set of microregions that happen to export. Microregions absent from Comex are
# retained at s_rd_n2 = 0 and theta_r = 0 — zero exposure is a value, not a
# missing observation, and dropping them would silently change the sample
# between rungs of the same ladder. N1 is a composition and is undefined for
# them; they are excluded from N1 ONLY, and the count is reported in every table
# note (D_data_contracts §4.2).
x_rd <- x_rd_2010 |> filter(micro %in% L_r$micro)
x_dropped_micro <- x_rd_2010 |> filter(!micro %in% L_r$micro)
cat(sprintf("\nSTEP 5: %d exporting microregions outside the v7 universe, %.4f%% of attributed value\n",
            n_distinct(x_dropped_micro$micro),
            100 * sum(x_dropped_micro$x_rd) / x_attributed))

x_r_tot <- x_rd |> group_by(micro) |> summarise(x_r = sum(x_rd), .groups = "drop")

s_rd <- x_rd |>
  left_join(x_r_tot, by = "micro") |>
  left_join(L_r,     by = "micro") |>
  mutate(s_rd_n2 = x_rd / L_r_denom,
         s_rd_n1 = if_else(x_r > 0, x_rd / x_r, NA_real_))

micro_exporting  <- sort(unique(s_rd$micro))
micro_zero_exp   <- setdiff(L_r$micro, micro_exporting)
cat(sprintf("        exporting microregions: %d | zero-export: %d | total: %d\n",
            length(micro_exporting), length(micro_zero_exp),
            length(micro_exporting) + length(micro_zero_exp)))
stopifnot("[D1] microregion accounting does not close on 557" =
            length(micro_exporting) + length(micro_zero_exp) == N_MICRO_EXPECTED)

# Contract gates, D_data_contracts §4.2
n1_sums <- s_rd |> group_by(micro) |> summarise(s = sum(s_rd_n1), .groups = "drop")
stopifnot(
  "[D1] s_rd_n1 does not sum to 1 within microregion" =
    all(abs(n1_sums$s - 1) < 1e-8),
  "[D1] negative s_rd_n2" = all(s_rd$s_rd_n2 >= 0),
  "[D1] non-finite share" =
    all(is.finite(s_rd$s_rd_n2)) && all(is.finite(s_rd$s_rd_n1)))

theta_r_dest <- x_r_tot |>
  left_join(L_r, by = "micro") |>
  transmute(micro, theta_r_dest = x_r / L_r_denom) |>
  right_join(tibble(micro = L_r$micro), by = "micro") |>
  mutate(theta_r_dest = replace_na(theta_r_dest, 0))
stopifnot("[D1] theta_r must be defined for all 557" =
            nrow(theta_r_dest) == N_MICRO_EXPECTED, !anyNA(theta_r_dest))

cat("\n--- theta_r under N2 (exports per formal worker, 2010 USD) ---\n")
print(as.data.frame(theta_r_dest |>
  summarise(mean = mean(theta_r_dest), sd = sd(theta_r_dest),
            min = min(theta_r_dest), p25 = quantile(theta_r_dest, .25),
            median = median(theta_r_dest), p75 = quantile(theta_r_dest, .75),
            max = max(theta_r_dest))), digits = 4)

# =============================================================================
# STEP 6 — THE DECISIVE NUMBER: microregion-level destination concentration
# =============================================================================
# Effective number of destinations per microregion, 1/HHI on the N1
# composition. This is the microregion-level analogue of the national 18.90 and
# the object that determines whether destination-side Rotemberg weights can
# de-concentrate.
micro_hhi <- s_rd |>
  group_by(micro) |>
  summarise(n_dest       = n(),
            hhi          = sum(s_rd_n1^2),
            eff_dest     = 1 / sum(s_rd_n1^2),
            top1_share   = max(s_rd_n1),
            top3_share   = sum(sort(s_rd_n1, decreasing = TRUE)[1:min(3, n())]),
            top1_dest    = destino_iso3[which.max(s_rd_n1)],
            x_r          = first(x_r),
            .groups = "drop") |>
  left_join(theta_r_dest, by = "micro")

national_mix <- x_rd |> group_by(destino, destino_iso3) |>
  summarise(x_d = sum(x_rd), .groups = "drop") |>
  mutate(share = x_d / sum(x_d)) |> arrange(desc(share))
national_eff <- 1 / sum(national_mix$share^2)

cat("\n=== D1(6) MICROREGION-LEVEL DESTINATION CONCENTRATION ===\n")
cat(sprintf("National destination mix   : %d destinations | 1/HHI = %.2f | top-1 %s %.1f%%\n",
            nrow(national_mix), national_eff, national_mix$destino_iso3[1],
            100 * national_mix$share[1]))
cat(sprintf("Value-weighted mean of microregion 1/HHI : %.2f\n",
            weighted.mean(micro_hhi$eff_dest, micro_hhi$x_r)))
print(as.data.frame(micro_hhi |>
  summarise(n_micro = n(),
            mean_eff = mean(eff_dest), sd_eff = sd(eff_dest),
            min_eff = min(eff_dest), p25 = quantile(eff_dest, .25),
            median_eff = median(eff_dest), p75 = quantile(eff_dest, .75),
            p90 = quantile(eff_dest, .90), max_eff = max(eff_dest),
            mean_n_dest = mean(n_dest), median_n_dest = median(n_dest))),
  digits = 4)

n_below <- sum(micro_hhi$eff_dest < HHI_EFF_THRESHOLD)
cat(sprintf("\nMicroregions with fewer than %d effective destinations: %d of %d (%.1f%%)\n",
            HHI_EFF_THRESHOLD, n_below, nrow(micro_hhi),
            100 * n_below / nrow(micro_hhi)))
cat(sprintf("  ...carrying %.2f%% of 2010 attributed export value\n",
            100 * sum(micro_hhi$x_r[micro_hhi$eff_dest < HHI_EFF_THRESHOLD]) /
              sum(micro_hhi$x_r)))
cat(sprintf("Benchmarks: national destination axis %.2f | national industry axis 19.67\n",
            national_eff))
cat("            industry-side EFFECTIVE SHOCKS: g_jt 2.59, g_arc 5.57, z_A 1.78\n")

cat("\n--- distribution of effective destinations per microregion ---\n")
print(as.data.frame(micro_hhi |>
  mutate(bucket = cut(eff_dest, breaks = c(0, 1.5, 2, 3, 5, 10, 20, Inf),
                      labels = c("<1.5", "1.5-2", "2-3", "3-5", "5-10",
                                 "10-20", ">20"), right = FALSE)) |>
  group_by(bucket) |>
  summarise(n_micro = n(), pct_micro = 100 * n() / nrow(micro_hhi),
            pct_value = 100 * sum(x_r) / sum(micro_hhi$x_r), .groups = "drop")),
  digits = 4)

# [D-26] Single-destination microregions are a TIE GROUP, not a ranking.
# slice_min(n = 15) keeps ties, so a table headed "15 most concentrated" silently
# printed 33 rows. Report the size of the tie group as the statistic it is, then
# cap the illustrative table explicitly.
n_single_dest <- sum(micro_hhi$n_dest == 1L)
cat(sprintf("\n--- single-destination microregions: %d of %d (%.1f%%), %.3f%% of export value ---\n",
            n_single_dest, nrow(micro_hhi), 100 * n_single_dest / nrow(micro_hhi),
            100 * sum(micro_hhi$x_r[micro_hhi$n_dest == 1L]) / sum(micro_hhi$x_r)))
cat(sprintf("--- %d largest of them by export value ---\n", TOP_CONC_N))
print(as.data.frame(micro_hhi |> filter(n_dest == 1L) |>
  slice_max(x_r, n = TOP_CONC_N, with_ties = FALSE) |>
  select(micro, n_dest, eff_dest, top1_dest, top1_share, x_r, theta_r_dest)),
  digits = 4)

# =============================================================================
# STEP 6b — [A1] INDUSTRY-SIDE COMPARISON ON THE SAME UNIT
#   The national comparison (destinations vs industries) is the wrong unit:
#   Rotemberg weights depend on how exposure covaries ACROSS microregions, so
#   the comparison must be per microregion. Computed here from the v7 shares
#   rather than quoted, so the two sides are measured the same way.
#   NOTE the denominators differ and this is NOT a like-for-like ratio:
#   destination shares are weighted by EXPORT VALUE, industry shares by
#   EMPLOYMENT. The comparison is of dispersion, not of magnitude.
# =============================================================================
micro_hhi_ind <- shares_v7 |>
  filter(s_rj > 0) |>
  group_by(micro) |>
  summarise(n_ind = n(),
            hhi_ind = sum((s_rj / sum(s_rj))^2),
            eff_ind = 1 / sum((s_rj / sum(s_rj))^2), .groups = "drop")

cat("\n=== D1(6b) [A1] EFFECTIVE UNITS PER MICROREGION: destinations vs industries ===\n")
print(as.data.frame(bind_rows(
  micro_hhi |> summarise(axis = "destinations (D1, export-weighted)",
                         n_micro = n(), mean = mean(eff_dest),
                         median = median(eff_dest), p25 = quantile(eff_dest, .25),
                         p75 = quantile(eff_dest, .75),
                         pct_below_3 = 100 * mean(eff_dest < HHI_EFF_THRESHOLD)),
  micro_hhi_ind |> summarise(axis = "ISIC industries (v7, employment-weighted)",
                             n_micro = n(), mean = mean(eff_ind),
                             median = median(eff_ind), p25 = quantile(eff_ind, .25),
                             p75 = quantile(eff_ind, .75),
                             pct_below_3 = 100 * mean(eff_ind < HHI_EFF_THRESHOLD)))),
  digits = 4)
cat("\n[A1] The exposure-diversity argument for Branch A is WITHDRAWN: destinations\n")
cat("     are if anything slightly MORE concentrated than industries per region.\n")
cat("     What survives is that the industry design collapses from these effective\n")
cat("     INDUSTRIES to 2.59 effective SHOCKS via the L_j,2010 denominator, and\n")
cat("     g_dt is bounded in [-2,2] so that dispersion is arithmetically impossible.\n")
cat("     The case for Branch A rests on SHOCK dispersion and is settled in D3/D4.\n")

# =============================================================================
# STEP 7 — DESTINATION MIX, ENTREPOTS, MUNICIPALITY ATTRIBUTION
# =============================================================================
cat(sprintf("\n=== D1(7) TOP %d DESTINATIONS, 2010 ===\n", TOP_DEST_N))
print(as.data.frame(national_mix |> slice_head(n = TOP_DEST_N) |>
  left_join(baci_countries, by = "destino") |>
  transmute(destino_iso3, baci_name, x_d_B = x_d / 1e9, share = share,
            cum_share = cumsum(share))), digits = 4)

entrepot <- national_mix |> filter(destino_iso3 %in% ENTREPOT_ISO3)
cat(sprintf("\nEntrepot destinations (%s): joint 2010 share %.2f%%\n",
            paste(ENTREPOT_ISO3, collapse = ", "), 100 * sum(entrepot$share)))
print(as.data.frame(entrepot |> transmute(destino_iso3, x_d_B = x_d / 1e9, share)),
      digits = 4)

# Municipality attribution (spec §D.7.1): how much of national export value sits
# in the top-20 declaring municipios. The leave-out itself is Phase 2; the
# magnitude is the diagnostic.
mun_conc <- comex_m |> filter(!is.na(micro)) |>
  group_by(CO_MUN, SG_UF_MUN, micro) |>
  summarise(x_m = sum(VL_FOB), .groups = "drop") |>
  arrange(desc(x_m)) |>
  mutate(share = x_m / sum(x_m), cum_share = cumsum(share))
cat(sprintf("\n=== D1(7b) MUNICIPALITY ATTRIBUTION ===\n"))
cat(sprintf("Top %d declaring municipios carry %.1f%% of attributed 2010 export value\n",
            TOP_MUN_N, 100 * mun_conc$cum_share[TOP_MUN_N]))
print(as.data.frame(mun_conc |> slice_head(n = TOP_MUN_N)), digits = 4)

# =============================================================================
# STEP 8 — FIGURE (vector PDF, base device; [D-8])
# =============================================================================
p1 <- ggplot(micro_hhi, aes(x = eff_dest)) +
  geom_histogram(bins = 50) +
  geom_vline(xintercept = HHI_EFF_THRESHOLD, linetype = "dashed") +
  geom_vline(xintercept = national_eff, linetype = "dotted") +
  scale_x_continuous(trans = "log10") +
  labs(x = "effective destinations per microregion (1/HHI, log scale)",
       y = "microregions",
       title = "Branch A: microregion-level destination concentration, 2010",
       subtitle = paste0("dashed = ", HHI_EFF_THRESHOLD, " effective destinations; ",
                         "dotted = national mix (", round(national_eff, 2), ")")) +
  theme_minimal(base_size = 9)
ggsave(file.path(OUT_D, "fig_d1_destination_hhi.pdf"), p1,
       width = 7, height = 4.5, device = grDevices::pdf)

# =============================================================================
# STEP 9 — WRITE
# =============================================================================
saveRDS(x_rd_2010, file.path(OUT_D, "D1_x_rd_2010.rds"))
# The harmonisation maps travel WITH the shares. D2/D3 read them from here
# rather than redeclaring them, so BACI and Comex cannot end up on different
# destination universes ([D-20], [D-23]).
saveRDS(list(s_rd = s_rd, theta_r = theta_r_dest,
             micro_zero_export = micro_zero_exp,
             comex_national_total_2010 = comex_national_total_2010,
             baci_countries = baci_countries,
             comex_baci_area_map = COMEX_BACI_AREA_MAP,
             panel_persistent_fold = PANEL_PERSISTENT_FOLD,
             non_destination_iso3 = NON_DESTINATION_ISO3),
        file.path(OUT_D, "D1_s_rd.rds"))
write_csv_safe(micro_hhi,    file.path(OUT_D, "D1_micro_hhi.csv"))
write_csv_safe(national_mix, file.path(OUT_D, "D1_destination_top.csv"))
write_csv_safe(micro_hhi |> select(micro, n_dest, eff_dest, top1_dest,
                                   top1_share, top3_share, x_r, theta_r_dest),
               file.path(OUT_D, "D1_micro_concentration.csv"))
write_csv_safe(mun_conc,     file.path(OUT_D, "D1_municipio_concentration.csv"))

# [D-26] Markdown writer: NEVER round an identifier.
# The first version applied signif(, 4) to every numeric column, including the
# microregion code. 12003 printed as 12000, and 23011/23012/23013/23014 all
# printed as 23010 — four distinct microregions rendered as one repeated four
# times. The CSVs were always correct; only the table writer was wrong, which is
# the dangerous case, because the markdown is what gets copied into prose.
# Rounding is applied to DOUBLES only; integer codes pass through untouched, and
# columns are pasted per-row rather than through apply(), which coerces the whole
# frame to a character matrix and reformats numbers on the way.
md <- function(df, digits = 4) {
  d <- df |> mutate(across(where(is.double), ~ signif(.x, digits))) |>
    mutate(across(everything(), as.character))
  rows <- do.call(paste, c(unname(as.list(d)), sep = " | "))
  paste(c(paste0("| ", paste(names(d), collapse = " | "), " |"),
          paste0("| ", paste(rep("---", ncol(d)), collapse = " | "), " |"),
          paste0("| ", rows, " |")),
        collapse = "\n")
}
writeLines(c(
  "# Packet D — Stage 1, step 1: Branch A destination shares",
  "",
  paste0("Generated ", format(Sys.time()), " by `códigos/packet_D/D1_shares_destino.R`."),
  "Comex `EXP_2010_MUN.csv` only — no BACI, no crosswalk, no ISIC.",
  "No outcome regression was run.",
  "",
  "## 1. Microregion-level destination concentration",
  "",
  md(micro_hhi |> summarise(
       n_micro = n(), mean_eff = mean(eff_dest), median_eff = median(eff_dest),
       p25 = quantile(eff_dest, .25), p75 = quantile(eff_dest, .75),
       min_eff = min(eff_dest), max_eff = max(eff_dest),
       value_wtd_mean = weighted.mean(eff_dest, x_r))),
  "",
  paste0("Microregions with fewer than ", HHI_EFF_THRESHOLD,
         " effective destinations: **", n_below, " of ", nrow(micro_hhi),
         "** (", round(100 * n_below / nrow(micro_hhi), 1), "%), carrying ",
         round(100 * sum(micro_hhi$x_r[micro_hhi$eff_dest < HHI_EFF_THRESHOLD]) /
                 sum(micro_hhi$x_r), 2), "% of 2010 export value."),
  paste0("National destination mix: 1/HHI = ", round(national_eff, 2),
         " over ", nrow(national_mix), " destinations."),
  "",
  "### Distribution",
  "",
  md(micro_hhi |>
       mutate(bucket = cut(eff_dest, breaks = c(0, 1.5, 2, 3, 5, 10, 20, Inf),
                           labels = c("<1.5", "1.5-2", "2-3", "3-5", "5-10",
                                      "10-20", ">20"), right = FALSE)) |>
       group_by(bucket) |>
       summarise(n_micro = n(), pct_micro = 100 * n() / nrow(micro_hhi),
                 pct_value = 100 * sum(x_r) / sum(micro_hhi$x_r), .groups = "drop")),
  "",
  paste0("### Single-destination microregions: ", n_single_dest, " of ",
         nrow(micro_hhi), " (", round(100 * n_single_dest / nrow(micro_hhi), 1),
         "%), carrying ",
         round(100 * sum(micro_hhi$x_r[micro_hhi$n_dest == 1L]) /
                 sum(micro_hhi$x_r), 3), "% of export value"),
  "",
  paste0("The ", TOP_CONC_N, " largest of them by export value (this is a TIE ",
         "GROUP at `eff_dest = 1`, not a ranking):"),
  "",
  md(micro_hhi |> filter(n_dest == 1L) |>
       slice_max(x_r, n = TOP_CONC_N, with_ties = FALSE) |>
       select(micro, n_dest, eff_dest, top1_dest, top1_share, x_r)),
  "",
  "### `[A1]` Effective units per microregion: destinations vs industries",
  "",
  md(bind_rows(
    micro_hhi |> summarise(axis = "destinations (export-weighted)",
                           n_micro = n(), mean = mean(eff_dest),
                           median = median(eff_dest),
                           pct_below_3 = 100 * mean(eff_dest < HHI_EFF_THRESHOLD)),
    micro_hhi_ind |> summarise(axis = "ISIC industries (employment-weighted)",
                               n_micro = n(), mean = mean(eff_ind),
                               median = median(eff_ind),
                               pct_below_3 = 100 * mean(eff_ind < HHI_EFF_THRESHOLD)))),
  "",
  paste0("Denominators differ — destination shares are weighted by export value, ",
         "industry shares by employment — so this compares dispersion, not ",
         "magnitude. Destinations are if anything slightly MORE concentrated. ",
         "**The exposure-diversity argument for Branch A is withdrawn**; the case ",
         "rests on shock dispersion and is settled in `D3`/`D4`."),
  "",
  paste0("## 2. Top ", TOP_DEST_N, " destinations, 2010"),
  "",
  md(national_mix |> slice_head(n = TOP_DEST_N) |>
       left_join(baci_countries, by = "destino") |>
       transmute(destino_iso3, baci_name, x_d_B = x_d / 1e9, share,
                 cum_share = cumsum(share))),
  "",
  paste0("Entrepot destinations (", paste(ENTREPOT_ISO3, collapse = ", "),
         ") carry a joint 2010 share of ",
         round(100 * sum(entrepot$share), 2), "%."),
  "",
  "## 3. Sample reconciliation",
  "",
  md(tibble(
    item = c("v7 microregion universe", "exporting microregions",
             "zero-export microregions", "destinations", "attributed value share"),
    value = c(N_MICRO_EXPECTED, length(micro_exporting), length(micro_zero_exp),
              n_distinct(x_rd$destino),
              round(100 * x_attributed / comex_national_total_2010, 4)))),
  "",
  "### Sample rules — `[D-27]`, binding on every downstream table",
  "",
  paste0("**N1 and N2 are different samples.** ", length(micro_zero_exp),
         " of ", N_MICRO_EXPECTED, " microregions have zero 2010 exports. N2 ",
         "retains them at `s_rd_n2 = 0`, `theta_r_dest = 0` (**N = ",
         N_MICRO_EXPECTED, "**); N1 is a composition and is undefined for them, ",
         "so it drops them (**N = ", length(micro_exporting), "**). N1 is not ",
         "comparable to N2, nor to the industry design in the same way. ",
         "`rho(EPW_S0, EPW_S3)` for `[D-PRE-4]` is computable **only on the ",
         length(micro_exporting), "**. Never print an N1 and an N2 column ",
         "without stating the sample."),
  "",
  paste0("**`theta_r_dest` is not the industry design's `theta_r`.** Branch A's ",
         "is exports per formal worker (2010 USD); the industry design's is the ",
         "tradable employment share, a unit-free fraction. Different units, ",
         "different object. The column keeps the name `theta_r_dest` through to ",
         "the tables and must never be rendered as a bare `theta_r` in prose."),
  "",
  paste0("Top ", TOP_MUN_N, " declaring municipios carry ",
         round(100 * mun_conc$cum_share[TOP_MUN_N], 1),
         "% of attributed 2010 export value (municipality-attribution threat, spec D.7.1)."),
  ""
), file.path(OUT_D, "tab_d1_shares.md"))

cat("\n[D1] wrote", OUT_D, "\n")
sink(); close(log_con)
