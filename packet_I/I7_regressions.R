# =============================================================================
# packet_I/I7_regressions.R  —  [I-7] THE LADDER, ESTIMATED.
#
# For every rung: the 02 -> 06 -> 07 chain on the PRESIDENTIAL panel, then the
# full Table 3 -- beta, clustered SE, RI p (B = 9999, seed 2026), symmetry Wald --
# under base and extended controls, for dP^D and dP^N. Plus the P3-pattern index
# comparison: correlation old x new by year, decile migration, mean change by
# region.
#
# The chain is re-executed IN-SCRIPT rather than by overwriting
# dalton_panel_presidencial.rds / df_estimation_v7.rds. I1 part B proves the
# two routes coincide exactly under V0 (max |z(rebuilt) - panel| = 0 on both
# outcomes), so nothing is lost, and the canonical artefacts stay as the
# provenance of the published table -- same reason [T-5] froze
# ri_beta_distribution.rds.
#
# RI is re-run per rung. When a rung's outcome vector is bit-identical to one
# already permuted (V1 == V0 on the presidential panel: the crosswalk touches no
# presidential sigla), the placebo matrix is reused and the identity asserted,
# because permuting the same outcome with the same seed can only reproduce it.
#
# RUN THIS ALONE. fixest segfaults in long RI loops under process contention
# (revision/README).
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/packet_I/I0_setup.R")
OUT <- I_DIR("I7")
log_con <- file(file.path(OUT, "I7_regressions_log.txt"), open = "wt"); sink(log_con, split = TRUE)
cat("=== I7 ladder regressions:", format(Sys.time()), "===\n")

B_RI  <- 9999
SEED  <- 2026
W_PSL <- suppressWarnings(as.numeric(Sys.getenv("I_W_PSL", NA)))
RUNGS <- if (is.na(W_PSL)) c("V0", "V1", "V2") else c("V0", "V1", "V2", "V3")
cat("rungs:", paste(RUNGS, collapse = " -> "),
    if (is.na(W_PSL)) "(V3 skipped: I_W_PSL unset, [I-4] decision pending)" else
      sprintf("(V3 with w_PSL = %.5f, score = %.5f)", W_PSL, uniao_score(W_PSL)), "\n")
cat("B =", B_RI, "| seed =", SEED, "| nthreads =", getFixest_nthreads(), "\n\n")
ideo_of <- function(v) if (v == "V3") build_ideo("V3", w_psl = W_PSL) else build_ideo(v)

# =============================================================================
# 1. REBUILD THE OUTCOME ON EVERY RUNG  (02 -> 06)
# =============================================================================
idx <- set_names(map(RUNGS, ~ build_index(attach_ideo(votes_pres, ideo_of(.x)))), RUNGS)
dat <- set_names(map(RUNGS, function(v) {
  d <- build_delta(idx[[v]])
  out <- df_scaled |> left_join(d, by = c("micro", "year")) |>
    mutate(y_D = as.numeric(scale(dPD)), y_N = as.numeric(scale(dPN)),
           epw_boom = pmax( delta_EPW_raw, 0) / sd_epw,
           epw_bust = pmax(-delta_EPW_raw, 0) / sd_epw)
  stopifnot("outcome has NA after the rebuild" = !anyNA(out$y_D), !anyNA(out$y_N))
  out
}), RUNGS)

# V0 must reproduce the panel's own outcome exactly (the I1 part B identity)
stopifnot("V0 rebuild does not reproduce the estimation frame" =
            max(abs(dat$V0$y_D - dat$V0$delta_P_dalton)) < 1e-10 &&
            max(abs(dat$V0$y_N - dat$V0$delta_P_center)) < 1e-10)
cat("[I7] V0 rebuild == df_estimation_v7 outcome (max |diff| < 1e-10): OK\n")

sig <- map_chr(RUNGS, ~ rlang::hash(list(dat[[.x]]$y_D, dat[[.x]]$y_N)))
names(sig) <- RUNGS
cat("outcome fingerprints:\n"); print(sig)

# =============================================================================
# 2. TABLE 3 PER RUNG
# =============================================================================
fit_one <- function(d, oc, ctrls) {
  cz <- paste(ctrls, collapse = " + ")
  mp <- feols(as.formula(paste(oc, "~ delta_EPW +", cz, "| state^year")),
              data = d, cluster = ~ mesoregion_code^year)
  md <- feols(as.formula(paste(oc, "~ epw_boom + epw_bust +", cz, "| state^year")),
              data = d, cluster = ~ mesoregion_code^year)
  b <- coef(md)[c("epw_boom", "epw_bust")]
  V <- vcov(md)[c("epw_boom", "epw_bust"), c("epw_boom", "epw_bust")]
  cc <- sum(b); s <- sqrt(sum(V))
  bind_rows(
    tibble(term = "pooled", beta = coef(mp)[["delta_EPW"]], se = se(mp)[["delta_EPW"]],
           n = nobs(mp)),
    tibble(term = "boom", beta = b[["epw_boom"]], se = se(md)[["epw_boom"]], n = nobs(md)),
    tibble(term = "bust", beta = b[["epw_bust"]], se = se(md)[["epw_bust"]], n = nobs(md)),
    tibble(term = "symmetry", beta = cc, se = s, n = nobs(md),
           p_sym = 2 * pt(-abs(cc / s), df = fixest::degrees_freedom(md, type = "t"))))
}

est <- map_dfr(RUNGS, function(v) map_dfr(c("y_D", "y_N"), function(oc)
  map_dfr(c("base", "ext"), function(ck)
    fit_one(dat[[v]], oc, if (ck == "base") ctrl_base else ctrl_ext) |>
      mutate(variante = v, outcome = oc, ctrls = ck))))

# =============================================================================
# 3. RANDOMIZATION INFERENCE
# =============================================================================
ri_block <- function(d, ctrls) {
  set.seed(SEED); cz <- paste(ctrls, collapse = " + ")
  t(replicate(B_RI, {
    raw <- make_epw_star(sample(nrow(g_mat)))
    dd <- d |> mutate(epw_star = raw / sd_epw, boom_star = pmax(raw, 0) / sd_epw,
                      bust_star = pmax(-raw, 0) / sd_epw)
    f <- function(dv, rhs) coef(feols(as.formula(paste0(dv, " ~ ", rhs, " + ", cz,
                                                        " | state^year")),
                                      data = dd, lean = TRUE))
    pD <- f("y_D", "epw_star"); pN <- f("y_N", "epw_star")
    aD <- f("y_D", "boom_star + bust_star"); aN <- f("y_N", "boom_star + bust_star")
    c(y_D_pooled = pD[["epw_star"]], y_N_pooled = pN[["epw_star"]],
      y_D_boom = aD[["boom_star"]], y_D_bust = aD[["bust_star"]],
      y_N_boom = aN[["boom_star"]], y_N_bust = aN[["bust_star"]])
  }))
}

RI <- list()
for (v in RUNGS) {
  twin <- names(which(sig[RUNGS[seq_len(match(v, RUNGS) - 1)]] == sig[[v]]))[1]
  if (!is.na(twin) && length(twin)) {
    cat(sprintf("[I7] %s: outcome bit-identical to %s -> reusing its placebo matrices\n", v, twin))
    stopifnot(max(abs(dat[[v]]$y_D - dat[[twin]]$y_D)) == 0,
              max(abs(dat[[v]]$y_N - dat[[twin]]$y_N)) == 0)
    RI[[v]] <- RI[[twin]]
  } else {
    for (ck in c("base", "ext")) {
      cat(sprintf("[I7] RI %s / %s : %s\n", v, ck, format(Sys.time())))
      RI[[v]][[ck]] <- ri_block(dat[[v]], if (ck == "base") ctrl_base else ctrl_ext)
    }
  }
  saveRDS(RI[[v]], file.path(OUT, sprintf("I7_ri_%s.rds", v)))
}

est <- est |> rowwise() |>
  mutate(ri_p = { k <- paste0(outcome, "_", term); m <- RI[[variante]][[ctrls]]
                  if (!k %in% colnames(m)) NA_real_ else p_ri(m[, k], beta) },
         ri_sd = { k <- paste0(outcome, "_", term); m <- RI[[variante]][[ctrls]]
                   if (!k %in% colnames(m)) NA_real_ else sd(m[, k]) }) |>
  ungroup() |> mutate(sd_ratio = ri_sd / se,
                      outcome_lbl = if_else(outcome == "y_D", "dP^D", "dP^N"))

cat("\n=== I7(2) Table 3 across the ladder ===\n")
print(as.data.frame(est |> filter(term != "symmetry") |>
  select(outcome_lbl, ctrls, term, variante, beta, se, ri_p, sd_ratio) |>
  pivot_wider(names_from = variante, values_from = c(beta, se, ri_p, sd_ratio))),
  digits = 4)
cat("\n=== I7(2b) symmetry Wald (H0: beta_boom + beta_bust = 0) ===\n")
print(as.data.frame(est |> filter(term == "symmetry") |>
  select(outcome_lbl, ctrls, variante, sum_b = beta, se, p_sym)), digits = 4)
cat("\nN on every model:", paste(sort(unique(est$n)), collapse = "/"), "\n")

# =============================================================================
# 4. WHAT MOVED IN THE INDEX  (P3 pattern)
# =============================================================================
region_of <- function(code) {
  uf <- substr(as.character(code), 1, 2)
  case_when(uf %in% c("11","12","13","14","15","16","17") ~ "Norte",
            uf %in% c("21","22","23","24","25","26","27","28","29") ~ "Nordeste",
            uf %in% c("31","32","33","35") ~ "Sudeste",
            uf %in% c("41","42","43") ~ "Sul", TRUE ~ "Centro-Oeste")
}

cmp <- map_dfr(RUNGS[-1], function(v)
  idx$V0 |> select(microregion_code, year, PD0 = P_dalton, PN0 = P_center) |>
    inner_join(idx[[v]] |> select(microregion_code, year, PD1 = P_dalton, PN1 = P_center),
               by = c("microregion_code", "year")) |>
    mutate(variante = v))

chg <- cmp |> group_by(variante, year) |>
  summarise(n = n(), cor_PD = cor(PD0, PD1), cor_PN = suppressWarnings(cor(PN0, PN1)),
            mean_PD_V0 = mean(PD0), mean_PD_v = mean(PD1), d_mean_PD = mean(PD1 - PD0),
            sd_PD_V0 = sd(PD0), sd_PD_v = sd(PD1),
            d_mean_PN = mean(PN1 - PN0), max_abs_d_PD = max(abs(PD1 - PD0)),
            .groups = "drop")
cat("\n=== I7(4) index change vs V0, by year ===\n"); print(as.data.frame(chg), digits = 5)

dec <- map_dfr(RUNGS[-1], function(v) map_dfr(election_years, function(y) {
  s <- cmp |> filter(variante == v, year == y) |>
    mutate(d0 = ntile(PD0, 10), d1 = ntile(PD1, 10))
  tibble(variante = v, year = y, n = nrow(s), same = sum(s$d0 == s$d1),
         move1 = sum(abs(s$d0 - s$d1) == 1), move2plus = sum(abs(s$d0 - s$d1) >= 2),
         max_move = max(abs(s$d0 - s$d1)))
}))
cat("\n=== I7(4b) decile migration of P^D ===\n"); print(as.data.frame(dec))

reg <- cmp |> mutate(regiao = region_of(microregion_code)) |>
  group_by(variante, year, regiao) |>
  summarise(n = n(), d_PD = mean(PD1 - PD0), d_PN = mean(PN1 - PN0), .groups = "drop")
cat("\n=== I7(4c) mean change by region ===\n")
print(as.data.frame(reg |> pivot_wider(names_from = regiao, values_from = c(d_PD, d_PN)) |>
                      select(variante, year, starts_with("d_PD"))), digits = 3)

write_csv(est, file.path(OUT, "I7_table3_ladder.csv"))
write_csv(chg, file.path(OUT, "I7_index_change.csv"))
write_csv(dec, file.path(OUT, "I7_decile_migration.csv"))
write_csv(reg, file.path(OUT, "I7_change_by_region.csv"))
write_csv(cmp, file.path(OUT, "I7_index_old_vs_new.csv"))
saveRDS(list(est = est, chg = chg, idx = idx), file.path(OUT, "I7.rds"))
cat("\n[I7] wrote", OUT, "|", format(Sys.time()), "\n")
sink(); close(log_con)
