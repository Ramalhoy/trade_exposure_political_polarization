# =============================================================================
# G1 — is Section 5.1 real? Degenerate 2018 stack in the center-emptying index.
# Referee item R3-M1.
#
#   (1) verify P^N_{r,2018} is identically 1 across all microregions;
#   (2) re-estimate EVERY delta_P_center specification on 2014 + 2022 only;
#   (3) estimate the 2018 stack ALONE, labelled a share-balance diagnostic;
#   (4) re-run the symmetry Wald test on the two-year sample.
#
# Standardisation note: the treatment and controls keep the POOLED (three-stack)
# scaling of the main specification so that coefficients are directly comparable
# to Table 3. Re-standardising within the two-year subsample would rescale the
# units and make the comparison the gate asks for impossible. A re-standardised
# variant is reported alongside for completeness.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("G1")
B_RI <- 9999

# ---- (1) degeneracy of P^N by year ------------------------------------------
pol <- readRDS("dalton_panel_presidencial.rds")
deg <- pol |> group_by(year) |>
  summarise(n_micro = n(), mean_PN = mean(P_center), sd_PN = sd(P_center),
            min_PN = min(P_center), max_PN = max(P_center),
            pct_exactly_1 = 100 * mean(abs(P_center - 1) < 1e-12),
            n_distinct_PN = n_distinct(round(P_center, 12)), .groups = "drop")
cat("\n=== G1(1) P^N distribution by year (full index panel) ===\n")
print(as.data.frame(deg), digits = 6)

# same, restricted to the estimation universe
deg_est <- df_raw |> filter(micro %in% unique(df$micro)) |>
  group_by(year) |>
  summarise(n_micro = n(), mean_PN = mean(P_center), sd_PN = sd(P_center),
            min_PN = min(P_center), max_PN = max(P_center),
            pct_exactly_1 = 100 * mean(abs(P_center - 1) < 1e-12), .groups = "drop")
cat("\n=== G1(1b) P^N by year, estimation universe (557 micros) ===\n")
print(as.data.frame(deg_est), digits = 6)

# is delta_P_center_2018 a deterministic function of P_center_2010?
d18 <- df_scaled |> filter(year == 2018)
chk <- df |> filter(year == 2018) |>
  summarise(cor_dPN_base = cor(delta_P_center, P_center_2010),
            max_abs_dev  = max(abs(delta_P_center - (1 - P_center_2010))))
cat("\n=== G1(1c) is dP^N_2018 == 1 - P^N_2010 exactly? ===\n")
print(as.data.frame(chk), digits = 8)

# ---- estimation helpers ------------------------------------------------------
df_asym <- df_scaled |>
  mutate(epw_boom = pmax( delta_EPW_raw, 0) / sd_epw,
         epw_bust = pmax(-delta_EPW_raw, 0) / sd_epw)

est_one <- function(data, oc, ctrls, spec, fe, cl) {
  rhs <- if (spec == "pooled") "delta_EPW" else "epw_boom + epw_bust"
  m <- feols(as.formula(paste(oc, "~", rhs, "+", paste(ctrls, collapse = " + "),
                              "|", fe)), data = data, cluster = cl)
  m
}

tidy_rows <- function(m, keep, ...) {
  tibble(term = keep, beta = coef(m)[keep], se = se(m)[keep],
         t = coef(m)[keep] / se(m)[keep], n = nobs(m), ...)
}

sym_test <- function(m) {
  b <- coef(m)[c("epw_boom", "epw_bust")]
  V <- vcov(m)[c("epw_boom", "epw_bust"), c("epw_boom", "epw_bust")]
  cc <- sum(b); s <- sqrt(sum(V))
  dof <- fixest::degrees_freedom(m, type = "t")
  tibble(sum_b = cc, se_sum = s, t = cc / s, p = 2 * pt(-abs(cc / s), df = dof))
}

# =============================================================================
# (2) TWO-YEAR SAMPLE (2014 + 2022), all delta_P_center specifications
# =============================================================================
keep2 <- df_asym$year %in% c(2014, 2022)
d2    <- df_asym[keep2, ]
W2    <- W[keep2, , drop = FALSE]
yr2   <- df_asym$year[keep2]
idx2  <- cbind(seq_len(nrow(W2)), match(as.character(yr2), YEARS))

res2 <- bind_rows(
  map_dfr(c("base", "ext"), function(ck) {
    ctrls <- if (ck == "base") ctrl_base else ctrl_ext
    mp <- est_one(d2, "delta_P_center", ctrls, "pooled", "state^year", ~ mesoregion_code^year)
    md <- est_one(d2, "delta_P_center", ctrls, "decomp", "state^year", ~ mesoregion_code^year)
    bind_rows(tidy_rows(mp, "delta_EPW", sample = "2014+2022", ctrls = ck),
              tidy_rows(md, c("epw_boom", "epw_bust"), sample = "2014+2022", ctrls = ck))
  })
)

sym2 <- map_dfr(c("base", "ext"), function(ck) {
  ctrls <- if (ck == "base") ctrl_base else ctrl_ext
  md <- est_one(d2, "delta_P_center", ctrls, "decomp", "state^year", ~ mesoregion_code^year)
  sym_test(md) |> mutate(sample = "2014+2022", ctrls = ck, .before = 1)
})

# ---- three-year reference (Table 3) for side-by-side -------------------------
res3 <- map_dfr(c("base", "ext"), function(ck) {
  ctrls <- if (ck == "base") ctrl_base else ctrl_ext
  mp <- est_one(df_asym, "delta_P_center", ctrls, "pooled", "state^year", ~ mesoregion_code^year)
  md <- est_one(df_asym, "delta_P_center", ctrls, "decomp", "state^year", ~ mesoregion_code^year)
  bind_rows(tidy_rows(mp, "delta_EPW", sample = "2014+2018+2022", ctrls = ck),
            tidy_rows(md, c("epw_boom", "epw_bust"), sample = "2014+2018+2022", ctrls = ck))
})
sym3 <- map_dfr(c("base", "ext"), function(ck) {
  ctrls <- if (ck == "base") ctrl_base else ctrl_ext
  md <- est_one(df_asym, "delta_P_center", ctrls, "decomp", "state^year", ~ mesoregion_code^year)
  sym_test(md) |> mutate(sample = "2014+2018+2022", ctrls = ck, .before = 1)
})

# =============================================================================
# (3) 2018 STACK ALONE — SHARE-BALANCE DIAGNOSTIC, NOT AN OUTCOME REGRESSION
# =============================================================================
keep18 <- df_asym$year == 2018
d18a   <- df_asym[keep18, ]
W18    <- W[keep18, , drop = FALSE]
idx18  <- cbind(seq_len(nrow(W18)), rep(match("2018", YEARS), nrow(W18)))

res18 <- map_dfr(c("base", "ext"), function(ck) {
  ctrls <- if (ck == "base") ctrl_base else ctrl_ext
  mp <- est_one(d18a, "delta_P_center", ctrls, "pooled", "state", ~ mesoregion_code)
  md <- est_one(d18a, "delta_P_center", ctrls, "decomp", "state", ~ mesoregion_code)
  bind_rows(tidy_rows(mp, "delta_EPW", sample = "2018 only (BALANCE DIAGNOSTIC)", ctrls = ck),
            tidy_rows(md, c("epw_boom", "epw_bust"),
                      sample = "2018 only (BALANCE DIAGNOSTIC)", ctrls = ck))
})

# equivalent regression on the BASE-YEAR variable itself, to make the point
# explicit: dP^N_2018 = 1 - P^N_2010, so this is a regression of the 2010
# centrist vote share on 2018 export exposure, sign-flipped.
d18b <- d18a |> mutate(P_center_2010_z = as.numeric(scale(P_center_2010)))
m18_base <- feols(P_center_2010_z ~ delta_EPW + ln_gdp_pc + ln_pop +
                    tradable_emp_share | state, data = d18b,
                  cluster = ~ mesoregion_code)
cat("\n=== G1(3b) 2010 centrist vote share on 2018 exposure (same thing, sign-flipped) ===\n")
print(summary(m18_base))

# =============================================================================
# RANDOMIZATION INFERENCE on each sample
# =============================================================================
ri_block <- function(data, Wm, idx, ctrls, fe, label) {
  set.seed(2026)
  cz <- paste(ctrls, collapse = " + ")
  stats <- t(replicate(B_RI, {
    perm    <- sample(nrow(g_mat))
    epw_raw <- make_epw_star(perm, Wm = Wm, idx = idx)
    d <- data |> mutate(epw_star  = epw_raw / sd_epw,
                        boom_star = pmax( epw_raw, 0) / sd_epw,
                        bust_star = pmax(-epw_raw, 0) / sd_epw)
    p <- coef(feols(as.formula(paste("delta_P_center ~ epw_star +", cz, "|", fe)),
                    data = d, lean = TRUE))
    a <- coef(feols(as.formula(paste("delta_P_center ~ boom_star + bust_star +", cz,
                                     "|", fe)), data = d, lean = TRUE))
    c(pooled = p[["epw_star"]], boom = a[["boom_star"]], bust = a[["bust_star"]])
  }))
  saveRDS(stats, file.path(OUT, sprintf("ri_%s.rds", label)))
  stats
}

cat("\n[G1] running RI on the two-year sample (base controls)...\n")
ri2_base <- ri_block(d2, W2, idx2, ctrl_base, "state^year", "2yr_base")
cat("[G1] running RI on the two-year sample (ext controls)...\n")
ri2_ext  <- ri_block(d2, W2, idx2, ctrl_ext,  "state^year", "2yr_ext")
cat("[G1] running RI on the 2018 stack (base controls)...\n")
ri18_base <- ri_block(d18a, W18, idx18, ctrl_base, "state", "2018_base")
cat("[G1] running RI on the 2018 stack (ext controls)...\n")
ri18_ext  <- ri_block(d18a, W18, idx18, ctrl_ext,  "state", "2018_ext")

attach_ri <- function(res, ri_list) {
  key <- c(delta_EPW = "pooled", epw_boom = "boom", epw_bust = "bust")
  res |> rowwise() |>
    mutate(ri_p = {
      m <- ri_list[[paste0(sample_tag, "_", ctrls)]]
      p_ri(m[, key[[term]]], beta)
    },
    ri_sd = sd(ri_list[[paste0(sample_tag, "_", ctrls)]][, key[[term]]])) |>
    ungroup() |> mutate(sd_ratio = ri_sd / se)
}

ri_list <- list(`2yr_base` = ri2_base, `2yr_ext` = ri2_ext,
                `2018_base` = ri18_base, `2018_ext` = ri18_ext)

res2  <- res2  |> mutate(sample_tag = "2yr")  |> attach_ri(ri_list)
res18 <- res18 |> mutate(sample_tag = "2018") |> attach_ri(ri_list)

all_res <- bind_rows(res3 |> mutate(sample_tag = "3yr", ri_p = NA_real_,
                                    ri_sd = NA_real_, sd_ratio = NA_real_),
                     res2, res18) |>
  select(sample, ctrls, term, beta, se, t, ri_p, ri_sd, sd_ratio, n)

cat("\n=== G1(2)(3) delta_P_center: three-year vs two-year vs 2018-only ===\n")
print(as.data.frame(all_res), digits = 4)

# ---- (4) symmetry test on both samples --------------------------------------
sym_all <- bind_rows(sym3, sym2)
cat("\n=== G1(4) symmetry Wald test  H0: b_boom + b_bust = 0  (delta_P_center) ===\n")
print(as.data.frame(sym_all), digits = 4)

# ---- re-standardised two-year variant (units differ; reported for completeness)
d2r <- df[keep2, ] |>
  mutate(across(all_of(zvars), ~ as.numeric(scale(.))),
         epw_boom = pmax( df$delta_EPW[keep2], 0) / sd(df$delta_EPW[keep2]),
         epw_bust = pmax(-df$delta_EPW[keep2], 0) / sd(df$delta_EPW[keep2]))
res2r <- map_dfr(c("base", "ext"), function(ck) {
  ctrls <- if (ck == "base") ctrl_base else ctrl_ext
  mp <- est_one(d2r, "delta_P_center", ctrls, "pooled", "state^year", ~ mesoregion_code^year)
  md <- est_one(d2r, "delta_P_center", ctrls, "decomp", "state^year", ~ mesoregion_code^year)
  bind_rows(tidy_rows(mp, "delta_EPW", sample = "2014+2022 (re-standardised)", ctrls = ck),
            tidy_rows(md, c("epw_boom", "epw_bust"),
                      sample = "2014+2022 (re-standardised)", ctrls = ck))
})
sym2r <- map_dfr(c("base", "ext"), function(ck) {
  ctrls <- if (ck == "base") ctrl_base else ctrl_ext
  md <- est_one(d2r, "delta_P_center", ctrls, "decomp", "state^year", ~ mesoregion_code^year)
  sym_test(md) |> mutate(sample = "2014+2022 (re-standardised)", ctrls = ck, .before = 1)
})
cat("\n=== G1 re-standardised two-year variant ===\n")
print(as.data.frame(res2r), digits = 4)
print(as.data.frame(sym2r), digits = 4)

# ---- Dalton on the two-year sample, for reference ---------------------------
resD2 <- map_dfr(c("base", "ext"), function(ck) {
  ctrls <- if (ck == "base") ctrl_base else ctrl_ext
  mp <- est_one(d2, "delta_P_dalton", ctrls, "pooled", "state^year", ~ mesoregion_code^year)
  md <- est_one(d2, "delta_P_dalton", ctrls, "decomp", "state^year", ~ mesoregion_code^year)
  bind_rows(tidy_rows(mp, "delta_EPW", sample = "2014+2022", ctrls = ck),
            tidy_rows(md, c("epw_boom", "epw_bust"), sample = "2014+2022", ctrls = ck))
})
cat("\n=== G1 (reference) delta_P_dalton on 2014+2022, no RI ===\n")
print(as.data.frame(resD2), digits = 4)

write_csv(deg,     file.path(OUT, "G1_PN_degeneracy_by_year.csv"))
write_csv(deg_est, file.path(OUT, "G1_PN_degeneracy_estimation_universe.csv"))
write_csv(all_res, file.path(OUT, "G1_center_coefficients.csv"))
write_csv(bind_rows(sym_all, sym2r), file.path(OUT, "G1_symmetry_tests.csv"))
write_csv(res2r,   file.path(OUT, "G1_center_restandardised.csv"))
write_csv(resD2,   file.path(OUT, "G1_dalton_twoyear.csv"))
cat("\n[G1] wrote", OUT, "\n")
