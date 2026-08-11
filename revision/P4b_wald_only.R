# =============================================================================
# P4b — corrected joint Wald test of the common-gamma restriction only.
# Separated from P4 because the RI block in P4 is what makes it expensive, and
# the RI results are already on disk from a completed run. The Wald test in the
# first P4 run was under-specified: R writes the interaction as
# "ln_gdp_pc:yf2014" for the first control and "yf2014:ln_pop" for the rest, so
# matching "^<ctrl>:yf" tested ONE control (q = 2) instead of all of them.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("P4")

d <- df_scaled |> mutate(yf = factor(year))

wald <- map_dfr(outcomes, function(oc) map_dfr(c("base","ext"), function(ck) {
  ctrls <- if (ck=="base") ctrl_base else ctrl_ext
  cz <- paste(paste0(ctrls, ":yf"), collapse = " + ")
  m <- feols(as.formula(paste(oc, "~ delta_EPW +", cz, "| state^year")),
             data = d, cluster = ~ mesoregion_code^year)
  nm <- names(coef(m))
  R <- matrix(0, nrow = 0, ncol = length(nm), dimnames = list(NULL, nm))
  per_ctrl <- integer(0)
  for (cv in ctrls) {
    cols <- grep(paste0("(^|:)", cv, "($|:)"), nm, value = TRUE)
    cols <- cols[grepl("yf", cols)]
    cols <- cols[order(sub(".*yf([0-9]{4}).*", "\\1", cols))]
    per_ctrl <- c(per_ctrl, setNames(length(cols), cv))
    if (length(cols) < 2) next
    for (j in 2:length(cols)) {
      r <- setNames(numeric(length(nm)), nm); r[cols[1]] <- 1; r[cols[j]] <- -1
      R <- rbind(R, r)
    }
  }
  b <- coef(m); V <- vcov(m); q <- nrow(R)
  stat <- as.numeric(t(R %*% b) %*% solve(R %*% V %*% t(R)) %*% (R %*% b)) / q
  dof <- fixest::degrees_freedom(m, type = "t")
  cat(sprintf("[P4b] %s / %s : %d coefficients, columns per control = %s, q = %d\n",
              oc, ck, length(nm), paste(per_ctrl, collapse = "/"), q))
  tibble(outcome = oc, ctrls = ck, n_controls = length(ctrls), q = q,
         F = stat, df2 = dof, p = pf(stat, q, dof, lower.tail = FALSE))
}))

cat("\n=== P4b joint Wald test of the common-gamma restriction (CORRECTED) ===\n")
print(as.data.frame(wald), digits = 4)

# per-control tests, so a single offending covariate is visible
per <- map_dfr(outcomes, function(oc) map_dfr(c("base","ext"), function(ck) {
  ctrls <- if (ck=="base") ctrl_base else ctrl_ext
  cz <- paste(paste0(ctrls, ":yf"), collapse = " + ")
  m <- feols(as.formula(paste(oc, "~ delta_EPW +", cz, "| state^year")),
             data = d, cluster = ~ mesoregion_code^year)
  nm <- names(coef(m)); b <- coef(m); V <- vcov(m)
  dof <- fixest::degrees_freedom(m, type = "t")
  map_dfr(ctrls, function(cv) {
    cols <- grep(paste0("(^|:)", cv, "($|:)"), nm, value = TRUE)
    cols <- cols[grepl("yf", cols)]
    cols <- cols[order(sub(".*yf([0-9]{4}).*", "\\1", cols))]
    R <- matrix(0, nrow = 0, ncol = length(nm), dimnames = list(NULL, nm))
    for (j in 2:length(cols)) {
      r <- setNames(numeric(length(nm)), nm); r[cols[1]] <- 1; r[cols[j]] <- -1
      R <- rbind(R, r)
    }
    stat <- as.numeric(t(R %*% b) %*% solve(R %*% V %*% t(R)) %*% (R %*% b)) / nrow(R)
    tibble(outcome = oc, ctrls = ck, control = cv,
           coef_2014 = b[[cols[1]]], coef_2018 = b[[cols[2]]], coef_2022 = b[[cols[3]]],
           q = nrow(R), F = stat, p = pf(stat, nrow(R), dof, lower.tail = FALSE))
  })
}))
cat("\n=== P4b per-control tests of year-invariance ===\n")
print(as.data.frame(per), digits = 4)

write_csv(wald, file.path(OUT, "P4_wald_common_gamma.csv"))
write_csv(per,  file.path(OUT, "P4_wald_per_control.csv"))
cat("\n[P4b] wrote", OUT, "\n")
