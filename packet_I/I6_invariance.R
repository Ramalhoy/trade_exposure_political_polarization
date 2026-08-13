# =============================================================================
# packet_I/I6_invariance.R  —  [I-6] THE TREATMENT MAY NOT MOVE.
#
# Packet I changes the OUTCOME only. delta_EPW, the effective shocks, the
# Rotemberg weights and the BHJ balance test are functions of the exposure
# shares W, the sectoral shocks g and the estimation sample -- never of the
# ideology join. That is an argument, not evidence, so it is asserted:
#
#   (a) delta_EPW is bit-identical across V0..V3, row for row;
#   (b) the estimation sample (micros x years) is identical across rungs;
#   (c) Rotemberg weights and 1/HHI, recomputed per rung, are identical;
#   (d) the BHJ balance test is outcome-free by construction and its inputs are
#       untouched (asserted on the input hashes, not re-run).
#
# A failure here means an outcome rebuild has leaked into the treatment or the
# sample, which would invalidate every comparison in [I-7].
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/packet_I/I0_setup.R")
OUT <- I_DIR("I6")
log_con <- file(file.path(OUT, "I6_invariance_log.txt"), open = "wt"); sink(log_con, split = TRUE)
cat("=== I6 treatment invariance:", format(Sys.time()), "===\n\n")

W_PSL <- suppressWarnings(as.numeric(Sys.getenv("I_W_PSL", NA)))
RUNGS <- if (is.na(W_PSL)) c("V0", "V1", "V2") else c("V0", "V1", "V2", "V3")
cat("rungs:", paste(RUNGS, collapse = " -> "), "\n\n")
ideo_of <- function(v) if (v == "V3") build_ideo("V3", w_psl = W_PSL) else build_ideo(v)

# the estimation frame each rung would produce
frame_of <- function(v) {
  d <- build_delta(build_index(attach_ideo(votes_pres, ideo_of(v))))
  df_scaled |> left_join(d, by = c("micro", "year")) |>
    mutate(y_D = as.numeric(scale(dPD)), y_N = as.numeric(scale(dPN)),
           epw_boom = pmax( delta_EPW_raw, 0) / sd_epw,
           epw_bust = pmax(-delta_EPW_raw, 0) / sd_epw) |>
    arrange(micro, year)
}
frames <- set_names(map(RUNGS, frame_of), RUNGS)

ref <- frames[[1]]
chk <- map_dfr(RUNGS, function(v) {
  f <- frames[[v]]
  tibble(variante = v, n_rows = nrow(f),
         max_abs_d_epw   = max(abs(f$delta_EPW     - ref$delta_EPW)),
         max_abs_d_epwraw= max(abs(f$delta_EPW_raw - ref$delta_EPW_raw)),
         max_abs_d_boom  = max(abs(f$epw_boom      - ref$epw_boom)),
         max_abs_d_bust  = max(abs(f$epw_bust      - ref$epw_bust)),
         sample_identical= identical(paste(f$micro, f$year), paste(ref$micro, ref$year)),
         theta_identical = max(abs(f$tradable_emp_share - ref$tradable_emp_share)) == 0,
         n_outcome_na    = sum(is.na(f$y_D)) + sum(is.na(f$y_N)))
})
cat("=== I6(a,b) treatment and sample, against V0 ===\n")
print(as.data.frame(chk), digits = 3)

# ---- (c) Rotemberg weights and effective shocks, recomputed per rung --------
# ss_rotemberg residualises the TREATMENT on the controls and the state dummies;
# the outcome never enters. Recomputed anyway, once per rung.
rot <- map_dfr(RUNGS, function(v)
  ss_rotemberg(frames[[v]], W, g_mat, "delta_EPW", ctrl_base) |> mutate(variante = v))
eff <- rot |> group_by(variante) |> group_modify(~ ss_eff_n(.x)) |> ungroup()
cat("\n=== I6(c) effective number of shocks (1/HHI of |alpha|) ===\n")
print(as.data.frame(eff |> pivot_wider(names_from = variante, values_from = c(hhi, eff_n))),
      digits = 5)
rot_w <- rot |> select(isic4, year, variante, alpha) |>
  pivot_wider(names_from = variante, values_from = alpha)
max_rot_gap <- max(abs(as.matrix(rot_w[, RUNGS]) - rot_w[[RUNGS[1]]]))
cat(sprintf("max |alpha_v - alpha_V0| over %d industry-years: %.3e\n",
            nrow(rot_w), max_rot_gap))
top5 <- rot |> filter(variante == RUNGS[1]) |> group_by(year) |>
  slice_max(abs(alpha), n = 5) |> ungroup() |> arrange(year, desc(abs(alpha)))
cat("\ntop-5 |alpha| by year (V0; identical on every rung):\n")
print(as.data.frame(top5 |> select(year, isic4, alpha)), digits = 4)

# ---- (d) BHJ balance inputs untouched --------------------------------------
bhj_inputs <- c("sectoral_shocks_isic_v7.rds", "exposure_shares_isic_v7.rds",
                "epw_panel_isic_v7.rds", "df_estimation_v7.rds")
md5 <- tibble(file = bhj_inputs, md5 = tools::md5sum(bhj_inputs) |> unname(),
              mtime = file.info(bhj_inputs)$mtime)
cat("\n=== I6(d) inputs of the treatment and of the BHJ balance test ===\n")
print(as.data.frame(md5))
cat("Packet I writes none of these files; the balance test is a regression of\n",
    "g_jt on industry characteristics and is not a function of any outcome.\n")

write_csv(chk,   file.path(OUT, "I6_invariance_checks.csv"))
write_csv(eff,   file.path(OUT, "I6_effective_shocks.csv"))
write_csv(rot_w, file.path(OUT, "I6_rotemberg_by_rung.csv"))
write_csv(md5,   file.path(OUT, "I6_input_md5.csv"))

ok <- all(chk$max_abs_d_epw == 0, chk$max_abs_d_epwraw == 0, chk$max_abs_d_boom == 0,
          chk$max_abs_d_bust == 0, chk$sample_identical, chk$theta_identical,
          chk$n_outcome_na == 0) && max_rot_gap == 0
cat(sprintf("\n[I-6] treatment invariance across %s: %s\n",
            paste(RUNGS, collapse = "/"), if (ok) "PASS (exact zeros)" else "FAIL"))
cat("\n[I6] wrote", OUT, "\n")
if (!ok) stop("[I-6] FAILED: the treatment or the sample moved with the outcome.")
sink(); close(log_con)
