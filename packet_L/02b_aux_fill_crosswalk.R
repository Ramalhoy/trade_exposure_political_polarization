# =============================================================================
# 02b_aux_fill_crosswalk.R  —  L3' : build party_crosswalk_bls.csv
# -----------------------------------------------------------------------------
# Packet L amendment, stage L3'. Writes the crosswalk deterministically from
# (a) the carry-expanded BLS availability set and (b) a DECLARED renaming table.
#
# SCOPE, per the amendment: RENAMINGS ONLY. The unscored tail stays unmatched and
# needs no judgement. Mergers are NOT renamings and are excluded here — UNIÃO is
# [PL-42], optional, and must not become a dependency.
#
# BASIS FOR `verified = TRUE` ON THE RENAMING ROWS
#   Each row is a legal renaming of a continuing party, not an inference about
#   whose score is whose. There is also direct internal evidence in the BLS file
#   itself: it labels parties with their MODERN sigla RETROACTIVELY. MDB, DEM, PL
#   and CID all carry scores from the 1990 wave, when those parties were legally
#   PMDB, PFL, PL and PCB/PPS respectively. A file that back-labels PMDB as "MDB"
#   in 1990 is a file whose series follow the legal party across renamings, which
#   is exactly what these rows assert.
#
#   THIS IS NOT A CODEBOOK PAGE CITE. If Zucco & Power's codebook contradicts any
#   row, the codebook wins and the row must be corrected here. The rows most worth
#   a spot-check are PR->PL (a 2006 merger with PRONA sits inside that lineage)
#   and CID (PCB -> PPS -> Cidadania is a long chain).
#
# OUTPUT: party_crosswalk_bls.csv  (overwritten; previous copy kept as .bak)
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
suppressMessages({library(dplyr); library(tidyr); library(stringr); library(tibble)})

write_csv_safe <- function(x, path) {            # [PL-35]
  utils::write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8"); invisible(path)
}

# ---- carry-expanded availability, identical rule to [PL-37] in 02b ----------
ideologia  <- readRDS("bls9_estimates_partiespresidents_long.rds")
PRESIDENTS <- c("BOLSONARO","COLLOR","DILMA","FHC","ITAMAR","LULA","SARNEY","TEMER")
WAVES      <- sort(unique(ideologia$year))
wave_pos   <- setNames(seq_along(WAVES), as.character(WAVES))
scored     <- ideologia |> filter(!party.or.pres %in% PRESIDENTS) |>
                select(bls_label = party.or.pres, wave = year)

resolve_wave <- function(lbl, home) {
  av <- scored$wave[scored$bls_label == lbl]
  if (home %in% av) return(home)
  hp <- wave_pos[[as.character(home)]]
  cand <- integer(0)
  if (hp - 1L >= 1L            && WAVES[hp - 1L] %in% av) cand <- c(cand, WAVES[hp - 1L])
  if (hp + 1L <= length(WAVES) && WAVES[hp + 1L] %in% av) cand <- c(cand, WAVES[hp + 1L])
  if (!length(cand)) NA_integer_ else min(cand)
}

avail <- expand_grid(bls_label = sort(unique(scored$bls_label)), year = election_years) |>
  rowwise() |>
  mutate(ideo_wave = resolve_wave(bls_label, year - 1L)) |>
  ungroup() |>
  filter(!is.na(ideo_wave)) |>
  select(bls_label, year)

# ---- TSE labels actually on the ballot, per year ----------------------------
tse <- readRDS("painel_votos_deputado_federal_microregioes_2010_2022.rds") |>
  mutate(party = str_trim(toupper(party))) |>
  summarise(votes = sum(votes, na.rm = TRUE), .by = c(year, party)) |>
  mutate(share = 100 * votes / sum(votes), .by = year)

# ---- DECLARED RENAMINGS (tse_party -> bls_label) ----------------------------
renames <- tribble(
  ~tse_party,      ~bls_label, ~basis,
  "PC DO B",       "PCDOB",    "orthography: TSE writes the sigla with spaces",
  "PMDB",          "MDB",      "renaming 2017: PMDB -> MDB, continuing legal party",
  "PR",            "PL",       "lineage PL (1985) -> PR (2006, merger with PRONA) -> PL (2019); BLS carries one continuous PL series from 1990",
  "PPS",           "CID",      "lineage PCB -> PPS -> Cidadania (2019); BLS CID series continuous from 1990",
  "CIDADANIA",     "CID",      "renaming 2019: PPS -> Cidadania",
  "PRB",           "REP",      "renaming 2019: PRB -> Republicanos; BLS REP scored in the 2017 and 2021 waves",
  "REPUBLICANOS",  "REP",      "renaming 2019: PRB -> Republicanos",
  "SOLIDARIEDADE", "SD",       "same party; BLS uses the short sigla SD",
  "PTN",           "PODE",     "renaming 2016: PTN -> Podemos; BLS PODE scored in the 2017 and 2021 waves",
  "PFL",           "DEM",      "renaming 2007: PFL -> DEM (not expected on a 2010+ ballot; kept for completeness)"
)

# ---- assemble ---------------------------------------------------------------
identity_rows <- avail |>
  semi_join(tse, by = c("year", "bls_label" = "party")) |>
  transmute(year, tse_party = bls_label, bls_label,
            basis = "identity: TSE label equals BLS label", verified = TRUE)

rename_rows <- expand_grid(renames, year = election_years) |>
  semi_join(tse,   by = c("year", "tse_party" = "party")) |>   # label on that ballot
  semi_join(avail, by = c("year", "bls_label")) |>             # target scored that year
  transmute(year, tse_party, bls_label, basis, verified = TRUE)

crosswalk <- bind_rows(identity_rows, rename_rows) |> arrange(year, tse_party)

stopifnot(
  "[PL-16] a TSE label maps to two BLS labels in the same year" =
    !any(duplicated(crosswalk[, c("year", "tse_party")])),
  "[PL-17] crosswalk targets a BLS label unavailable in that year" =
    nrow(anti_join(crosswalk, avail, by = c("year", "bls_label"))) == 0
)

CROSSWALK_PATH <- "party_crosswalk_bls.csv"
if (file.exists(CROSSWALK_PATH)) file.copy(CROSSWALK_PATH, paste0(CROSSWALK_PATH, ".bak"), overwrite = TRUE)
write_csv_safe(crosswalk, CROSSWALK_PATH)

cat("wrote", CROSSWALK_PATH, "-", nrow(crosswalk), "rows (",
    nrow(identity_rows), "identity,", nrow(rename_rows), "renaming )\n\n")
cat("--- RENAMING ROWS APPLIED ---\n")
print(as.data.frame(rename_rows |> select(year, tse_party, bls_label)), row.names = FALSE)

cat("\n--- DECLARED RENAMINGS THAT MATCHED NOTHING (check these) ---\n")
unused <- renames |> anti_join(rename_rows, by = c("tse_party", "bls_label"))
if (nrow(unused) == 0) cat("  none\n") else
  print(as.data.frame(unused |> select(tse_party, bls_label)), row.names = FALSE)

cat("\n--- TSE labels >= 0.5% of a year's vote left UNMATCHED (the unscored tail) ---\n")
left <- tse |> anti_join(crosswalk, by = c("year", "party" = "tse_party")) |>
  filter(share >= 0.5) |> arrange(year, desc(share)) |> mutate(share = round(share, 2))
print(as.data.frame(left |> select(year, party, share)), row.names = FALSE)
