# =============================================================================
# P4 — year-interacted controls. Referee item R1-M1.
# Equation (6) restricts gamma to be common across 2014, 2018 and 2022. Since
# the dominant shock rotates (iron ore -> crude petroleum), the loading on
# theta_r is year-specific by construction. Test the restriction and report how
# much the treatment coefficient moves.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("P4")
B_RI <- 9999

d <- df_scaled |> mutate(yf = factor(year),
                         epw_boom = pmax( delta_EPW_raw, 0) / sd_epw,
                         epw_bust = pmax(-delta_EPW_raw, 0) / sd_epw)

spec_rhs <- list(
  common    = function(ctrls) paste(ctrls, collapse = " + "),
  theta_x_t = function(ctrls) paste(c(setdiff(ctrls, "tradable_emp_share"),
                                      "tradable_emp_share:yf"), collapse = " + "),
  all_x_t   = function(ctrls) paste(paste0(ctrls, ":yf"), collapse = " + ")
)

fit_all <- function(oc, ctrls, ck) {
  map_dfr(names(spec_rhs), function(sp) {
    cz <- spec_rhs[[sp]](ctrls)
    mp <- feols(as.formula(paste(oc, "~ delta_EPW +", cz, "| state^year")),
                data = d, cluster = ~ mesoregion_code^year)
    md <- feols(as.formula(paste(oc, "~ epw_boom + epw_bust +", cz, "| state^year")),
                data = d, cluster = ~ mesoregion_code^year)
    bind_rows(
      tibble(outcome = oc, ctrls = ck, spec = sp, term = "pooled",
             beta = coef(mp)[["delta_EPW"]], se = se(mp)[["delta_EPW"]],
             n = nobs(mp), k = length(coef(mp)), wr2 = fitstat(mp, "wr2")$wr2),
      tibble(outcome = oc, ctrls = ck, spec = sp, term = "boom",
             beta = coef(md)[["epw_boom"]], se = se(md)[["epw_boom"]],
             n = nobs(md), k = length(coef(md)), wr2 = fitstat(md, "wr2")$wr2),
      tibble(outcome = oc, ctrls = ck, spec = sp, term = "bust",
             beta = coef(md)[["epw_bust"]], se = se(md)[["epw_bust"]],
             n = nobs(md), k = length(coef(md)), wr2 = fitstat(md, "wr2")$wr2))
  })
}
res <- map_dfr(outcomes, function(oc) map_dfr(c("base","ext"), function(ck)
  fit_all(oc, if (ck=="base") ctrl_base else ctrl_ext, ck)))

# ---- joint Wald test of the common-gamma restriction ------------------------
wald <- map_dfr(outcomes, function(oc) map_dfr(c("base","ext"), function(ck) {
  ctrls <- if (ck=="base") ctrl_base else ctrl_ext
  mfull <- feols(as.formula(paste(oc, "~ delta_EPW +", spec_rhs$all_x_t(ctrls),
                                  "| state^year")), data = d,
                 cluster = ~ mesoregion_code^year)
  # restriction: for each control, the 2018 and 2022 interactions equal the 2014 one
  nm <- names(coef(mfull))
  # R writes the interaction in EITHER order depending on the term: the first
  # control comes back as "ln_gdp_pc:yf2014" and the rest as "yf2014:ln_pop".
  # Matching only "^<ctrl>:yf" silently tests one control instead of all of
  # them (q = 2 rather than 2 x #controls), so match both orders.
  R <- matrix(0, nrow = 0, ncol = length(nm), dimnames = list(NULL, nm))
  for (cv in ctrls) {
    cols <- grep(paste0("(^|:)", cv, "($|:)"), nm, value = TRUE)
    cols <- cols[grepl("yf", cols)]
    cols <- cols[order(sub(".*yf([0-9]{4}).*", "\\1", cols))]
    if (length(cols) < 2) next
    for (j in 2:length(cols)) {
      r <- setNames(numeric(length(nm)), nm); r[cols[1]] <- 1; r[cols[j]] <- -1
      R <- rbind(R, r)
    }
  }
  b <- coef(mfull); V <- vcov(mfull)
  q <- nrow(R)
  stat <- as.numeric(t(R %*% b) %*% solve(R %*% V %*% t(R)) %*% (R %*% b)) / q
  dof <- fixest::degrees_freedom(mfull, type = "t")
  tibble(outcome = oc, ctrls = ck, q = q, F = stat, df2 = dof,
         p = pf(stat, q, dof, lower.tail = FALSE))
}))

# ---- RI under the fully interacted spec -------------------------------------
ri_p4 <- function(ctrls) {
  set.seed(2026); cz <- spec_rhs$all_x_t(ctrls)
  t(replicate(B_RI, {
    raw <- make_epw_star(sample(nrow(g_mat)))
    dd <- d |> mutate(epw_star = raw/sd_epw, boom_star = pmax(raw,0)/sd_epw,
                      bust_star = pmax(-raw,0)/sd_epw)
    f1 <- function(dv) coef(feols(as.formula(paste0(dv," ~ epw_star + ",cz," | state^year")),
                                  data = dd, lean = TRUE))[["epw_star"]]
    f2 <- function(dv) coef(feols(as.formula(paste0(dv," ~ boom_star + bust_star + ",cz,
                                                    " | state^year")), data = dd,
                                  lean = TRUE))[c("boom_star","bust_star")]
    aD <- f2("delta_P_dalton"); aN <- f2("delta_P_center")
    c(delta_P_dalton_pooled = f1("delta_P_dalton"), delta_P_center_pooled = f1("delta_P_center"),
      delta_P_dalton_boom = aD[[1]], delta_P_dalton_bust = aD[[2]],
      delta_P_center_boom = aN[[1]], delta_P_center_bust = aN[[2]])
  }))
}
cat("\n[P4] RI under fully interacted controls (base)...\n"); rb <- ri_p4(ctrl_base)
cat("[P4] RI under fully interacted controls (ext)...\n");    re <- ri_p4(ctrl_ext)
saveRDS(list(base=rb, ext=re), file.path(OUT, "P4_ri.rds"))

res <- res |> rowwise() |>
  mutate(ri_p = if (spec != "all_x_t") NA_real_ else {
    k <- paste0(outcome,"_",term); m <- if (ctrls=="base") rb else re
    if (!k %in% colnames(m)) NA_real_ else p_ri(m[,k], beta) }) |> ungroup()

cat("\n=== P4 treatment coefficients under three control specifications ===\n")
print(as.data.frame(res), digits = 4)
cat("\n=== P4 joint Wald test of the common-gamma restriction ===\n")
print(as.data.frame(wald), digits = 4)

mv <- res |> select(outcome, ctrls, spec, term, beta) |>
  pivot_wider(names_from = spec, values_from = beta) |>
  mutate(move_theta = theta_x_t - common, move_all = all_x_t - common)
cat("\n=== P4 how much the treatment coefficient moves ===\n")
print(as.data.frame(mv), digits = 4)

write_csv(res,  file.path(OUT, "P4_coefficients.csv"))
write_csv(wald, file.path(OUT, "P4_wald_common_gamma.csv"))
write_csv(mv,   file.path(OUT, "P4_movement.csv"))
cat("\n[P4] wrote", OUT, "\n")
