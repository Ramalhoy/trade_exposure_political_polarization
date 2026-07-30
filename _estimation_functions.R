# =============================================================================
# _estimation_functions.R  —  shared shift-share estimation + inference machinery
# -----------------------------------------------------------------------------
# Factored out of 07_regression_inference.R so that 07 (presidential) and 07b
# (governor) call ONE implementation instead of duplicating ~400 lines that
# would otherwise drift (exactly as the v4/v7 files did). Pure functions only —
# sourcing this file has no side effects.
#
# Design conventions carried verbatim from 07:
#   * standardized treatment + controls, state^year FE, meso^year cluster ref;
#   * RI permutes INDUSTRY identities jointly across years, preserving each
#     industry's shock PATH (the exchangeability unit for a common-base stack);
#   * RI can permute MULTIPLE shock vectors JOINTLY (same industry permutation
#     applied to every shock matrix), preserving cross-treatment structure —
#     used by the joint EPW+IPW spec;
#   * asymmetric boom/bust MAGNITUDE coding (both >= 0), model Prop. 1;
#   * Rotemberg alpha from the treatment residualized on controls + state.
#
# Requires: tidyverse, fixest (loaded by the caller). ShiftShareSE only if
# akm_fit() is used.
# =============================================================================

# ---- BHJ sum-of-shares control, MATCHED to the share numerator --------------
# THE TRAP (CODE_CHANGES_TODO.md 1b): sum_j s_rj equals (employment in the
# NUMERATOR set) / D_r. The pipeline uses two numerator sets --
#   "bilateral"  export-bilateral (03  -> exposure_shares_isic_v7.rds)
#   "common"     full tradable    (03a -> exposure_shares_common_v8.rds)
# -- so a single precomputed file is the RIGHT control for only one of them.
#
# Under SHARE_DENOM="tradable" the realized sum of shares is identically 1 and
# therefore degenerate (collinear with any intercept/FE); the tradable-intensity
# variable tradable_emp_share is used instead, which is what every table to date
# has reported. Under "total" the realized sum IS theta_r and is the control the
# BHJ incomplete-shares correction actually calls for, so it is used directly.
#
# Returns a two-column tibble: micro (character), tradable_emp_share (numeric).
ss_bhj_control <- function(numerator = c("bilateral", "common")) {
  numerator <- match.arg(numerator)
  degenerate <- identical(get0("SHARE_DENOM", ifnotfound = "tradable"), "tradable")

  f <- if (degenerate || numerator == "bilateral") {
    # 03 asserts that, under "total", its realized share sum equals this file
    # exactly, so the bilateral branch is correct under BOTH conventions.
    "tradable_emp_share_2010_v7.rds"
  } else {
    "share_sum_theta_common_v9.rds"
  }
  if (!file.exists(f))
    stop("BHJ control file not found: ", f,
         " -- re-run ", if (grepl("common", f)) "03a_shares_common.R" else
                        "03_epw_construction.R", " first.")

  out <- readRDS(f) |> dplyr::mutate(micro = as.character(micro))
  if ("sum_s_rj" %in% names(out))
    out <- dplyr::rename(out, tradable_emp_share = sum_s_rj)
  dplyr::select(out, micro, tradable_emp_share)
}

# ---- share matrix W (region x industry), aligned to a micro vector ----------
ss_build_W <- function(shares, micro_vec) {
  share_wide <- shares |> dplyr::select(micro, isic4, s_rj) |>
    tidyr::pivot_wider(names_from = isic4, values_from = s_rj, values_fill = 0)
  W <- tibble::tibble(micro = as.character(micro_vec)) |>
    dplyr::left_join(share_wide, by = "micro") |>
    dplyr::select(-micro) |>
    dplyr::mutate(dplyr::across(dplyr::everything(), ~ tidyr::replace_na(., 0))) |>
    as.matrix()
  rownames(W) <- as.character(micro_vec)
  W
}

# ---- shock matrix g_mat (industry x year), aligned to W columns -------------
#   shocks: long tbl with isic4, year, and the named shock column.
ss_build_gmat <- function(shocks, shock_col, W, years = c(2014, 2018, 2022)) {
  g_wide <- shocks |> dplyr::filter(year %in% years) |>
    dplyr::transmute(isic4, year, s = .data[[shock_col]]) |>
    tidyr::pivot_wider(names_from = year, values_from = s, values_fill = 0)
  g_mat <- g_wide |> tibble::column_to_rownames("isic4") |> as.matrix()
  miss <- setdiff(colnames(W), rownames(g_mat))
  if (length(miss))
    g_mat <- rbind(g_mat, matrix(0, length(miss), ncol(g_mat),
                                 dimnames = list(miss, colnames(g_mat))))
  g_mat[colnames(W), as.character(years), drop = FALSE]
}

# ---- per-row treatment from W and g_mat given each row's year ---------------
ss_epw_from <- function(W, g_mat, year_vec, years = c(2014, 2018, 2022)) {
  yc  <- as.character(years)
  idx <- cbind(seq_len(nrow(W)), match(as.character(year_vec), yc))
  epw_mat <- sapply(yc, function(t) as.numeric(W %*% g_mat[, t]))
  epw_mat[idx]
}

# ---- Rotemberg weights + effective number of shocks -------------------------
#   Treatment residualized on controls + state factor (lm keeps singletons, so
#   the residual vector stays aligned with W's rows — see 07 note).
ss_rotemberg <- function(df, W, g_mat, treat_col, ctrls, years = c(2014, 2018, 2022)) {
  purrr::map_dfr(as.character(years), function(t) {
    ty <- as.integer(t)
    d  <- dplyr::filter(df, year == ty)
    Wt <- W[df$year == ty, , drop = FALSE]
    f  <- stats::reformulate(c(ctrls, "factor(state)"), response = treat_col)
    x_perp <- stats::resid(stats::lm(f, data = d))
    stopifnot(length(x_perp) == nrow(Wt))
    num <- g_mat[colnames(Wt), t] * as.numeric(t(Wt) %*% x_perp)
    tibble::tibble(isic4 = colnames(Wt), year = ty, alpha = num / sum(num))
  })
}
ss_eff_n <- function(rot) rot |> dplyr::group_by(year) |>
  dplyr::summarise(hhi = sum((abs(alpha) / sum(abs(alpha)))^2),
                   eff_n = 1 / hhi, .groups = "drop")

# ---- design-based RANDOMIZATION INFERENCE -----------------------------------
#   Wlist, gmatlist: named lists (one entry per treatment). All g_mats MUST be
#   indexed by the SAME industry set (same rownames) so one permutation applies
#   jointly. refit_fn(treats) receives a named list of per-row treatment vectors
#   (raw scale) and returns a named numeric vector of statistics.
ss_ri <- function(Wlist, gmatlist, year_vec, refit_fn, B = 9999, seed = 2026,
                  years = c(2014, 2018, 2022)) {
  set.seed(seed)
  n_ind <- nrow(gmatlist[[1]])
  stopifnot(all(vapply(gmatlist, nrow, 1L) == n_ind))
  out <- t(replicate(B, {
    perm   <- sample(n_ind)
    treats <- Map(function(W, g) ss_epw_from(W, g[perm, , drop = FALSE], year_vec, years),
                  Wlist, gmatlist)
    refit_fn(treats)
  }))
  out
}
ss_ri_p <- function(stars, hat) (1 + sum(abs(stars) >= abs(hat))) / (length(stars) + 1)

# ---- baseline OLS with meso^year cluster (reference regime) ------------------
ss_baseline <- function(df, outcome, treat, ctrls, fe = "state^year",
                        cluster = ~ mesoregion_code^year) {
  fml <- stats::as.formula(paste(outcome, "~",
                                 paste(c(treat, ctrls), collapse = " + "), "|", fe))
  m <- fixest::feols(fml, data = df)
  list(model = m, summary = summary(m, cluster = cluster),
       beta = stats::coef(m)[treat], n = stats::nobs(m))
}

# ---- asymmetric boom/bust decomposition (MAGNITUDE coding, both >= 0) -------
#   Adds epw_boom/epw_bust (or a custom prefix) scaled by sd_raw; returns model.
ss_asym <- function(df, outcome, treat_raw, ctrls, sd_raw, prefix = "epw",
                    fe = "state^year", cluster = ~ mesoregion_code^year) {
  d <- df
  d[[paste0(prefix, "_boom")]] <- pmax( d[[treat_raw]], 0) / sd_raw
  d[[paste0(prefix, "_bust")]] <- pmax(-d[[treat_raw]], 0) / sd_raw
  fml <- stats::as.formula(paste(
    outcome, "~", paste(c(paste0(prefix, "_boom"), paste0(prefix, "_bust"), ctrls),
                        collapse = " + "), "|", fe))
  m <- fixest::feols(fml, data = d)
  list(model = m, summary = summary(m, cluster = cluster),
       beta_boom = stats::coef(m)[paste0(prefix, "_boom")],
       beta_bust = stats::coef(m)[paste0(prefix, "_bust")], data = d)
}

# ---- AKM / AKM0 (secondary regime) wrapper ----------------------------------
#   Returns the reg_ss object; extract $se/$p/$ci with names c("akm","akm0").
ss_akm <- function(df, outcome, treat_raw, ctrls, W, fe_terms = "factor(state):factor(year)") {
  reg_ss <- get("reg_ss", envir = asNamespace("ShiftShareSE"))
  f <- stats::reformulate(c(ctrls, fe_terms), response = outcome)
  reg_ss(f, X = df[[treat_raw]], data = df, W = W, method = c("akm", "akm0"))
}
ss_akm0_ci <- function(akm_obj) {
  # AKM0 weak-IV-robust confidence set from reg_ss (SSResults): ci.l/ci.r are
  # named vectors with an "AKM0" entry.
  pick <- function(v) {
    if (is.null(v)) return(NA_real_)
    i <- grep("AKM0", names(v), ignore.case = TRUE)
    if (length(i)) as.numeric(v[i[1]]) else NA_real_
  }
  round(c(pick(akm_obj$ci.l), pick(akm_obj$ci.r)), 4)
}

# ---- one-line reporting row required for EVERY table ------------------------
#   N, effective # shocks, RI p-value, AKM0 interval — never a lone cluster t.
ss_report_row <- function(tag, n, eff_n_mean, ri_p, akm0_ci) {
  sprintf("%-28s | N=%d | eff_n=%.2f | RI p=%.3f | AKM0 CI=[%s, %s]",
          tag, n, eff_n_mean, ri_p,
          format(akm0_ci[1], nsmall = 3), format(akm0_ci[2], nsmall = 3))
}
