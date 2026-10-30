# =============================================================================
# step4_outcomes.R — every outcome used in step 4, built from the stored
# round-1 ideological panels (governor: repaired copy, A3.2), aligned to the
# 1,671-row estimation frame (ss_core.R order), as 2010 -> t changes.
# Indices per microregion-year on scored votes (shares among scored votes):
#   Dalton  sqrt(sum w (y - ybar)^2); ybar = sum w y; centre = share |y| > 0.25;
#   Esteban-Ray(alpha) = sum_p sum_q w_p^(1+alpha) w_q |y_p - y_q|.
# Canaries: Dalton, ybar and centre reproduce the stored panels; ER reproduces
# E0_frame.rds (president). Deputy coverage = scored votes / all votes, per cell.
# Requires ss_core.R to be sourced first (df, m14, yi).
# =============================================================================
library(data.table)
idx_tab <- function(p, idcol = "microregion_code") {
  p <- p[!is.na(ideo) & votes > 0]
  p[, {
    a <- tapply(votes, party, sum); y <- as.numeric(tapply(ideo, party, `[`, 1)[names(a)]); w <- as.numeric(a / sum(a))
    yb <- sum(w * y); Dw <- as.numeric(abs(outer(y, y, "-")) %*% w)
    .(dalton = sqrt(sum(w * (y - yb)^2)), ybar = yb, centre = sum(w * (abs(y) > 0.25)),
      er10 = sum(w^2 * Dw), er14 = sum(w^2.4 * Dw)) }, by = c(idcol, "year")]
}
panels <- list(
  dep = as.data.table(readRDS(file.path(D, "painel_ideologico_deputado_federal.rds")))[round == 1],
  pres = as.data.table(readRDS(file.path(D, "painel_ideologico_presidencial.rds")))[round == 1],
  gov = as.data.table(readRDS("audit/out/painel_ideologico_governador_repaired.rds"))[round == 1])
panels$gov <- panels$gov[scored == TRUE | is.na(scored)]
stored <- list(dep = as.data.table(readRDS(file.path(D, "dalton_panel_deputado_federal.rds"))),
               pres = as.data.table(readRDS(file.path(D, "dalton_panel_presidencial.rds"))),
               gov = as.data.table(readRDS("audit/out/dalton_panel_governador_repaired.rds")))
OUT <- list(); canary <- list()
for (o in names(panels)) {
  it <- idx_tab(panels[[o]])
  cmp <- merge(it, stored[[o]], by = c("microregion_code", "year"))
  canary[[o]] <- data.frame(office = o, dalton = max(abs(cmp$dalton - cmp$P_dalton)),
    centre = max(abs(cmp$centre - cmp$P_center)),
    ybar = if ("y_bar" %in% names(cmp)) max(abs(cmp$ybar - cmp$y_bar)) else NA, cells = nrow(cmp))
  base <- it[year == 2010]; key <- paste(df$micro, df$year)
  cur <- it[match(key, paste(it$microregion_code, it$year))]; b0 <- base[match(df$micro, as.character(base$microregion_code))]
  for (v in c("dalton", "ybar", "centre", "er10", "er14")) OUT[[paste(o, v, sep = "_")]] <- cur[[v]] - b0[[v]]
}
outc <- as.data.frame(OUT)
stopifnot(!anyNA(outc), nrow(outc) == 1671)
# ER canary against E0 (president, standardised over the 1,671 rows there)
canary$er <- data.frame(office = "pres_ER_vs_E0", dalton = max(abs(zs(outc$pres_er10) - E0$delta_P_er_10)),
                        centre = max(abs(zs(outc$pres_er14) - E0$delta_P_er_14)), ybar = NA, cells = 1671)
# deputy coverage per cell and the >= 0.85 rule (both 2010 and t)
cv <- panels$dep[, .(cov = sum(votes[!is.na(ideo)]) / sum(votes)), by = .(microregion_code, year)]
c0 <- cv[year == 2010][match(df$micro, as.character(microregion_code)), cov]
ct <- cv[match(paste(df$micro, df$year), paste(microregion_code, year)), cov]
outc$dep_cov_ok <- c0 >= 0.85 & ct >= 0.85
canary <- rbindlist(canary)
