# =============================================================================
# packet_I/I5_denominator.R  —  [I-5] GUARD ON THE DENOMINATOR.
#
# 02_polarization_indices.R filters !is.na(ideo) BEFORE summing votes, so the
# denominator of every index is the SCORED vote, not the cast vote. P3 item 2
# established the consequence: dropping a NON-neutral party mechanically raises
# the measured neutral share and lowers P^N. This script quantifies it rung by
# rung and decomposes the movement of P^N exactly.
#
# For a cell with scored set S and newly scored set A (disjoint):
#   P^N_S  = 1 - N_S / T_S                     N = neutral votes, T = total votes
#   P^N_S' = 1 - (N_S + N_A) / (T_S + T_A)
#   dP^N   = [ N_S/T_S - N_S/(T_S+T_A) ]  +  [ -N_A/(T_S+T_A) ]
#            \___ REWEIGHTING (denominator) __/  \__ COMPOSITION (numerator) __/
# The identity is asserted cell by cell, so the two channels cannot absorb an
# arithmetic error between them.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/packet_I/I0_setup.R")
OUT <- I_DIR("I5")
log_con <- file(file.path(OUT, "I5_denominator_log.txt"), open = "wt"); sink(log_con, split = TRUE)
cat("=== I5 denominator guard:", format(Sys.time()), "===\n\n")

W_PSL <- suppressWarnings(as.numeric(Sys.getenv("I_W_PSL", NA)))
RUNGS <- if (is.na(W_PSL)) c("V0", "V1", "V2") else c("V0", "V1", "V2", "V3")
cat("rungs:", paste(RUNGS, collapse = " -> "),
    if (is.na(W_PSL)) "(V3 skipped: I_W_PSL unset, [I-4] decision pending)\n" else
      sprintf("(V3 with w_PSL = %.5f)\n", W_PSL), "\n")

ideo_of <- function(v) if (v == "V3") build_ideo("V3", w_psl = W_PSL) else build_ideo(v)

# =============================================================================
# 1. COVERAGE, by rung / level / year
# =============================================================================
cov <- imap_dfr(VOTE_PANELS, function(v, nivel)
  map_dfr(RUNGS, function(r)
    coverage_by_year(attach_ideo(v, ideo_of(r))) |>
      mutate(variante = r, nivel = nivel)))
cov_w <- cov |> select(nivel, year, variante, pct_scored) |>
  pivot_wider(names_from = variante, values_from = pct_scored)
cat("=== I5(1) ideology coverage (% of the cast first-round vote) ===\n")
print(as.data.frame(cov_w), digits = 5)
cat("\n--- number of scored parties ---\n")
print(as.data.frame(cov |> select(nivel, year, variante, n_parties, n_scored) |>
                      pivot_wider(names_from = variante, values_from = n_scored,
                                  names_prefix = "scored_")), digits = 3)

# The baseline governor figure on record for 2018 is 86.5%, against 89.42% here.
# The gap is exactly the PSL-2018 <- BOLSONARO-2021 imputation, which 02 applies
# and which is preserved on every rung of this packet.
psl18 <- votes_gov |> filter(year == 2018) |>
  summarise(pct = 100 * sum(votes[sigla_key(party) == "PSL"], na.rm = TRUE) /
              sum(votes, na.rm = TRUE)) |> pull(pct)
g18 <- cov_w$V0[cov_w$nivel == "governador" & cov_w$year == 2018]
cat(sprintf("\n[I-5 note] governador 2018: V0 = %.3f%% | PSL-2018 patch = %.3f pp | without it = %.3f%%\n",
            g18, psl18, g18 - psl18))

# =============================================================================
# 2. DECOMPOSITION OF THE P^N MOVEMENT, rung by rung
# =============================================================================
cell_parts <- function(votes, ideo_tbl) {
  attach_ideo(votes, ideo_tbl) |> filter(!is.na(ideo)) |>
    mutate(neutral = as.integer(ideo >= -NEUTRAL_BAND & ideo <= NEUTRAL_BAND)) |>
    group_by(microregion_code, year) |>
    summarise(T = sum(votes, na.rm = TRUE),
              N = sum(votes * neutral, na.rm = TRUE), .groups = "drop")
}

steps <- map2_dfr(RUNGS[-length(RUNGS)], RUNGS[-1], function(a, b) {
  imap_dfr(VOTE_PANELS, function(v, nivel) {
    pa <- cell_parts(v, ideo_of(a)); pb <- cell_parts(v, ideo_of(b))
    j <- pa |> rename(T_S = T, N_S = N) |>
      inner_join(pb |> rename(T_new = T, N_new = N),
                 by = c("microregion_code", "year")) |>
      mutate(T_A = T_new - T_S, N_A = N_new - N_S,
             PN_old = 1 - N_S / T_S, PN_new = 1 - N_new / T_new,
             d_PN = PN_new - PN_old,
             reweighting = N_S / T_S - N_S / T_new,
             composition = -N_A / T_new,
             resid = d_PN - (reweighting + composition))
    stopifnot("P^N decomposition is not exact" = max(abs(j$resid)) < 1e-12)
    j |> group_by(year) |>
      summarise(n_cells = n(),
                mean_PN_old = mean(PN_old), mean_PN_new = mean(PN_new),
                d_PN = mean(d_PN), reweighting = mean(reweighting),
                composition = mean(composition),
                new_vote_pp = 100 * sum(T_A) / sum(T_new),
                new_vote_neutral_pp = 100 * sum(N_A) / sum(T_new),
                max_abs_resid = max(abs(resid)), .groups = "drop") |>
      mutate(passo = paste0(a, "->", b), nivel = nivel)
  })
})

cat("\n=== I5(2) movement of P^N, decomposed (means over microregions) ===\n")
print(as.data.frame(steps |> select(nivel, passo, year, mean_PN_old, mean_PN_new,
                                    d_PN, reweighting, composition,
                                    new_vote_pp, new_vote_neutral_pp)), digits = 4)
cat("\nmax |residual of the identity| over all cells and steps: ",
    sprintf("%.3e\n", max(steps$max_abs_resid)))

# cumulative V0 -> last rung
tot <- imap_dfr(VOTE_PANELS, function(v, nivel) {
  pa <- cell_parts(v, ideo_of("V0")); pb <- cell_parts(v, ideo_of(tail(RUNGS, 1)))
  pa |> rename(T_S = T, N_S = N) |>
    inner_join(pb |> rename(T_new = T, N_new = N), by = c("microregion_code", "year")) |>
    mutate(N_A = N_new - N_S,
           d_PN = (1 - N_new / T_new) - (1 - N_S / T_S),
           reweighting = N_S / T_S - N_S / T_new, composition = -N_A / T_new) |>
    group_by(year) |>
    summarise(d_PN = mean(d_PN), reweighting = mean(reweighting),
              composition = mean(composition), .groups = "drop") |>
    mutate(nivel = nivel, passo = paste0("V0->", tail(RUNGS, 1)))
})
cat("\n=== I5(2b) cumulative ===\n")
print(as.data.frame(tot |> select(nivel, passo, year, d_PN, reweighting, composition)),
      digits = 4)

# =============================================================================
# 3. P^D and P^N levels by rung (so the sign of the movement is on record)
# =============================================================================
lvls <- imap_dfr(VOTE_PANELS, function(v, nivel)
  map_dfr(RUNGS, function(r) {
    idx <- build_index(attach_ideo(v, ideo_of(r)))
    idx |> group_by(year) |>
      summarise(mean_PD = mean(P_dalton), sd_PD = sd(P_dalton),
                mean_PN = mean(P_center), pct_PN_degenerate = 100 * mean(abs(P_center - 1) < 1e-12),
                mean_n_scored = mean(n_scored), .groups = "drop") |>
      mutate(variante = r, nivel = nivel)
  }))
cat("\n=== I5(3) index levels by rung ===\n")
print(as.data.frame(lvls |> select(nivel, variante, year, mean_PD, sd_PD, mean_PN,
                                   pct_PN_degenerate, mean_n_scored)), digits = 4)

write_csv(cov,   file.path(OUT, "I5_coverage_by_rung.csv"))
write_csv(steps, file.path(OUT, "I5_PN_decomposition_steps.csv"))
write_csv(tot,   file.path(OUT, "I5_PN_decomposition_cumulative.csv"))
write_csv(lvls,  file.path(OUT, "I5_index_levels_by_rung.csv"))
cat("\n[I5] wrote", OUT, "\n")
sink(); close(log_con)
