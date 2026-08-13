# =============================================================================
# packet_I/I2_crosswalk_scan.R  —  [I-2] CROSSWALK: scan, then assert.
#
# The instruction is explicit that the supplied list of renames must NOT be
# assumed complete. This script sweeps BOTH vote panels, lists EVERY sigla that
# fails to match a BLS label under V0 ordered by national vote, and reports the
# disposition the versioned crosswalk assigns to each: matched by rename, to be
# resolved by carry ([I-3]), to be resolved by succession ([I-4]), or a recorded
# decision that no BLS label exists for it.
#
# ASSERTION THAT KILLS THE RUN: no sigla above 0.5% of the national vote in any
# panel-year may be left without a match AND without a recorded decision.
# I0_setup.R already enforces the stronger contract that every observed
# sigla-year has exactly one crosswalk row; this script enforces that for the
# consequential ones the row actually carries a decision, and reports the rung
# that resolves it.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/packet_I/I0_setup.R")
OUT <- I_DIR("I2")
log_con <- file(file.path(OUT, "I2_scan_log.txt"), open = "wt"); sink(log_con, split = TRUE)
cat("=== I2 crosswalk scan:", format(Sys.time()), "===\n\n")

THRESH_PCT <- 0.5

# =============================================================================
# 1. National vote by sigla, level and year; match status on every rung
# =============================================================================
tot <- OBS_SIGLA_YEARS |> group_by(nivel, year) |>
  summarise(total_votes = sum(votes), .groups = "drop")

status_on <- function(tbl, tag) tbl |> distinct(key, ano_eleicao) |>
  transmute(key, year = ano_eleicao, !!tag := TRUE)

v0 <- build_ideo("V0"); v1 <- build_ideo("V1"); v2 <- build_ideo("V2")
# V3 adds exactly one row (UNIAO 2022); its score is not needed to know that the
# sigla is resolved there, so the scan uses a placeholder weight.
v3 <- build_ideo("V3", w_psl = 0.5)

scan <- OBS_SIGLA_YEARS |> left_join(tot, by = c("nivel", "year")) |>
  mutate(pct = 100 * votes / total_votes) |>
  left_join(status_on(v0, "in_V0"), by = c("key", "year")) |>
  left_join(status_on(v1, "in_V1"), by = c("key", "year")) |>
  left_join(status_on(v2, "in_V2"), by = c("key", "year")) |>
  left_join(status_on(v3, "in_V3"), by = c("key", "year")) |>
  mutate(across(starts_with("in_V"), ~ replace_na(., FALSE)),
         resolved_at = case_when(in_V0 ~ "V0 (ja casava)",
                                 in_V1 ~ "V1 crosswalk",
                                 in_V2 ~ "V2 carry",
                                 in_V3 ~ "V3 fusao",
                                 TRUE  ~ "sem score (decisao registrada)")) |>
  left_join(CROSSWALK |> select(key, rotulo_bls, data_renomeacao, fonte), by = "key") |>
  arrange(nivel, year, desc(pct))

cat("=== I2(1) coverage of the ideology join, by rung ===\n")
cov_rung <- scan |> group_by(nivel, year) |>
  summarise(V0 = 100 * sum(votes[in_V0]) / first(total_votes),
            V1 = 100 * sum(votes[in_V1]) / first(total_votes),
            V2 = 100 * sum(votes[in_V2]) / first(total_votes),
            V3 = 100 * sum(votes[in_V3]) / first(total_votes), .groups = "drop")
print(as.data.frame(cov_rung), digits = 5)

# =============================================================================
# 2. Every unmatched sigla under V0, ordered by vote
# =============================================================================
unmatched <- scan |> filter(!in_V0) |>
  select(nivel, year, party, key, votes, pct, resolved_at, rotulo_bls,
         data_renomeacao, fonte)
cat(sprintf("\n=== I2(2) siglas unmatched under V0: %d panel-year rows, %d distinct siglas ===\n",
            nrow(unmatched), n_distinct(unmatched$key)))
cat("--- above the", THRESH_PCT, "% decision threshold ---\n")
print(as.data.frame(unmatched |> filter(pct >= THRESH_PCT) |>
                      select(nivel, year, party, votes, pct, resolved_at, rotulo_bls)),
      digits = 4)
cat("\n--- below the threshold (reported, not decided individually) ---\n")
print(as.data.frame(unmatched |> filter(pct < THRESH_PCT) |>
                      select(nivel, year, party, pct, resolved_at)), digits = 3)

# aggregate view: the sigla, not the panel-year
by_sigla <- unmatched |> group_by(key) |>
  summarise(max_pct = max(pct), total_votes = sum(votes),
            anos = paste(sort(unique(year)), collapse = "/"),
            niveis = paste(sort(unique(nivel)), collapse = "+"),
            resolved_at = first(resolved_at), rotulo_bls = first(rotulo_bls),
            .groups = "drop") |> arrange(desc(max_pct))
cat("\n=== I2(2b) by sigla, ordered by the largest single panel-year share ===\n")
print(as.data.frame(by_sigla), digits = 4)

# =============================================================================
# 3. THE ASSERTION
# =============================================================================
consequential <- unmatched |> filter(pct >= THRESH_PCT)
no_decision <- consequential |>
  filter(resolved_at == "sem score (decisao registrada)" &
           (is.na(fonte) | !nzchar(trimws(fonte))))
cat(sprintf("\n=== I2(3) assertion ===\nsigla-years above %.1f%% unmatched under V0: %d\n",
            THRESH_PCT, nrow(consequential)))
cat(sprintf("of which resolved: V1 %d | V2 %d | V3 %d | decided-no-score %d\n",
            sum(consequential$resolved_at == "V1 crosswalk"),
            sum(consequential$resolved_at == "V2 carry"),
            sum(consequential$resolved_at == "V3 fusao"),
            sum(consequential$resolved_at == "sem score (decisao registrada)")))
cat(sprintf("without match AND without recorded decision: %d\n", nrow(no_decision)))

write_csv(scan,      file.path(OUT, "I2_sigla_scan_full.csv"))
write_csv(unmatched, file.path(OUT, "I2_unmatched_V0.csv"))
write_csv(by_sigla,  file.path(OUT, "I2_unmatched_by_sigla.csv"))
write_csv(cov_rung,  file.path(OUT, "I2_coverage_by_rung.csv"))
write_csv(CROSSWALK |> select(-key), file.path(OUT, "I2_party_crosswalk_applied.csv"))
cat("\n[I2] wrote", OUT, "\n")
if (nrow(no_decision))
  stop("[I-2] FAILED: sigla above ", THRESH_PCT, "% with neither match nor decision:\n",
       paste(sprintf("  %s %s %d (%.2f%%)", no_decision$nivel, no_decision$party,
                     no_decision$year, no_decision$pct), collapse = "\n"))
sink(); close(log_con)
