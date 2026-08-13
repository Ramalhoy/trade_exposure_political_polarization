# =============================================================================
# packet_I/I4_uniao.R  —  [I-4] UNIAO BRASIL 2022 by succession.
#
# UNIAO has no BLS label: the party did not exist when the 2021 wave was fielded.
# It is the fusion of DEM and PSL, homologated by the TSE on 08/02/2022, and both
# constituents ARE scored in the 2021 wave. The 2022 score is therefore built as
# a weighted mean of the two, and the whole content of the decision is the
# weight.
#
#   PRIMARY   bancada na Camara at the fusion date (Feb/2022)
#   FALLBACK  2018 governor vote of the two legends (computed here from the panel)
#
# The packet's stopping rule: if the two disagree by more than 0.05, report both
# and STOP before choosing. DEM and PSL sit 0.372 apart in the 2021 wave, so the
# score is a near-linear function of the weight and the two schemes cannot be
# expected to agree; the rule is doing real work here.
#
# NOT IN THIS PACKET: the PL-2022 question (party score vs Bolsonaro's individual
# score). It is a separate substantive change, recorded as P3 anomaly 5.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/packet_I/I0_setup.R")
OUT <- I_DIR("I4")
log_con <- file(file.path(OUT, "I4_uniao_log.txt"), open = "wt"); sink(log_con, split = TRUE)
cat("=== I4 UNIAO succession:", format(Sys.time()), "===\n\n")

TOL <- 0.05

ideo_dem <- bls_waves$ideo[bls_waves$wave == 2021 & bls_waves$rotulo_bls == "DEM"]
ideo_psl <- bls_waves$ideo[bls_waves$wave == 2021 & bls_waves$rotulo_bls == "PSL"]
cat(sprintf("BLS wave 2021: DEM = %.6f | PSL = %.6f | spread = %.4f\n",
            ideo_dem, ideo_psl, ideo_psl - ideo_dem))
cat(sprintf("=> d(score)/d(w_PSL) = %.4f, so a weight shift of %.3f moves the score by %.2f\n\n",
            ideo_psl - ideo_dem, TOL / (ideo_psl - ideo_dem), TOL))

# ---- FALLBACK weight: 2018 governor vote ------------------------------------
gov18 <- votes_gov |> filter(year == 2018) |> mutate(key = sigla_key(party)) |>
  filter(key %in% c("DEM", "PSL")) |>
  group_by(key) |> summarise(votes = sum(votes, na.rm = TRUE), .groups = "drop")
v_dem <- gov18$votes[gov18$key == "DEM"]; v_psl <- gov18$votes[gov18$key == "PSL"]
w_vote <- v_psl / (v_dem + v_psl)
cat(sprintf("FALLBACK  2018 governor vote: DEM = %d | PSL = %d | w_PSL = %.4f\n",
            v_dem, v_psl, w_vote))

# ---- PRIMARY weight: Chamber bench at the fusion --------------------------
# Documentary inputs, not computed from any pipeline artefact. Two published
# counts exist for the same object and both are reported, because the choice
# between them is smaller than the choice of scheme.
bench <- tribble(
  ~esquema,          ~dep_dem, ~dep_psl, ~fonte,
  "bancada 2021-10",       28L,      54L,
  "CNN Brasil, 06/10/2021 (aprovacao da fusao pelos dois partidos): PSL 54, DEM 28, total 82",
  "eleitos 2018",          29L,      52L,
  "deputados federais eleitos em 2018 pelas duas legendas (81 no total; Wikipedia/TSE)")

res <- bench |>
  mutate(w_psl = dep_psl / (dep_dem + dep_psl),
         score = (1 - w_psl) * ideo_dem + w_psl * ideo_psl) |>
  bind_rows(tibble(esquema = "voto governador 2018", dep_dem = NA_integer_,
                   dep_psl = NA_integer_,
                   fonte = "painel_votos_governador_microregioes_2010_2022.rds, 1o turno",
                   w_psl = w_vote,
                   score = (1 - w_vote) * ideo_dem + w_vote * ideo_psl)) |>
  mutate(papel = c("primario", "primario (variante)", "fallback"))

cat("\n=== I4(1) UNIAO 2022 score under each weighting scheme ===\n")
print(as.data.frame(res |> select(papel, esquema, dep_dem, dep_psl, w_psl, score)), digits = 5)

primary  <- res$score[res$papel == "primario"]
fallback <- res$score[res$papel == "fallback"]
gap <- abs(primary - fallback)
cat(sprintf("\nPRIMARY  (bancada 2021-10) = %.6f\nFALLBACK (voto gov 2018)   = %.6f\nGAP = %.4f (tolerance %.2f)\n",
            primary, fallback, gap, TOL))

# Where the score lands relative to the neutral band and to the parties around it
cat("\n=== I4(2) where each candidate score sits ===\n")
neigh <- bls_waves |> filter(wave == 2021) |> arrange(ideo) |>
  select(rotulo_bls, ideo)
for (s in sort(res$score)) {
  lo <- neigh |> filter(ideo <= s) |> slice_tail(n = 1)
  hi <- neigh |> filter(ideo >  s) |> slice_head(n = 1)
  cat(sprintf("  %.4f  between %s (%.3f) and %s (%.3f) | fora da banda neutra: %s\n",
              s, lo$rotulo_bls, lo$ideo, hi$rotulo_bls, hi$ideo,
              if (abs(s) > NEUTRAL_BAND) "sim" else "NAO"))
}
cat(sprintf("\nAll candidate scores are outside the neutral band [%.2f, %.2f]: %s\n",
            -NEUTRAL_BAND, NEUTRAL_BAND, all(abs(res$score) > NEUTRAL_BAND)))
cat("=> the choice of weight cannot flip UNIAO between neutral and non-neutral,\n",
    "   so P^N is invariant to it; only P^D (dispersion) moves.\n")

# Sensitivity of the index to the weight, at the extremes and at both schemes
cat("\n=== I4(3) 2022 index sensitivity to w_PSL (presidencial e governador) ===\n")
sens <- map_dfr(c(0, w_vote, res$w_psl[res$papel == "primario"], 1), function(w) {
  it <- build_ideo("V3", w_psl = w)
  imap_dfr(VOTE_PANELS, function(v, nivel) {
    idx <- build_index(attach_ideo(v |> filter(year == 2022), it))
    tibble(nivel = nivel, w_psl = w, score = uniao_score(w),
           mean_PD = mean(idx$P_dalton), sd_PD = sd(idx$P_dalton),
           mean_PN = mean(idx$P_center))
  })
})
print(as.data.frame(sens |> arrange(nivel, w_psl)), digits = 5)

write_csv(res,  file.path(OUT, "I4_uniao_weights.csv"))
write_csv(sens, file.path(OUT, "I4_uniao_sensitivity.csv"))
cat("\n[I4] wrote", OUT, "\n")

if (gap > TOL) {
  cat(sprintf("\n[I-4] STOP: the two weighting schemes differ by %.4f > %.2f.\n", gap, TOL))
  cat("Report both and obtain a decision before V3 is estimated.\n")
}
sink(); close(log_con)
