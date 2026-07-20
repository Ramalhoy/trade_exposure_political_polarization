# =============================================================================
# 01_regressao_SFD_v3.R
# Stacked first-difference estimation + full inference regime + robustness.
# Reads the _v7 pipeline outputs (canonical audited protocol). Rationale in RATIONALE.md, section 2.
#
# Inference regime (unchanged):
#   PRIMARY   : design-based randomization p-values (shock permutation)
#   SECONDARY : analytical AKM / AKM0 (ShiftShareSE)
#   REFERENCE : mesoregion-by-year cluster + Conley spatial SEs
#
# CHANGES vs v2:
#   [A-1] CANONICAL SIGN CONVENTION: EPW+/EPW- entered as MAGNITUDES,
#         epw_bust = max(-dEPW,0)/sd, epw_boom = max(dEPW,0)/sd, matching
#         the model appendix (Prop. 1: b_bust > 0, b_boom <= 0). The signed
#         v2 coding (pmin/pmax) is retained ONLY inside the verification
#         block, which proves the recoding is a pure reparameterization
#         (bust coefficient flips sign exactly; fit identical).
#   [A-2] Raw treatment carried INSIDE df_scaled (delta_EPW_raw); all
#         cross-frame df$ references inside mutate() eliminated (silent-
#         misalignment hazard).
#   [A-3] missing_micro diagnostic moved AFTER df exists (v2 referenced df
#         before it was defined -- interactive-session artifact).
#   [A-4] Single centroid join (v2 joined twice, producing lon.x/lat.x and
#         a rename patch).
#   [A-5] Sample rule unified and asserted: identical N in every model.
#   [A-6] BHJ balance test weights = NATIONAL EMPLOYMENT SHARES
#         L_j / sum(L_j), not the unweighted mean of s_rj across regions.
#   [A-7] RI extended to the decomposed bust coefficient (headline result);
#         RI p-values reported for pooled AND bust.
#   [A-8] here() calls (package never loaded in v2) replaced by relative
#         paths + dir.create; header input list matches what is read.
#   [A-9] Sign-audit log written to output/sign_audit_log.txt.
# =============================================================================

source("C:/Users/Yago Ramalho/Documents/tema mestrado/data/códigos/_config.R")

library(tidyverse)
library(fixest)

set.seed(2026)

# ---- INPUTS (all _v7) -------------------------------------------------------
df_raw    <- readRDS("df_estimation_v7.rds")            # micro x year panel (outcomes + controls)
shares    <- readRDS("exposure_shares_isic_v7.rds")
shocks    <- readRDS("sectoral_shocks_isic_v7.rds")
epw_v7    <- readRDS("epw_panel_isic_v7.rds")           # v7 treatment
sumsh     <- readRDS("tradable_emp_share_2010_v7.rds")
centroids <- readRDS("micro_centroids.rds") |> mutate(micro = as.character(micro))

df_raw <- df_raw |> mutate(micro = as.character(microregion_code))
shares <- shares |> mutate(micro = as.character(micro))
sumsh  <- sumsh  |> mutate(micro = as.character(micro))
epw_v7 <- epw_v7 |> mutate(micro = as.character(micro))

# ---- [A-5] REBUILD delta_EPW FROM THE v7 PANEL ------------------------------
# The treatment must come from the corrected pipeline, not from whatever
# vintage produced df_estimation. Differences are vs the 2010 base (EPW_2010
# is identically 0 by construction, asserted in 00_v7, so delta = EPW_t).
df_raw <- df_raw |>
  select(-any_of("delta_EPW")) |>
  left_join(epw_v7 |> filter(year != 2010) |> select(micro, year, delta_EPW = EPW),
            by = c("micro", "year"))

# -----------------------------------------------------------------------------
# [G-1] ESTIMATION SAMPLE: stacked FDs only, t in {2014, 2018, 2022}
# -----------------------------------------------------------------------------
# ---- [A-10] EPW-UNIVERSE RESTRICTION (fatal-bug fix) ------------------------
# A microregion can appear in the polarization/controls panels yet be ABSENT
# from the RAIS-based EPW universe (no tradable-sector employment matched in
# 2010). Such a micro has no exposure shares AND no state/mesoregion label
# (those are carried by the EPW panel), so it cannot enter the state x year
# fixed effects nor the AKM share matrix. Retaining it silently breaks the
# secondary regime: ShiftShareSE::reg_ss builds its model frame with na.omit
# (dropping the NA-state rows) while W keeps them, so the row counts diverge and
# reg_ss aborts with "incompatible dimensions". feols likewise drops the rows,
# desyncing N. This is DISTINCT from the [G-1] retention rule: that rule keeps
# zero-tradable micros that ARE in the EPW universe (EPW = 0, state known);
# micros outside the universe are excluded here. As of the v7 pipeline this is
# exactly one micro (13002), reported below.
epw_micros    <- unique(epw_v7$micro)
excluded_micro <- setdiff(unique(df_raw$micro), epw_micros)
cat("Excluded (not in EPW universe):",
    if (length(excluded_micro)) paste(excluded_micro, collapse = ", ") else "none", "\n")

df <- df_raw |>
  filter(year != 2010) |>
  filter(micro %in% epw_micros) |>
  left_join(sumsh, by = "micro") |>
  mutate(tradable_emp_share = replace_na(tradable_emp_share, 0),
         delta_EPW          = replace_na(delta_EPW, 0),
         manuf_share        = replace_na(manuf_share, 0))
# Rule (unified, [A-5]): a microregion with zero bilateral tradable employment
# in 2010 has structurally zero exposure and a zero sum of shares -- it is
# RETAINED, with the BHJ control absorbing this as a baseline characteristic.
# Exclusion happens upstream only if a microregion lacks the data to define
# the outcome or denominator at all (handled by [A-10] above).

# [A-3] Diagnostic AFTER df exists:
missing_micro <- df |>
  filter(!micro %in% (sumsh |> filter(tradable_emp_share > 0) |> pull(micro))) |>
  distinct(micro, across(any_of(c("microregion_name", "state"))))
cat("Microregions with zero bilateral tradable employment (retained, EPW = 0):\n")
print(missing_micro)

stopifnot(
  "2010 rows leaked into estimation sample" = all(df$year %in% c(2014, 2018, 2022)),
  "tradable_emp_share missing"              = !anyNA(df$tradable_emp_share),
  "delta_EPW missing"                       = !anyNA(df$delta_EPW),
  "state label missing"                     = !anyNA(df$state)
)
N_SAMPLE <- nrow(df)
cat("Estimation sample:", N_SAMPLE, "raw obs |", n_distinct(df$micro), "micros |",
    n_distinct(df$year), "years\n")
# NOTE: the ESTIMATION N is below N_SAMPLE because feols removes state x year
# singletons (Distrito Federal has a single microregion, so each DF x year cell
# is a singleton -> 3 obs dropped). N_EST is fixed once the first models exist
# and every subsequent model is asserted against it ([A-5]).

# -----------------------------------------------------------------------------
# [G-2][G-3] STANDARDIZE on the estimation sample; define control sets
# -----------------------------------------------------------------------------
ctrl_base <- c("ln_gdp_pc", "ln_pop", "tradable_emp_share")
ctrl_ext  <- c(ctrl_base, "urban_share", "educ_share", "manuf_share")

outcomes  <- c("delta_P_dalton", "delta_P_center")
zvars     <- unique(c(outcomes, "delta_EPW", ctrl_ext))

df_scaled <- df |>
  mutate(delta_EPW_raw = delta_EPW) |>                       # [A-2]
  mutate(across(all_of(zvars), ~ as.numeric(scale(.))))
stopifnot(all(abs(colMeans(df_scaled[zvars], na.rm = TRUE)) < 1e-10))

# [A-4] single centroid join:
df_scaled <- df_scaled |>
  select(-any_of(c("lat", "lon", "long"))) |>
  left_join(centroids, by = "micro") |>
  rename(long = lon)
stopifnot("lat/lon missing after join" = !anyNA(df_scaled$lat) & !anyNA(df_scaled$long))

sd_epw <- sd(df$delta_EPW)   # scale anchor for both asymmetric codings

# -----------------------------------------------------------------------------
# 1. BASELINE OLS — reference inference (meso x year clusters)
# -----------------------------------------------------------------------------
rhs <- function(ctrls) paste("delta_EPW +", paste(ctrls, collapse = " + "))

mods <- list(
  dalton_base = feols(as.formula(paste("delta_P_dalton ~", rhs(ctrl_base), "| state^year")), data = df_scaled),
  dalton_ext  = feols(as.formula(paste("delta_P_dalton ~", rhs(ctrl_ext),  "| state^year")), data = df_scaled),
  center_base = feols(as.formula(paste("delta_P_center ~", rhs(ctrl_base), "| state^year")), data = df_scaled),
  center_ext  = feols(as.formula(paste("delta_P_center ~", rhs(ctrl_ext),  "| state^year")), data = df_scaled)
)
# [A-5] identical ESTIMATION N across all models (not equal to N_SAMPLE, which
# is the pre-singleton row count -- see NOTE above).
N_EST <- unique(map_int(mods, nobs))
stopifnot("models differ in estimation N" = length(N_EST) == 1L)
cat("Estimation N (post state x year singleton drop):", N_EST, "of",
    N_SAMPLE, "raw rows\n")
mods_cl <- map(mods, ~ summary(., cluster = ~ mesoregion_code^year))

# [M-10] Common-base-year stacking induces cross-year correlation within
# microregion (all deltas share the 2010 base). Meso x year clustering assumes
# independence across year blocks; report meso-level POOLED clustering as the
# robustness that allows unrestricted within-mesoregion correlation over the
# full panel. (The primary RI regime is immune: randomness is at shock level.)
mods_cl_meso <- map(mods, ~ summary(., cluster = ~ mesoregion_code))
cat("\n--- Meso-level pooled clustering (common-base robustness) ---\n")
walk(mods_cl_meso, print)

# [G-5] NPD-VCOV diagnosis (unchanged; moot under the primary regime):
singletons <- df_scaled |> count(mesoregion_code, year) |> filter(n <= 2)
cat("Meso-year cells with <=2 micros:", nrow(singletons), "of",
    df_scaled |> distinct(mesoregion_code, year) |> nrow(), "\n")

# -----------------------------------------------------------------------------
# 2. CONLEY SPATIAL SEs (reference regime, 250km / 500km)
# -----------------------------------------------------------------------------
mods_conley <- map(c(`250km` = 250, `500km` = 500), function(cut)
  feols(delta_P_dalton ~ delta_EPW + ln_gdp_pc + ln_pop + tradable_emp_share |
          state^year,
        data = df_scaled, vcov = conley(cut))
)
print(mods_conley)

# -----------------------------------------------------------------------------
# 3. AKM / AKM0 (secondary regime) — Adao, Kolesar & Morales (2019)
# -----------------------------------------------------------------------------
library(ShiftShareSE)

# NOTE on collinearity: a few ISIC pairs (in v7: 0510/0520, 2731/2732,
# 2818/2822) have byte-identical employment-share columns -- the CNAE 2.0 ->
# ISIC 4 crosswalk splits a single CNAE class across them with no other feeder,
# so their regional exposure is indistinguishable and W is rank-deficient by the
# number of such pairs. This is HARMLESS for AKM: reg_ss() internally QR-drops
# the redundant columns (the "Share matrix is collinear" message is expected,
# not an error) and the AKM/AKM0 SEs are unchanged because the column space is
# preserved. The full-width W is deliberately RETAINED for the randomization-
# inference and Rotemberg steps below, where the industries' DISTINCT shocks
# matter and the columns must NOT be merged or dropped.
share_wide <- shares |>
  select(micro, isic4, s_rj) |>
  pivot_wider(names_from = isic4, values_from = s_rj, values_fill = 0)

W <- df_scaled |> select(micro) |>
  left_join(share_wide, by = "micro") |>
  select(-micro) |>
  mutate(across(everything(), ~ replace_na(., 0))) |>       # zero-tradable micros
  as.matrix()
stopifnot(nrow(W) == nrow(df_scaled), !anyNA(W))

akm <- reg_ss(as.formula(paste("delta_P_dalton ~",
                               paste(ctrl_base, collapse = " + "),
                               "+ factor(state):factor(year)")),
              X = df_scaled$delta_EPW, data = df_scaled, W = W,
              method = c("akm", "akm0"))
print(akm)

akm_by_year <- map(c(2014, 2018, 2022), function(t) {
  d  <- filter(df_scaled, year == t)
  Wt <- d |> select(micro) |> left_join(share_wide, by = "micro") |>
    select(-micro) |> mutate(across(everything(), ~ replace_na(., 0))) |> as.matrix()
  reg_ss(as.formula(paste("delta_P_dalton ~", paste(ctrl_base, collapse = "+"),
                          "+ factor(state)")),
         X = d$delta_EPW, data = d, W = Wt, method = c("akm", "akm0"))
})

# -----------------------------------------------------------------------------
# 4. DESIGN-BASED RANDOMIZATION INFERENCE (primary regime)
#    Permute industry identities (jointly across years, preserving each
#    industry's shock path), rebuild EPW*, re-estimate.
#    [A-7] Run for BOTH the pooled coefficient and the decomposed bust
#    magnitude (the headline cell).
# -----------------------------------------------------------------------------
B <- 9999

g_wide <- shocks |>
  filter(year %in% c(2014, 2018, 2022)) |>
  select(isic4, year, g_jt) |>
  pivot_wider(names_from = year, values_from = g_jt, values_fill = 0)
g_mat <- g_wide |> column_to_rownames("isic4") |> as.matrix()
stopifnot(all(colnames(W) %in% rownames(g_mat)))
g_mat <- g_mat[colnames(W), , drop = FALSE]

year_chr <- as.character(df_scaled$year)
yr_idx   <- cbind(seq_len(nrow(W)), match(year_chr, c("2014", "2018", "2022")))

make_epw_star <- function(perm) {
  g_star   <- g_mat[perm, , drop = FALSE]
  epw_mat  <- sapply(c("2014", "2018", "2022"), function(t) as.numeric(W %*% g_star[, t]))
  epw_mat[yr_idx]                      # raw scale, aligned to df_scaled rows
}

ri_fast <- function(perm) {
  epw_raw <- make_epw_star(perm)                 # raw scale
  d <- df_scaled |>
    mutate(epw_star  = epw_raw / sd_epw,
           boom_star = pmax( epw_raw, 0) / sd_epw,
           bust_star = pmax(-epw_raw, 0) / sd_epw)
  c(pooled = coef(feols(delta_P_dalton ~ epw_star + ln_gdp_pc + ln_pop +
                          tradable_emp_share | state^year,
                        data = d, lean = TRUE))["epw_star"],
    bust_D = coef(feols(delta_P_dalton ~ bust_star + boom_star +
                          ln_gdp_pc + ln_pop + tradable_emp_share | state^year,
                        data = d, lean = TRUE))["bust_star"],
    bust_N = coef(feols(delta_P_center ~ bust_star + boom_star +
                          ln_gdp_pc + ln_pop + tradable_emp_share | state^year,
                        data = d, lean = TRUE))["bust_star"])
}

beta_star <- t(replicate(B, ri_fast(sample(nrow(g_mat)))))
colnames(beta_star) <- c("pooled", "bust_dalton", "bust_center")

# -----------------------------------------------------------------------------
# 5. ROTEMBERG WEIGHTS (GPSS) + concentration diagnostics
# -----------------------------------------------------------------------------
rotemberg <- map_dfr(c("2014", "2018", "2022"), function(t) {
  d  <- filter(df_scaled, year == as.integer(t))
  Wt <- d |> select(micro) |> left_join(share_wide, by = "micro") |>
    select(-micro) |> mutate(across(everything(), ~ replace_na(., 0))) |> as.matrix()
  # Residualize delta_EPW on the controls + state effects. feols() would DROP
  # any state x year singleton (Distrito Federal) from resid(), leaving x_perp
  # shorter than the rows of Wt and breaking t(Wt) %*% x_perp. lm() with a state
  # factor keeps every observation (a singleton state gets its own dummy and a
  # residual of 0, contributing nothing to the weight, which is correct), so the
  # residual vector stays aligned with Wt.
  x_perp <- resid(lm(delta_EPW ~ ln_gdp_pc + ln_pop + tradable_emp_share +
                       factor(state), data = d))
  stopifnot(length(x_perp) == nrow(Wt))
  num <- g_mat[colnames(Wt), t] * as.numeric(t(Wt) %*% x_perp)
  tibble(isic4 = colnames(Wt), year = t, alpha = num / sum(num))
})
rotemberg |> group_by(year) |> slice_max(alpha, n = 5) |> print(n = 15)
rot_conc <- rotemberg |> group_by(year) |>
  summarise(hhi_abs_alpha = sum((abs(alpha) / sum(abs(alpha)))^2),
            top3_share    = sum(sort(abs(alpha), decreasing = TRUE)[1:3]) / sum(abs(alpha)))
print(rot_conc)   # report in appendix: effective number of shocks ~ 1/HHI
write_csv(rotemberg, file.path("output", "rotemberg_weights.csv"))
write_csv(rot_conc,  file.path("output", "rotemberg_concentration.csv"))

# -----------------------------------------------------------------------------
# 6. BHJ SHOCK BALANCE TEST — [A-6] national employment weights
# -----------------------------------------------------------------------------
if (file.exists(file.path("data", "sector_chars.rds"))) {
  chars <- readRDS(file.path("data", "sector_chars.rds"))
  s_nat <- readRDS("rais_isic_v7.rds") |> group_by(isic4) |>
    summarise(L_j = sum(workers), .groups = "drop") |>
    mutate(s_bar = L_j / sum(L_j))                       # [A-6]
  bal_df <- shocks |> inner_join(chars, by = "isic4") |>
    inner_join(s_nat, by = "isic4")
  bal <- map(c(2014, 2018, 2022), function(t)
    feols(g_jt ~ sh_loweduc + sh_white + sh_male + mean_lnwage,
          data = filter(bal_df, year == t), weights = ~ s_bar))
  walk(bal, ~ print(fitstat(., "f")))
} else cat("TODO: build sector_chars.rds from RAIS 2010.\n")


# -----------------------------------------------------------------------------
# 7. ASYMMETRY — [A-1] CANONICAL MAGNITUDE CODING + SIGN AUDIT
# -----------------------------------------------------------------------------
df_asym <- df_scaled |>
  mutate(
    # --- OLD v2 convention (signed), verification only ---
    epw_pos_signed = pmax(delta_EPW_raw, 0) / sd_epw,
    epw_neg_signed = pmin(delta_EPW_raw, 0) / sd_epw,
    # --- CANONICAL convention (magnitudes; model Prop. 1) ---
    epw_boom = pmax( delta_EPW_raw, 0) / sd_epw,     # >= 0
    epw_bust = pmax(-delta_EPW_raw, 0) / sd_epw      # >= 0
  )
stopifnot(all(df_asym$epw_bust >= 0), all(df_asym$epw_boom >= 0),
          all(abs(df_asym$epw_bust + df_asym$epw_neg_signed) < 1e-12),
          all(abs(df_asym$epw_boom - df_asym$epw_pos_signed) < 1e-12))

mod_decomp <- list(); mod_signed <- list()
for (oc in outcomes) {
  mod_decomp[[oc]] <- feols(
    as.formula(paste(oc, "~ epw_boom + epw_bust +",
                     paste(ctrl_base, collapse = " + "), "| state^year")),
    data = df_asym, cluster = ~ mesoregion_code^year)
  mod_signed[[oc]] <- feols(
    as.formula(paste(oc, "~ epw_pos_signed + epw_neg_signed +",
                     paste(ctrl_base, collapse = " + "), "| state^year")),
    data = df_asym, cluster = ~ mesoregion_code^year)
}
stopifnot(all(map_int(c(mod_decomp, mod_signed), nobs) == N_EST))   # [A-5]

# ---- [A-9] SIGN AUDIT LOG ---------------------------------------------------
sink(file.path("output", "sign_audit_log.txt"), split = TRUE)
cat("===== SIGN AUDIT (", format(Sys.time()), ") =====\n")
cat("Convention: epw_bust = max(-dEPW,0)/sd; epw_boom = max(dEPW,0)/sd.\n")
cat("Model (Appendix, Prop. 1) predicts: b_bust > 0, b_boom <= 0, b_bust >= |b_boom|.\n\n")
for (oc in outcomes) {
  b_new_bust <- coef(mod_decomp[[oc]])["epw_bust"]
  b_new_boom <- coef(mod_decomp[[oc]])["epw_boom"]
  b_old_neg  <- coef(mod_signed[[oc]])["epw_neg_signed"]
  b_old_pos  <- coef(mod_signed[[oc]])["epw_pos_signed"]
  stopifnot(abs(b_new_bust + b_old_neg) < 1e-8,       # exact sign flip
            abs(b_new_boom - b_old_pos) < 1e-8,       # boom unchanged
            abs(fitstat(mod_decomp[[oc]], "wr2")$wr2 -
                fitstat(mod_signed[[oc]], "wr2")$wr2) < 1e-10)
  cat(sprintf(
    "%-16s | bust (magnitude) = %+.4f (SE %.4f) | boom = %+.4f (SE %.4f) | bust > 0: %s\n",
    oc, b_new_bust, se(mod_decomp[[oc]])["epw_bust"],
    b_new_boom, se(mod_decomp[[oc]])["epw_boom"],
    ifelse(b_new_bust > 0, "MATCH (theory-consistent)", "** MISMATCH **")))
}
cat("\nEquivalence proof PASSED: magnitude coding is a pure reparameterization",
    "of the v2 signed coding (bust flips sign exactly; fits identical).\n")

# ---- RI p-values ([A-7]) ----------------------------------------------------
beta_hat_pooled <- coef(mods$dalton_base)["delta_EPW"]
beta_hat_bust_D <- coef(mod_decomp$delta_P_dalton)["epw_bust"]
beta_hat_bust_N <- coef(mod_decomp$delta_P_center)["epw_bust"]

p_ri <- function(stars, hat) (1 + sum(abs(stars) >= abs(hat))) / (length(stars) + 1)
p_pooled <- p_ri(beta_star[, "pooled"],      beta_hat_pooled)
p_bust_D <- p_ri(beta_star[, "bust_dalton"], beta_hat_bust_D)
p_bust_N <- p_ri(beta_star[, "bust_center"], beta_hat_bust_N)

cat(sprintf("\nDesign-based RI (B = %d):\n", B))
cat(sprintf("  pooled Dalton : beta = %+.4f | p = %.4f\n", beta_hat_pooled, p_pooled))
cat(sprintf("  bust  Dalton  : beta = %+.4f | p = %.4f\n", beta_hat_bust_D, p_bust_D))
cat(sprintf("  bust  Center  : beta = %+.4f | p = %.4f\n", beta_hat_bust_N, p_bust_N))
sink()

saveRDS(beta_star, file.path("output", "ri_beta_distribution.rds"))
ggplot(tibble(b = beta_star[, "pooled"]), aes(b)) +
  geom_histogram(bins = 60) +
  geom_vline(xintercept = beta_hat_pooled, linetype = 2) +
  labs(x = expression(beta^"*"), y = "Frequency") +
  theme_minimal()
ggsave(file.path("figures", "ri_distribution.pdf"), width = 7, height = 4)


# -----------------------------------------------------------------------------
# 7b. WINSORIZED ROBUSTNESS — [A-2] no cross-frame references
# -----------------------------------------------------------------------------
wz <- function(x, p = .01) pmin(pmax(x, quantile(x, p)), quantile(x, 1 - p))
mod_winz <- feols(delta_P_dalton ~ epw_w + ln_gdp_pc + ln_pop +
                    tradable_emp_share | state^year,
                  data = df_asym |>
                    mutate(epw_w = as.numeric(scale(wz(delta_EPW_raw)))),
                  cluster = ~ mesoregion_code^year)

# -----------------------------------------------------------------------------
# 8. OUTPUT — etable
# -----------------------------------------------------------------------------
dict <- c(delta_EPW = "$\\Delta$ EPW", delta_P_dalton = "$\\Delta P^{D}$",
          delta_P_center = "$\\Delta P^{N}$",
          ln_gdp_pc = "Log GDP per capita", ln_pop = "Log population",
          tradable_emp_share = "Tradable employment share",
          urban_share = "Urban share", educ_share = "Education share",
          manuf_share = "Manufacturing share",
          epw_boom = "$\\Delta$ EPW$^{+}$ (boom magnitude)",
          epw_bust = "$\\Delta$ EPW$^{-}$ (bust magnitude)",
          "state^year" = "State $\\times$ year")

etable(mods_cl, dict = dict, digits = 3, fitstat = ~ n + war2,
       signif.code = c("***" = .01, "**" = .05, "*" = .10),
       cluster = ~ mesoregion_code^year, tex = TRUE,
       title = "Trade exposure and political polarization: stacked first differences",
       label = "tab:ols_baseline",
       notes = paste("Standardized variables. SEs clustered mesoregion",
                     "$\\times$ year (reference regime); design-based RI",
                     sprintf("p-value for $\\Delta$EPW: %.3f.", p_pooled)),
       file = file.path("tables", "tab_ols_baseline.tex"), replace = TRUE)

etable(mod_decomp, dict = dict, digits = 3, fitstat = ~ n + war2,
       signif.code = c("***" = .01, "**" = .05, "*" = .10),
       tex = TRUE,
       title = "Trade exposure and polarization: asymmetric decomposition (magnitude coding)",
       label = "tab:decomposition",
       notes = paste("$\\Delta$EPW$^{+} = \\max(\\Delta\\text{EPW},0)$ and",
                     "$\\Delta$EPW$^{-} = \\max(-\\Delta\\text{EPW},0)$ are boom and bust",
                     "\\emph{magnitudes} (both non-negative), each scaled by the SD of",
                     "$\\Delta$EPW; the model predicts a positive coefficient on",
                     "$\\Delta$EPW$^{-}$. Design-based RI p-values for the bust",
                     sprintf("coefficient: %.3f ($\\Delta P^D$), %.3f ($\\Delta P^N$).",
                             p_bust_D, p_bust_N)),
       file = file.path("tables", "tab_decomposition_v3.tex"), replace = TRUE)

cat("\nDone. Check output/sign_audit_log.txt for the MATCH/MISMATCH verdict.\n")
