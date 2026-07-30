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

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
source("/Users/solenoide/Documents/dissertação/data/códigos/_estimation_functions.R")

library(tidyverse)
library(fixest)
setFixest_notes(FALSE)     # silence per-call singleton NOTEs (RI loops -> log spam)

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
# ---- [A-10] EPW-UNIVERSE RESTRICTION ----------------------------------------
# A microregion can in principle appear in the polarization/controls panels yet
# be ABSENT from the RAIS-based EPW universe. Such a micro has no exposure
# shares AND no state/mesoregion label (those are carried by the EPW panel), so
# it cannot enter the state x year fixed effects nor the AKM share matrix.
# Retaining it silently breaks the secondary regime: ShiftShareSE::reg_ss builds
# its model frame with na.omit (dropping the NA-state rows) while W keeps them,
# so the row counts diverge and reg_ss aborts with "incompatible dimensions".
# feols likewise drops the rows, desyncing N.
#
# [CORRECTION 2026-07] This block previously claimed to exclude exactly one
# micro (13002). It does NOT, and never did in any run of the current code:
# 13002 IS in the EPW universe, so the filter is a NO-OP (558 of 558 micros
# retained). Verified against the saved artefacts. The exclusion of 13002 is
# effected upstream, by the estimation-universe rule in 06 (zero base-year
# tradable employment => manuf_share_of_tradable is 0/0, undefined). The filter
# is KEPT as a genuine forward guard, not as the mechanism it was described as.
epw_micros    <- unique(epw_v7$micro)
excluded_micro <- setdiff(unique(df_raw$micro), epw_micros)
cat("Excluded (not in EPW universe):",
    if (length(excluded_micro)) paste(excluded_micro, collapse = ", ") else "none",
    sprintf("[%d of %d micros retained]\n", length(intersect(unique(df_raw$micro), epw_micros)),
            n_distinct(df_raw$micro)))

df <- df_raw |>
  filter(year != 2010) |>
  filter(micro %in% epw_micros)

# tradable_emp_share now arrives WITH the panel (06). The join is kept as a
# fallback for panels built before that change; when the column is already
# present the two are asserted to agree rather than one silently masking the
# other.
if ("tradable_emp_share" %in% names(df)) {
  chk <- df |> distinct(micro, tradable_emp_share) |> inner_join(sumsh, by = "micro")
  stopifnot("panel tradable_emp_share disagrees with tradable_emp_share_2010_v7.rds" =
              max(abs(chk$tradable_emp_share.x - chk$tradable_emp_share.y)) < 1e-12)
} else {
  cat("[!] Panel predates the 06 BHJ-control change; joining sumsh directly.\n")
  df <- df |> left_join(sumsh, by = "micro")
}

df <- df |>
  mutate(tradable_emp_share = replace_na(tradable_emp_share, 0),
         delta_EPW          = replace_na(delta_EPW, 0))

# ---- ESTIMATION-UNIVERSE RULE (the 1,671 vs 1,668 resolution) ---------------
# A microregion with zero base-year bilateral tradable employment has an
# UNDEFINED tradable composition: manuf_share_of_tradable is 0/0, not 0.
# Zero-filling it (the old behaviour here) was a convention, not a correction,
# and it silently disagreed with the paper, which drops the unit. The rule is
# now imposed once, in 06, and only ASSERTED here so the two cannot drift.
undefined_micro <- df |>
  filter(tradable_emp_share <= 0 | is.na(manuf_share_of_tradable)) |>
  distinct(micro, across(any_of(c("microregion_name", "state"))))
if (nrow(undefined_micro)) {
  cat("\n[!] Microregions with undefined tradable composition reached 07 --\n",
      "    06_panel_consolidation.R should already have dropped them:\n")
  print(undefined_micro)
  df <- df |> filter(!micro %in% undefined_micro$micro)
}

stopifnot(
  "2010 rows leaked into estimation sample" = all(df$year %in% c(2014, 2018, 2022)),
  "tradable_emp_share missing"              = !anyNA(df$tradable_emp_share),
  "manuf_share_of_tradable missing"         = !anyNA(df$manuf_share_of_tradable),
  "zero-tradable micro in estimation sample" = all(df$tradable_emp_share > 0),
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
# [T-3b] tradable_emp_share == sum_j s_rj under SHARE_DENOM = "total". This is the
# BHJ sum-of-shares control and is REQUIRED for consistency, not an optional
# covariate. Do not drop it from any specification reporting delta_EPW. (Under
# "tradable" the realized sum is identically 1 and the variable is a tradable-
# intensity covariate instead -- included, but not load-bearing for BHJ.)
ctrl_base <- c("ln_gdp_pc", "ln_pop", "tradable_emp_share")
ctrl_ext  <- c(ctrl_base, "urban_share", "educ_share", "manuf_share_of_tradable")

outcomes  <- c("delta_P_dalton", "delta_P_center")
zvars     <- unique(c(outcomes, "delta_EPW", ctrl_ext))

df_scaled <- df |>
  mutate(delta_EPW_raw = delta_EPW,                          # [A-2]
         theta_raw     = tradable_emp_share) |>              # [T-2b] pre-scaling
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

# ---- [T-2b] the property that makes the incomplete-shares spec correct -------
# Under SHARE_DENOM = "total", sum_j s_rj IS theta_r, so tradable_emp_share is
# literally the object BHJ prescribes rather than a proxy from a neighbouring
# design. Under "tradable" the row sums are identically 1 (degenerate). Assert
# whichever invariant applies; a failure here invalidates everything downstream.
W_rowsum_gap <- if (SHARE_DENOM == "total")
  max(abs(rowSums(W) - df_scaled$theta_raw)) else max(abs(rowSums(W) - 1))
cat(sprintf("[T-2b] SHARE_DENOM = %s | max|rowSums(W) - %s| = %.3e\n",
            SHARE_DENOM, if (SHARE_DENOM == "total") "theta_r" else "1", W_rowsum_gap))
stopifnot("rowSums(W) does not match the share-sum invariant" = W_rowsum_gap < 1e-10)
if (SHARE_DENOM == "total")
  stopifnot("sum_j s_rj must be < 1 under the total denominator" =
              all(rowSums(W) < 1))

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
#
#    [T-4] The loop is PARAMETERISED on the control vector and now returns all
#    SIX reported coefficients. Previously it hardcoded ctrl_base and returned
#    three. That matched Table 3 and the pooled-Dalton p (both ctrl_base), so
#    those p-values were correctly calibrated -- but the ctrl_ext columns of
#    tab_ols_baseline carried a base-controls p-value, the center columns carried
#    the Dalton one, and pooled_N / boom_D / boom_N were never permuted at all.
#    boom_N is the coefficient the draft's Section 6 argument turns on.
#
#    [T-5] W already embeds whichever share denominator is in force. Under
#    SHARE_DENOM = "total" it IS the incomplete-shares matrix, so there is NO
#    theta rescaling here: epw_star = W_total %*% g_star, full stop. Multiplying
#    by theta again (correct only against a tradable-share W) would square the
#    reweighting. sd_epw likewise comes from the new raw treatment (line above,
#    sd(df$delta_EPW)), which keeps boom/bust on the same scale as pooled and
#    preserves the nesting property b+ = -b- => pooled beta.
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

RI_COEFS <- c("pooled_D", "pooled_N", "boom_D", "bust_D", "boom_N", "bust_N")

ri_fast <- function(perm, ctrls) {
  epw_raw <- make_epw_star(perm)                 # raw scale
  d <- df_scaled |>
    mutate(epw_star  = epw_raw / sd_epw,
           boom_star = pmax( epw_raw, 0) / sd_epw,
           bust_star = pmax(-epw_raw, 0) / sd_epw)
  cz  <- paste(ctrls, collapse = " + ")
  fit <- function(dv, rhs)
    coef(feols(as.formula(paste0(dv, " ~ ", rhs, " + ", cz, " | state^year")),
               data = d, lean = TRUE))
  # FOUR fits cover all six statistics: the decomposition model yields boom AND
  # bust jointly, so refitting it per coefficient would only burn time.
  p_D <- fit("delta_P_dalton", "epw_star")
  p_N <- fit("delta_P_center", "epw_star")
  a_D <- fit("delta_P_dalton", "boom_star + bust_star")
  a_N <- fit("delta_P_center", "boom_star + bust_star")
  c(pooled_D = p_D[["epw_star"]],  pooled_N = p_N[["epw_star"]],
    boom_D   = a_D[["boom_star"]], bust_D   = a_D[["bust_star"]],
    boom_N   = a_N[["boom_star"]], bust_N   = a_N[["bust_star"]])
}

# One placebo matrix per control set. The seed is reset before each so both
# runs see the SAME permutation stream and differ only in specification.
ri_run <- function(ctrls, tag) {
  set.seed(2026)
  t0 <- Sys.time()
  m  <- t(replicate(B, ri_fast(sample(nrow(g_mat)), ctrls)))
  colnames(m) <- RI_COEFS
  f <- file.path("output", sprintf("ri_beta_distribution_%s_%s.rds", SHARE_DENOM, tag))
  saveRDS(m, f)
  cat(sprintf("[T-5] RI %-4s controls | B = %d | %.1f min -> %s\n",
              tag, B, as.numeric(difftime(Sys.time(), t0, units = "mins")), f))
  m
}
beta_star_base <- ri_run(ctrl_base, "base")
beta_star_ext  <- ri_run(ctrl_ext,  "ext")

# Aliases for the blocks below, which report the ctrl_base specification
# (Table 3 and the pooled-Dalton baseline are both estimated on ctrl_base).
beta_star <- beta_star_base[, c("pooled_D", "bust_D", "bust_N")]
colnames(beta_star) <- c("pooled", "bust_dalton", "bust_center")

# -----------------------------------------------------------------------------
# 5. ROTEMBERG WEIGHTS (GPSS) + concentration diagnostics
# -----------------------------------------------------------------------------
# [T-6] The weights are a function of W and therefore MOVE with the share
# denominator, so they are recomputed here on whichever W this run built, and
# reported for BOTH control sets: the residualisation must match the
# specification whose identification the weights are meant to describe.
# The lm() is deliberate and must stay -- feols() would DROP any state x year
# singleton (Distrito Federal) from resid(), leaving x_perp shorter than the rows
# of Wt and breaking t(Wt) %*% x_perp. lm() with a state factor keeps every
# observation (a singleton state gets its own dummy and a residual of 0,
# contributing nothing to the weight, which is correct), so the residual vector
# stays aligned with Wt.
rotemberg_for <- function(ctrls) {
  map_dfr(c("2014", "2018", "2022"), function(t) {
    d  <- filter(df_scaled, year == as.integer(t))
    Wt <- d |> select(micro) |> left_join(share_wide, by = "micro") |>
      select(-micro) |> mutate(across(everything(), ~ replace_na(., 0))) |> as.matrix()
    x_perp <- resid(lm(reformulate(c(ctrls, "factor(state)"), response = "delta_EPW"),
                       data = d))
    stopifnot(length(x_perp) == nrow(Wt))
    num <- g_mat[colnames(Wt), t] * as.numeric(t(Wt) %*% x_perp)
    tibble(isic4 = colnames(Wt), year = t, alpha = num / sum(num))
  })
}
rot_conc_for <- function(rot) rot |> group_by(year) |>
  summarise(hhi_abs_alpha = sum((abs(alpha) / sum(abs(alpha)))^2),
            eff_n         = 1 / sum((abs(alpha) / sum(abs(alpha)))^2),
            top3_share    = sum(sort(abs(alpha), decreasing = TRUE)[1:3]) / sum(abs(alpha)),
            .groups = "drop")

rotemberg      <- rotemberg_for(ctrl_base)      # paper vintage (base controls)
rotemberg_ext  <- rotemberg_for(ctrl_ext)       # [T-6] extended-controls spec
rot_conc       <- rot_conc_for(rotemberg)
rot_conc_ext   <- rot_conc_for(rotemberg_ext)

rot_top5 <- bind_rows(
  rotemberg     |> mutate(ctrls = "base"),
  rotemberg_ext |> mutate(ctrls = "ext")) |>
  group_by(ctrls, year) |> slice_max(abs(alpha), n = 5) |>
  arrange(ctrls, year, desc(abs(alpha))) |> ungroup()
cat("\n--- Rotemberg: top-5 |alpha| by year and control set ---\n")
print(as.data.frame(rot_top5), digits = 4)
cat("\n--- Rotemberg concentration | base controls ---\n"); print(as.data.frame(rot_conc), digits = 4)
cat("--- Rotemberg concentration | ext controls  ---\n");   print(as.data.frame(rot_conc_ext), digits = 4)
cat(sprintf("Effective shocks (mean over years): base %.2f | ext %.2f\n",
            mean(rot_conc$eff_n), mean(rot_conc_ext$eff_n)))
write_csv(rotemberg,     file.path("output", sprintf("rotemberg_weights_%s_base.csv", SHARE_DENOM)))
write_csv(rotemberg_ext, file.path("output", sprintf("rotemberg_weights_%s_ext.csv",  SHARE_DENOM)))
write_csv(bind_rows(mutate(rot_conc, ctrls = "base"), mutate(rot_conc_ext, ctrls = "ext")),
          file.path("output", sprintf("rotemberg_concentration_%s.csv", SHARE_DENOM)))

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

# ---- [T-6] SYMMETRY TEST  H0: b_boom = -b_bust  ------------------------------
# The formal test of the paper's central asymmetry hypothesis. In magnitude
# coding a symmetric response means the two coefficients are equal and opposite,
# i.e. b_boom + b_bust = 0; under that restriction the decomposition collapses to
# the pooled specification. Present in the 16 Jun table (p = 0.106 Dalton, 0.032
# center) and lost in transcription -- restored here. Clustered vcov (the models
# carry cluster = meso^year at fit time).
symmetry_test <- map_dfr(outcomes, function(oc) {
  m  <- mod_decomp[[oc]]
  b  <- coef(m)[c("epw_boom", "epw_bust")]
  V  <- vcov(m)[c("epw_boom", "epw_bust"), c("epw_boom", "epw_bust")]
  cc <- sum(b)                                   # b_boom + b_bust
  se <- sqrt(sum(V))                             # var(b1+b2) = v11 + v22 + 2 v12
  dof <- tryCatch(fixest::degrees_freedom(m, type = "t"), error = function(e) Inf)
  tibble(outcome = oc, b_boom = b[["epw_boom"]], b_bust = b[["epw_bust"]],
         sum = cc, se_sum = se, t = cc / se, dof = dof,
         p = 2 * pt(-abs(cc / se), df = dof))
})
cat("\n--- [T-6] Symmetry test  H0: b_boom + b_bust = 0 ---\n")
print(as.data.frame(symmetry_test), digits = 4)
cat("Read: small p => the boom and bust responses are NOT mirror images, which is\n",
    "the asymmetry the model predicts. Large p => the pooled spec is not rejected.\n")

# ---- [T-5] NESTING CHECK: the restriction b_boom = -b_bust IS the pooled spec -
# Imposing it turns the regressor into (boom - bust) = delta_EPW_raw / sd_epw, so
# the constrained coefficient must equal the pooled beta to machine precision.
# This is what certifies that sd_epw is the right scale anchor: reuse a stale one
# and boom/bust desynchronise from pooled and this check fails.
nesting_gap <- map_dbl(set_names(outcomes), function(oc) {
  m_r <- feols(as.formula(paste(oc, "~ epw_net +", paste(ctrl_base, collapse = " + "),
                                "| state^year")),
               data = df_asym |> mutate(epw_net = epw_boom - epw_bust))
  m_p <- feols(as.formula(paste(oc, "~ delta_EPW +", paste(ctrl_base, collapse = " + "),
                                "| state^year")), data = df_scaled)
  abs(coef(m_r)[["epw_net"]] - coef(m_p)[["delta_EPW"]])
})
cat(sprintf("[T-5] nesting check max|b(boom-bust) - b_pooled| = %.3e\n",
            max(nesting_gap)))
stopifnot("b+ = -b- does not recover the pooled beta -- sd_epw anchor is wrong" =
            max(nesting_gap) < 1e-9)

# ---- [A-9] SIGN AUDIT LOG ---------------------------------------------------
sink(file.path("output", sprintf("sign_audit_log_%s.txt", SHARE_DENOM)), split = TRUE)
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

# NOTE: output/ri_beta_distribution.rds is deliberately NOT rewritten. It is the
# three-column, base-controls placebo matrix from the complete-shares vintage and
# is kept frozen for provenance; the current run writes
# ri_beta_distribution_<denom>_<ctrls>.rds via ri_run() above. ([T-5], criterion 8.)
ggplot(tibble(b = beta_star[, "pooled"]), aes(b)) +
  geom_histogram(bins = 60) +
  geom_vline(xintercept = beta_hat_pooled, linetype = 2) +
  labs(x = expression(beta^"*"), y = "Frequency") +
  theme_minimal()
ggsave(file.path("figures", sprintf("ri_distribution_%s.pdf", SHARE_DENOM)),
       width = 7, height = 4)

# =============================================================================
# [T-5] FULL RI REPORT — six coefficients x two control sets
# =============================================================================
# The ctrl_ext decomposition was never estimated before (only ctrl_base was), so
# the ext placebo matrix had no matched point estimate to be located in. Fit it.
mod_decomp_ext <- map(set_names(outcomes), function(oc)
  feols(as.formula(paste(oc, "~ epw_boom + epw_bust +",
                         paste(ctrl_ext, collapse = " + "), "| state^year")),
        data = df_asym, cluster = ~ mesoregion_code^year))
stopifnot("ext decomposition N differs" =
            all(map_int(mod_decomp_ext, nobs) == N_EST))

pick <- function(m, k, nm)
  tibble(coef = nm, beta = unname(coef(m)[k]), se_cl = unname(se(m)[k]))

hat_of <- function(m_pool_D, m_pool_N, m_dec_D, m_dec_N) bind_rows(
  pick(m_pool_D, "delta_EPW", "pooled_D"),
  pick(m_pool_N, "delta_EPW", "pooled_N"),
  pick(m_dec_D,  "epw_boom",  "boom_D"),
  pick(m_dec_D,  "epw_bust",  "bust_D"),
  pick(m_dec_N,  "epw_boom",  "boom_N"),
  pick(m_dec_N,  "epw_bust",  "bust_N"))

ri_table <- function(hat, bstar, tag) hat |>
  mutate(placebo_sd = map_dbl(coef, ~ sd(bstar[, .x])),
         sd_ratio   = placebo_sd / se_cl,
         p_ri       = map2_dbl(coef, beta, ~ mean(abs(bstar[, .x]) >= abs(.y))),
         p_ri_plus1 = map2_dbl(coef, beta,
                               ~ (1 + sum(abs(bstar[, .x]) >= abs(.y))) / (nrow(bstar) + 1)),
         ctrls = tag, share_denom = SHARE_DENOM, B = nrow(bstar), n = N_EST)

ri_full <- bind_rows(
  ri_table(hat_of(mods_cl$dalton_base, mods_cl$center_base,
                  mod_decomp$delta_P_dalton, mod_decomp$delta_P_center),
           beta_star_base, "base"),
  ri_table(hat_of(mods_cl$dalton_ext, mods_cl$center_ext,
                  mod_decomp_ext$delta_P_dalton, mod_decomp_ext$delta_P_center),
           beta_star_ext, "ext"))

cat("\n=========== [T-5] RANDOMIZATION INFERENCE, all reported cells ===========\n")
cat("share_denom =", SHARE_DENOM, "| B =", B, "| N =", N_EST, "\n")
cat("p_ri = mean(|beta*| >= |beta_hat|); p_ri_plus1 = (1+#)/(B+1), the convention\n")
cat("used in the tables. sd_ratio = placebo SD / clustered SE.\n\n")
print(as.data.frame(ri_full |> select(ctrls, coef, beta, se_cl, placebo_sd,
                                     sd_ratio, p_ri, p_ri_plus1)), digits = 4)
write_csv(ri_full, file.path("output", sprintf("ri_summary_%s.csv", SHARE_DENOM)))


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
          manuf_share_of_tradable = "Manuf.\\ share of tradable emp.",
          epw_boom = "$\\Delta$ EPW$^{+}$ (boom magnitude)",
          epw_bust = "$\\Delta$ EPW$^{-}$ (bust magnitude)",
          "state^year" = "State $\\times$ year")

# [T-7] Every table is written under a CONVENTION-TAGGED name. The untagged files
# already on disk are the frozen complete-shares vintage and are left alone, in
# the same spirit as ri_beta_distribution.rds. Under SHARE_DENOM = "total" these
# are the MAIN results; under "tradable" they are the robustness panel.
tag_tab <- function(stem) file.path("tables", sprintf("tab_%s_%s.tex", stem, SHARE_DENOM))

# Matched RI p per reported cell, pulled from ri_full (no hand-copying).
rip <- function(cf, ct) ri_full |> filter(coef == cf, ctrls == ct) |> pull(p_ri_plus1)
denom_txt <- if (SHARE_DENOM == "total") {
  paste("Exposure shares are normalised over TOTAL formal employment, so",
        "$\\sum_j s_{rj} = \\theta_r < 1$ and varies across microregions; the",
        "tradable employment share is therefore the BHJ sum-of-shares control and",
        "is included in every column.")
} else {
  paste("Exposure shares are normalised within the tradable universe, so",
        "$\\sum_j s_{rj} = 1$ by construction and the sum-of-shares control is",
        "degenerate; the tradable employment share enters as a tradable-intensity",
        "covariate, not as the BHJ control.")
}

etable(mods_cl, dict = dict, digits = 3, fitstat = ~ n + war2,
       signif.code = c("***" = .01, "**" = .05, "*" = .10),
       cluster = ~ mesoregion_code^year, tex = TRUE,
       title = "Trade exposure and political polarization: stacked first differences",
       label = paste0("tab:ols_baseline_", SHARE_DENOM),
       notes = paste("Standardized variables. SEs clustered mesoregion",
                     "$\\times$ year (reference regime).", denom_txt,
                     "Design-based RI $p$ for $\\Delta$EPW, each column against a",
                     "placebo distribution built under ITS OWN control set:",
                     sprintf(paste("%.3f (1), %.3f (2), %.3f (3), %.3f (4);",
                                   "$B = %d$."),
                             rip("pooled_D", "base"), rip("pooled_D", "ext"),
                             rip("pooled_N", "base"), rip("pooled_N", "ext"), B)),
       file = tag_tab("ols_baseline"), replace = TRUE)

etable(c(mod_decomp, setNames(mod_decomp_ext, paste0(names(mod_decomp_ext), "_ext"))),
       dict = dict, digits = 3, fitstat = ~ n + war2,
       signif.code = c("***" = .01, "**" = .05, "*" = .10),
       tex = TRUE,
       title = "Trade exposure and polarization: asymmetric decomposition (magnitude coding)",
       label = paste0("tab:decomposition_", SHARE_DENOM),
       notes = paste("$\\Delta$EPW$^{+} = \\max(\\Delta\\text{EPW},0)$ and",
                     "$\\Delta$EPW$^{-} = \\max(-\\Delta\\text{EPW},0)$ are boom and bust",
                     "\\emph{magnitudes} (both non-negative), each scaled by the SD of",
                     "$\\Delta$EPW; the model predicts a positive coefficient on",
                     "$\\Delta$EPW$^{-}$. The boom/bust PARTITION is identical across",
                     "the two share conventions because $\\theta_r \\ge 0$; only the",
                     "magnitudes are reweighted.", denom_txt,
                     "Columns 1--2 use base controls, 3--4 extended.",
                     sprintf(paste("Design-based RI $p$ (base / ext): boom %.3f / %.3f",
                                   "and bust %.3f / %.3f for $\\Delta P^D$;",
                                   "boom %.3f / %.3f and bust %.3f / %.3f for",
                                   "$\\Delta P^N$."),
                             rip("boom_D", "base"), rip("boom_D", "ext"),
                             rip("bust_D", "base"), rip("bust_D", "ext"),
                             rip("boom_N", "base"), rip("boom_N", "ext"),
                             rip("bust_N", "base"), rip("bust_N", "ext")),
                     sprintf(paste("Symmetry test $H_0: \\beta_+ = -\\beta_-$:",
                                   "$p = %.3f$ ($\\Delta P^D$), $p = %.3f$",
                                   "($\\Delta P^N$)."),
                             symmetry_test$p[symmetry_test$outcome == "delta_P_dalton"],
                             symmetry_test$p[symmetry_test$outcome == "delta_P_center"])),
       file = tag_tab("decomposition"), replace = TRUE)

# ---- [T-7] DESCRIPTIVE STATISTICS IN RAW UNITS ------------------------------
# The tab_desc_stats.tex on disk reports STANDARDISED variables (every mean 0,
# SD 1), which is unusable as a descriptive table and is not produced by any
# current script. Rebuilt here from `df` (pre-scaling), with the treatment and
# theta_r rows the paper needs.
desc_vars <- c(delta_P_dalton = "$\\Delta$ Dalton polarization index",
               delta_P_center = "$\\Delta$ Center-emptying index",
               delta_EPW      = if (SHARE_DENOM == "total")
                 "$\\Delta$EPW (total-share, incomplete)" else
                 "$\\Delta$EPW (tradable-share, complete)",
               tradable_emp_share      = "Tradable employment share ($\\theta_r$)",
               manuf_share_of_tradable = "Manuf.\\ share of tradable emp.",
               ln_gdp_pc    = "Log GDP per capita",
               ln_pop       = "Log population",
               urban_share  = "Urban share",
               educ_share   = "Education share")
desc_tbl <- imap_dfr(desc_vars, function(lab, v) {
  x <- df[[v]]
  tibble(Variable = lab, N = sum(!is.na(x)), Mean = mean(x, na.rm = TRUE),
         SD = sd(x, na.rm = TRUE), Min = min(x, na.rm = TRUE),
         P25 = quantile(x, .25, na.rm = TRUE), Median = median(x, na.rm = TRUE),
         P75 = quantile(x, .75, na.rm = TRUE), Max = max(x, na.rm = TRUE))
})
cat("\n--- [T-7] descriptive statistics, RAW units, estimation sample ---\n")
print(as.data.frame(desc_tbl), digits = 4)
write_csv(desc_tbl, file.path("output", sprintf("desc_stats_raw_%s.csv", SHARE_DENOM)))

num_fmt <- function(x) formatC(x, format = "f", digits = 4, big.mark = ",")
desc_tex <- c(
  "\\begin{table}[htbp]",
  sprintf("\\caption{\\label{tab:desc_stats_%s} Descriptive statistics, raw units (estimation sample, $N = %d$ microregion-years)}",
          SHARE_DENOM, nrow(df)),
  "\\centering", "\\small",
  "\\begin{tabular}{lrrrrrrrr}", "\\midrule\\midrule",
  "Variable & N & Mean & SD & Min & P25 & Median & P75 & Max \\\\", "\\midrule",
  paste0(desc_tbl$Variable, " & ", format(desc_tbl$N, big.mark = ","), " & ",
         apply(as.matrix(desc_tbl[, c("Mean","SD","Min","P25","Median","P75","Max")]),
               1, function(r) paste(num_fmt(r), collapse = " & ")),
         " \\\\"),
  "\\midrule\\midrule", "\\end{tabular}", "\\par\\raggedright",
  paste("\\footnotesize Raw (unstandardised) units on the estimation sample.",
        denom_txt, "The regressions standardise the treatment and all controls;",
        "boom/bust magnitudes are scaled by",
        sprintf("$\\mathrm{sd}(\\Delta\\mathrm{EPW}) = %.4f$.", sd_epw)),
  "\\end{table}")
writeLines(desc_tex, tag_tab("desc_stats"))
cat("[T-7] wrote", tag_tab("desc_stats"), "\n")

# -----------------------------------------------------------------------------
# 9. JOINT EPW / IPW  — import-competition channel (Part A.5)
#    Runs only if the import treatment (03d) and common shares (03a) exist.
#    Treatments are on the COMMON share denominator (03a) so EPW and IPW are
#    commensurable (guard cor(EPW_common, EPW_v7) > 0.99 established in 03a).
#      * joint spec  dP ~ EPW^+ + EPW^- + IPW | state^year
#      * net exposure dP ~ (EPW - IPW) | state^year
#      * asymmetric decomposition applied to IPW as well
#      * RI permuting BOTH shock vectors JOINTLY (same industry permutation)
#      * AKM/AKM0 reported alongside (weak-identification-robust complement)
#    Every reported cell carries N, eff # shocks, RI p, AKM0 interval.
#
#    VINTAGE GUARD: the block additionally requires that the 03a/03d artefacts
#    were built under the SAME SHARE_DENOM as this run. Mixing a "tradable"-
#    normalised IPW with a "total"-normalised EPW would silently compare
#    incommensurable treatments — the exact failure the common-share refactor
#    exists to prevent. Missing or mismatched stamps SKIP the block with a
#    diagnostic instead of producing a number nobody can interpret.
# -----------------------------------------------------------------------------
joint_files <- c("ipw_panel_isic_v1.rds", "epw_common_panel_v8.rds",
                 "exposure_shares_common_v8.rds", "sectoral_import_shocks_v1.rds")
joint_ok <- all(file.exists(joint_files))
if (joint_ok) {
  stamps <- vapply(c("epw_common_panel_v8.rds", "exposure_shares_common_v8.rds"),
                   \(f) { s <- attr(readRDS(f), "share_denom")
                          if (is.null(s)) NA_character_ else s },
                   character(1))
  if (anyNA(stamps) || !all(stamps == SHARE_DENOM)) {
    joint_ok <- FALSE
    cat("\n########## [9] JOINT EPW / IPW — SKIPPED ##########\n")
    cat("Reason: the 03a/03d artefacts carry share_denom =",
        paste(ifelse(is.na(stamps), "<unstamped>", stamps), collapse = " / "),
        "but this run uses", SHARE_DENOM, "\n")
    cat("Re-run 03a_shares_common.R and 03d_ipw_construction.R to enable the\n")
    cat("import channel. Export-only results above are unaffected.\n")
  }
} else {
  cat("\n########## [9] JOINT EPW / IPW — SKIPPED (missing 03a/03d outputs) ##########\n")
}
if (joint_ok) {
  library(ShiftShareSE)
  cat("\n########## [9] JOINT EPW / IPW (import channel) ##########\n")

  ipw_p  <- readRDS("ipw_panel_isic_v1.rds")  |> mutate(micro = as.character(micro))
  epw_c  <- readRDS("epw_common_panel_v8.rds")|> mutate(micro = as.character(micro))
  sh_c   <- readRDS("exposure_shares_common_v8.rds") |> mutate(micro = as.character(micro))
  g_exp  <- shocks                                         # export g_jt (v7)
  m_imp  <- readRDS("sectoral_import_shocks_v1.rds")       # import m_lev

  dj <- df_scaled |>
    select(micro, year, state, mesoregion_code, all_of(outcomes),
           all_of(ctrl_base)) |>                                  # already standardized
    left_join(epw_c |> filter(year != 2010) |> select(micro, year, EPW_c = EPW_common),
              by = c("micro", "year")) |>
    left_join(ipw_p |> select(micro, year, IPW_total), by = c("micro", "year")) |>
    mutate(EPW_c = replace_na(EPW_c, 0), IPW_total = replace_na(IPW_total, 0),
           EPW_raw = EPW_c, IPW_raw = IPW_total)
  sdE <- sd(dj$EPW_raw); sdI <- sd(dj$IPW_raw)
  dj <- dj |>
    mutate(epw_z = EPW_raw / sdE, ipw_z = IPW_raw / sdI,
           net_z = as.numeric(scale(EPW_raw - IPW_raw)),
           epw_boom = pmax( EPW_raw, 0) / sdE, epw_bust = pmax(-EPW_raw, 0) / sdE,
           ipw_boom = pmax( IPW_raw, 0) / sdI, ipw_bust = pmax(-IPW_raw, 0) / sdI)

  Wc  <- ss_build_W(sh_c, dj$micro)
  gmE <- ss_build_gmat(g_exp, "g_jt",  Wc)
  gmI <- ss_build_gmat(m_imp, "m_lev", Wc)
  stopifnot(identical(rownames(gmE), rownames(gmI)))

  m_joint <- feols(delta_P_dalton ~ epw_boom + epw_bust + ipw_z + ln_gdp_pc + ln_pop +
                     tradable_emp_share | state^year, data = dj,
                   cluster = ~ mesoregion_code^year)
  m_net   <- feols(delta_P_dalton ~ net_z + ln_gdp_pc + ln_pop + tradable_emp_share |
                     state^year, data = dj, cluster = ~ mesoregion_code^year)
  m_ipwd  <- feols(delta_P_dalton ~ ipw_boom + ipw_bust + ln_gdp_pc + ln_pop +
                     tradable_emp_share | state^year, data = dj,
                   cluster = ~ mesoregion_code^year)
  cat("Joint  (EPW+/EPW-/IPW): ",
      sprintf("bust=%.4f boom=%.4f ipw=%.4f\n", coef(m_joint)["epw_bust"],
              coef(m_joint)["epw_boom"], coef(m_joint)["ipw_z"]))
  cat("Net exposure (EPW-IPW): ", sprintf("beta=%.4f (t=%.2f)\n",
              coef(m_net)["net_z"], tstat(m_net)["net_z"]))
  cat("IPW asymmetric        : ", sprintf("bust=%.4f boom=%.4f\n",
              coef(m_ipwd)["ipw_bust"], coef(m_ipwd)["ipw_boom"]))

  # eff # shocks for the import treatment on this sample
  effn_ipw <- ss_eff_n(ss_rotemberg(dj, Wc, gmI, "IPW_raw", ctrl_base))
  cat("Import-treatment eff_n by year:\n"); print(as.data.frame(effn_ipw), digits = 3)

  # RI permuting BOTH shock paths jointly
  yvj <- dj$year
  refit_j <- function(tr) {
    d <- dj |> mutate(e = tr$EPW / sdE, i = tr$IPW / sdI,
                      eb = pmax(-tr$EPW, 0) / sdE, bo = pmax(tr$EPW, 0) / sdE)
    mj <- feols(delta_P_dalton ~ eb + bo + i + ln_gdp_pc + ln_pop +
                  tradable_emp_share | state^year, data = d, lean = TRUE)
    c(epw_bust = unname(coef(mj)["eb"]), ipw = unname(coef(mj)["i"]))
  }
  bstar_j <- ss_ri(list(EPW = Wc, IPW = Wc), list(EPW = gmE, IPW = gmI), yvj,
                   refit_j, B = 4999)
  colnames(bstar_j) <- c("epw_bust", "ipw")
  obs_j <- refit_j(list(EPW = ss_epw_from(Wc, gmE, yvj),
                        IPW = ss_epw_from(Wc, gmI, yvj)))
  p_epw_bust_j <- ss_ri_p(bstar_j[, "epw_bust"], obs_j["epw_bust"])
  p_ipw_j      <- ss_ri_p(bstar_j[, "ipw"],      obs_j["ipw"])
  cat(sprintf("Joint RI (B=4999): EPW-bust p=%.4f | IPW p=%.4f\n",
              p_epw_bust_j, p_ipw_j))

  # AKM0 for the IPW coefficient (weak-ID-robust complement)
  akm_ipw <- ss_akm(dj, "delta_P_dalton", "IPW_raw", ctrl_base, Wc)
  ci_ipw  <- ss_akm0_ci(akm_ipw)
  cat(ss_report_row("Dalton ~ IPW (joint)", nobs(m_joint), mean(effn_ipw$eff_n),
                    p_ipw_j, ci_ipw), "\n")

  etable(list(joint = m_joint, net = m_net, ipw_decomp = m_ipwd),
         dict = c(dict, epw_z = "$\\Delta$EPW", ipw_z = "$\\Delta$IPW",
                  net_z = "Net (EPW$-$IPW)",
                  ipw_boom = "$\\Delta$IPW$^{+}$", ipw_bust = "$\\Delta$IPW$^{-}$"),
         digits = 3, fitstat = ~ n + war2, tex = TRUE,
         title = "Export and import exposure: joint specification",
         label = "tab:joint_epw_ipw", cluster = ~ mesoregion_code^year,
         notes = sprintf("Common-share treatments (03a). Joint RI p: EPW-bust %.3f, IPW %.3f. AKM0 CI (IPW): [%s, %s].",
                         p_epw_bust_j, p_ipw_j, ci_ipw[1], ci_ipw[2]),
         file = file.path("tables", "tab_joint_epw_ipw.tex"), replace = TRUE)
}

# =============================================================================
# [T-8]/[T-9] PROVENANCE — manifest fragment for this convention
# =============================================================================
# One fragment per SHARE_DENOM; 07z_results_manifest.R merges them into
# output/RESULTS_MANIFEST.md. Nothing reaches the manuscript that is not in here.
tidy_akm <- function(a) tryCatch({
  g <- function(v) { if (is.null(v)) return(c(NA_real_, NA_real_))
                     i <- grep("AKM0", names(v), ignore.case = TRUE)
                     c(as.numeric(v[setdiff(seq_along(v), i)][1]),
                       if (length(i)) as.numeric(v[i[1]]) else NA_real_) }
  tibble(stat = c("akm", "akm0"), se = g(a$se), p = g(a$p),
         ci_l = g(a$ci.l), ci_r = g(a$ci.r))
}, error = function(e) tibble(stat = c("akm", "akm0"), se = NA_real_, p = NA_real_,
                              ci_l = NA_real_, ci_r = NA_real_))

coef_se <- function(m, k = "delta_EPW")
  c(beta = unname(coef(m)[k]), se = unname(se(m)[k]))

bust_counts <- c(pooled = sum(df_asym$delta_EPW_raw < 0),
                 tapply(df_asym$delta_EPW_raw, df_asym$year, function(x) sum(x < 0)))

manifest <- list(
  meta = list(share_denom = SHARE_DENOM, B = B, seed = 2026,
              timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
              fe = "state^year", cluster = "mesoregion_code^year",
              ctrl_base = ctrl_base, ctrl_ext = ctrl_ext,
              input_md5 = tools::md5sum(c("df_estimation_v7.rds",
                                          "exposure_shares_isic_v7.rds",
                                          "sectoral_shocks_isic_v7.rds",
                                          "epw_panel_isic_v7.rds",
                                          "tradable_emp_share_2010_v7.rds")),
              session = utils::capture.output(utils::sessionInfo())),
  ri            = ri_full,
  fit           = tibble(model = names(mods_cl),
                         n = map_int(mods_cl, nobs),
                         war2 = map_dbl(mods_cl, ~ fitstat(., "war2")$war2)),
  rotemberg     = bind_rows(mutate(rot_conc, ctrls = "base"),
                            mutate(rot_conc_ext, ctrls = "ext")),
  rotemberg_top5 = rot_top5,
  symmetry      = symmetry_test,
  nesting_gap   = nesting_gap,
  akm_pooled    = tidy_akm(akm),
  akm_by_year   = map_dfr(seq_along(akm_by_year),
                          ~ mutate(tidy_akm(akm_by_year[[.x]]),
                                   year = c(2014, 2018, 2022)[.x])),
  conley        = map_dfr(names(mods_conley),
                          ~ tibble(cutoff = .x, beta = coef_se(mods_conley[[.x]])[["beta"]],
                                   se = coef_se(mods_conley[[.x]])[["se"]])),
  meso_pooled   = map_dfr(names(mods_cl_meso),
                          ~ tibble(model = .x, beta = coef_se(mods_cl_meso[[.x]])[["beta"]],
                                   se = coef_se(mods_cl_meso[[.x]])[["se"]])),
  balance       = if (file.exists(file.path("output", "03c_balance_test.csv")))
                    read_csv(file.path("output", "03c_balance_test.csv"),
                             show_col_types = FALSE) else NULL,
  descriptives  = desc_tbl,
  sanity = list(
    W_rowsum_gap   = W_rowsum_gap,
    share_sum_min  = min(rowSums(W)), share_sum_mean = mean(rowSums(W)),
    share_sum_max  = max(rowSums(W)),
    n_rows_prefilter = nrow(filter(df_raw, year != 2010)),
    N_SAMPLE = N_SAMPLE, N_EST = N_EST,
    n_micros = n_distinct(df$micro), n_fe_cells = n_distinct(paste(df$state, df$year)),
    n_industries = ncol(W), sd_epw = sd_epw,
    bust_counts = bust_counts,
    theta = c(mean = mean(df$tradable_emp_share), sd = sd(df$tradable_emp_share),
              min = min(df$tradable_emp_share),
              p25 = quantile(df$tradable_emp_share, .25, names = FALSE),
              median = median(df$tradable_emp_share),
              p75 = quantile(df$tradable_emp_share, .75, names = FALSE),
              max = max(df$tradable_emp_share))))

saveRDS(manifest, file.path("output", sprintf("manifest_%s.rds", SHARE_DENOM)))
cat(sprintf("\n[T-9] manifest fragment -> output/manifest_%s.rds\n", SHARE_DENOM))
cat(sprintf("[T-9] N chain: %d raw -> %d sample -> %d estimated | %d micros | %d industries\n",
            manifest$sanity$n_rows_prefilter, N_SAMPLE, N_EST,
            manifest$sanity$n_micros, manifest$sanity$n_industries))

cat("\nDone. Check output/sign_audit_log.txt for the MATCH/MISMATCH verdict.\n")
