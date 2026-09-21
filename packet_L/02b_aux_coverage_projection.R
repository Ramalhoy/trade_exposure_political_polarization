# =============================================================================
# 02b_aux_coverage_projection.R   — DECISION AID, NOT A PIPELINE STAGE
# -----------------------------------------------------------------------------
# Packet L stage L3 (filling party_crosswalk_bls.csv from the Zucco & Power
# codebook) is a human step and is not delegable. It is also expensive. This
# script exists to answer, BEFORE that time is spent, a single question:
#
#     Even if the crosswalk were filled perfectly, would [PL-19]'s 15% coverage
#     gate pass?
#
# [PL-34] in 02b already computes an assumption-free UPPER BOUND, but that bound
# is deliberately loose: it lets any unmatched TSE party claim any spare BLS
# label in the wave, so it would happily "match" PSL to REDE. It is a valid
# bound and it rules 2014 out, but it cannot rule anything IN.
#
# This script computes the realistic counterpart: coverage under a crosswalk that
# resolves PURE LABEL DRIFT and nothing else.
#
# ***********************************************************************
# * THE MAPPING BELOW IS A HYPOTHESIS, NOT A VERIFIED CROSSWALK.         *
# * It is NOT written to party_crosswalk_bls.csv and sets no `verified`  *
# * flag anywhere. It exists only to bound the decision. L3 remains the  *
# * human step, to be settled against the codebook.                      *
# ***********************************************************************
#
# OUTPUTS: output/packet_L/tab_pl_coverage_projection.csv
#          output/packet_L/tab_pl_residual_unmatched.csv
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
suppressMessages({library(dplyr); library(stringr); library(tibble)})

write_csv_safe <- function(x, path) {            # [PL-35]
  utils::write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8"); invisible(path)
}
dir.create(file.path("output", "packet_L"), recursive = TRUE, showWarnings = FALSE)

votos <- readRDS("painel_votos_deputado_federal_microregioes_2010_2022.rds") |>
  mutate(party = str_trim(toupper(party)))

ideologia <- readRDS("bls9_estimates_partiespresidents_long.rds") |>
  mutate(ano_eleicao = year + 1)
PRESIDENTS <- c("BOLSONARO","COLLOR","DILMA","FHC","ITAMAR","LULA","SARNEY","TEMER")
bls <- ideologia |>
  filter(!party.or.pres %in% PRESIDENTS, ano_eleicao %in% election_years) |>
  select(bls_label = party.or.pres, year = ano_eleicao)

# ---- HYPOTHESISED LABEL DRIFT (see the warning above) -----------------------
# Each entry is a TSE ballot label that is plausibly the SAME legal party as a
# BLS label, on renaming or orthography alone. Mergers are deliberately absent:
# UNIÃO (DEM + PSL, 2022) is not a renaming and gets no entry, per [PL-15].
drift <- c(
  "PC DO B"      = "PCDOB",   # orthography only
  "PMDB"         = "MDB",     # renamed 2017
  "PR"           = "PL",      # PL -> PR (2006) -> PL (2019)
  "PPS"          = "CID",     # PPS -> Cidadania (2019)
  "CIDADANIA"    = "CID",
  "PRB"          = "REP",     # PRB -> Republicanos (2019)
  "REPUBLICANOS" = "REP",
  "SOLIDARIEDADE"= "SD",
  "PTN"          = "PODE",    # PTN -> Podemos (2016)
  "PFL"          = "DEM"      # renamed 2007
)

nat <- votos |>
  summarise(votes = sum(votes, na.rm = TRUE), .by = c(year, party)) |>
  mutate(share = 100 * votes / sum(votes), .by = year) |>
  mutate(bls_label = ifelse(party %in% names(drift), drift[party], party)) |>
  left_join(bls |> mutate(hit = TRUE), by = c("year", "bls_label")) |>
  mutate(hit = !is.na(hit))

proj <- nat |>
  summarise(matched_pct   = round(sum(share[hit]), 2),
            unmatched_pct = round(sum(share[!hit]), 2),
            n_matched     = sum(hit),
            n_unmatched   = sum(!hit), .by = year) |>
  mutate(passes_PL19 = unmatched_pct <= 15) |>
  arrange(year)

cat("\n--- PROJECTED COVERAGE, label drift resolved (HYPOTHESIS) ---\n")
print(as.data.frame(proj))
write_csv_safe(proj, file.path("output", "packet_L", "tab_pl_coverage_projection.csv"))

# ---- what is left, and why it cannot be crosswalked -------------------------
resid <- nat |>
  filter(!hit) |>
  mutate(reason = case_when(
    party == "PSL" & year == 2018 ~ "PSL 2018: scored only in the 2021 wave [PL-13]",
    grepl("^UNI", party)          ~ "UNIAO 2022: DEM+PSL merger, no BLS label [PL-15]",
    TRUE                          ~ "party never scored by BLS in the matching wave"),
    share = round(share, 3)) |>
  arrange(year, desc(share)) |>
  select(year, party, share, reason)
write_csv_safe(resid, file.path("output", "packet_L", "tab_pl_residual_unmatched.csv"))

cat("\n--- RESIDUAL UNMATCHED VOTE, BY REASON ---\n")
print(as.data.frame(resid |> summarise(pct = round(sum(share), 2), n_parties = n(),
                                       .by = c(year, reason)) |> arrange(year, desc(pct))),
      row.names = FALSE)

cat("\n--- LARGEST RESIDUALS (>= 0.5% of the year's vote) ---\n")
print(as.data.frame(resid |> filter(share >= 0.5)), row.names = FALSE)

cat("\nNOTE: this is a projection to size the decision. The authoritative\n",
    "crosswalk is still L3, and party_crosswalk_bls.csv is untouched.\n")
