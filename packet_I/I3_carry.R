# =============================================================================
# packet_I/I3_carry.R  —  [I-3] CARRY, and the validation that licenses it.
#
# Rule: a party scored in a wave ADJACENT to the election's own wave, but not in
# that wave, carries the nearest wave. Ties resolve to the earlier (pre-election)
# wave. A party scored only in a distant wave is NOT carried (PSTU, 1993 only).
#
# The rule is only defensible if party positions are near-constant between
# consecutive waves RELATIVE to the dispersion the index measures. This script
# computes the comparison the packet requires: mean and max |dideo| for the same
# party across consecutive waves, against the SD of ideo across parties within a
# wave. If a carried score moves a party by an amount comparable to the spread
# the index is built on, the carry is not a measurement fix but an assumption.
#
# Writes the carry ledger (which sigla, which year, from which wave, how far the
# score moved) so every carried cell is auditable.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/packet_I/I0_setup.R")
OUT <- I_DIR("I3")
log_con <- file(file.path(OUT, "I3_carry_log.txt"), open = "wt"); sink(log_con, split = TRUE)
cat("=== I3 carry:", format(Sys.time()), "===\n\n")

# =============================================================================
# 1. WAVE-TO-WAVE STABILITY (the validation)
# =============================================================================
W_EST <- c(2009, 2013, 2017, 2021)      # waves feeding the four election years

pairs <- map_dfr(seq_len(length(W_EST) - 1), function(i) {
  a <- bls_waves |> filter(wave == W_EST[i])     |> select(rotulo_bls, ideo_a = ideo)
  b <- bls_waves |> filter(wave == W_EST[i + 1]) |> select(rotulo_bls, ideo_b = ideo)
  inner_join(a, b, by = "rotulo_bls") |>
    mutate(transicao = sprintf("%d->%d", W_EST[i], W_EST[i + 1]),
           d = ideo_b - ideo_a, abs_d = abs(d))
})

stab <- pairs |> group_by(transicao) |>
  summarise(n_parties = n(), mean_abs_d = mean(abs_d), median_abs_d = median(abs_d),
            max_abs_d = max(abs_d), argmax = rotulo_bls[which.max(abs_d)],
            .groups = "drop")

sd_between <- bls_waves |> filter(wave %in% W_EST) |> group_by(wave) |>
  summarise(n_parties = n(), sd_ideo = sd(ideo), .groups = "drop")

cat("=== I3(1) |delta ideo| for the SAME party between consecutive waves ===\n")
print(as.data.frame(stab), digits = 4)
cat("\n=== I3(1b) SD of ideo BETWEEN parties, within wave ===\n")
print(as.data.frame(sd_between), digits = 4)
cat(sprintf("\nPooled over the three transitions: n = %d | mean |d| = %.4f | max |d| = %.4f (%s, %s)\n",
            nrow(pairs), mean(pairs$abs_d), max(pairs$abs_d),
            pairs$rotulo_bls[which.max(pairs$abs_d)], pairs$transicao[which.max(pairs$abs_d)]))
cat(sprintf("Mean between-party SD across the four waves: %.4f\n", mean(sd_between$sd_ideo)))
cat(sprintf("RATIO  mean|d| / SD_between = %.3f   |   max|d| / SD_between = %.3f\n",
            mean(pairs$abs_d) / mean(sd_between$sd_ideo),
            max(pairs$abs_d)  / mean(sd_between$sd_ideo)))

cat("\n=== I3(1c) the full movement table, largest first ===\n")
print(as.data.frame(pairs |> arrange(desc(abs_d)) |>
                      select(transicao, party = rotulo_bls, ideo_a, ideo_b, d)), digits = 3)

# =============================================================================
# 2. THE CARRY LEDGER — what the rule actually does
# =============================================================================
v1 <- build_ideo("V1"); v2 <- build_ideo("V2")
carry <- attr(v2, "carry_detail") |>
  select(key, ano_eleicao, rotulo_bls, own_wave, carry_from_wave, ideo)

# how much does the carried score differ from the SAME party's own-wave score in
# the nearest wave on the other side (where one exists)? A diagnostic on the
# choice of neighbour, not on the carry itself.
alt <- carry |>
  left_join(bls_waves |> select(rotulo_bls, wave, ideo_alt = ideo),
            by = "rotulo_bls", relationship = "many-to-many") |>
  mutate(idx_own = match(own_wave, WAVES), dist = abs(match(wave, WAVES) - idx_own)) |>
  filter(dist == 1, wave != carry_from_wave) |>
  transmute(key, ano_eleicao, other_wave = wave, ideo_other = ideo_alt)
carry <- carry |> left_join(alt, by = c("key", "ano_eleicao")) |>
  mutate(gap_between_neighbours = ideo_other - ideo)

# vote weight of each carried cell, so the ledger says how much it matters
wt <- OBS_SIGLA_YEARS |> group_by(nivel, year) |>
  mutate(pct = 100 * votes / sum(votes)) |> ungroup() |>
  select(key, ano_eleicao = year, nivel, pct) |>
  pivot_wider(names_from = nivel, values_from = pct, names_prefix = "pct_")
carry <- carry |> left_join(wt, by = c("key", "ano_eleicao")) |>
  arrange(desc(coalesce(pct_governador, 0) + coalesce(pct_presidencial, 0)))

cat(sprintf("\n=== I3(2) carry ledger: %d (sigla, election) cells ===\n", nrow(carry)))
print(as.data.frame(carry |> select(key, ano_eleicao, rotulo_bls, own_wave,
                                    carry_from_wave, ideo, pct_governador,
                                    pct_presidencial, gap_between_neighbours)),
      digits = 4)
cat(sprintf("\nCells with a neighbour on BOTH sides (tie broken to the earlier wave): %d\n",
            sum(!is.na(carry$ideo_other))))
cat(sprintf("New scored vote added by V2 (pp of the national vote):\n"))
print(as.data.frame(carry |> summarise(gov  = sum(pct_governador,   na.rm = TRUE),
                                       pres = sum(pct_presidencial, na.rm = TRUE))),
      digits = 4)

# =============================================================================
# 3. ideo_source composition on the panels
# =============================================================================
src <- imap_dfr(VOTE_PANELS, function(v, nivel) {
  map_dfr(c("V0", "V1", "V2"), function(vr) {
    pi <- attach_ideo(v, build_ideo(vr))
    pi |> mutate(src = coalesce(ideo_source, "sem score")) |>
      group_by(year, src) |>
      summarise(votes = sum(votes, na.rm = TRUE), .groups = "drop") |>
      group_by(year) |> mutate(pct = 100 * votes / sum(votes)) |> ungroup() |>
      mutate(variante = vr, nivel = nivel)
  })
})
cat("\n=== I3(3) share of the vote by ideo_source ===\n")
print(as.data.frame(src |> select(nivel, variante, year, src, pct) |>
                      pivot_wider(names_from = src, values_from = pct, values_fill = 0)),
      digits = 4)

write_csv(pairs,      file.path(OUT, "I3_wave_movement.csv"))
write_csv(stab,       file.path(OUT, "I3_wave_stability.csv"))
write_csv(sd_between, file.path(OUT, "I3_sd_between_parties.csv"))
write_csv(carry,      file.path(OUT, "I3_carry_ledger.csv"))
write_csv(src,        file.path(OUT, "I3_ideo_source_shares.csv"))
cat("\n[I3] wrote", OUT, "\n")
sink(); close(log_con)
