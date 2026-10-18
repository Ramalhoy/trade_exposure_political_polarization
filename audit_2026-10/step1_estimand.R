# =============================================================================
# step1_estimand.R — Step 1 (estimand statement) diagnostics, S0 and S3_N2ex
# Base R only; does not source any project script. Reads stored s_rj / g_jt
# (S0) and s_rd / g_dt (S3) and recomputes Rotemberg weights, effective-shock
# counts, AKM estimand weights and the BHJ recentring share from scratch.
# No new outcome regression is run: the only outcome-side computation is the
# reproduction of the already-stored pooled S0/S3 Dalton coefficients.
# =============================================================================
options(width = 160, stringsAsFactors = FALSE)
D  <- Sys.getenv("SS_DATA_DIR", "D"); PD <- file.path(D, "output", "packet_D")
YRS <- c(2014, 2018, 2022); YC <- as.character(YRS)
out <- list()
say <- function(...) cat(sprintf(...), "\n")

# ---------------- S0 sample, built as R00_setup.R builds it ------------------
df  <- readRDS(file.path(D, "df_estimation_v7.rds")); df <- as.data.frame(df)
epw <- as.data.frame(readRDS(file.path(D, "epw_panel_isic_v7.rds")))
df$micro <- as.character(df$microregion_code); epw$micro <- as.character(epw$micro)
df  <- df[df$year %in% YRS & df$micro %in% unique(epw$micro), ]
df$delta_EPW_stored <- df$delta_EPW
m   <- merge(df[, c("micro","year")], epw[epw$year != 2010, c("micro","year","EPW")], all.x = TRUE)
df  <- merge(df, m, by = c("micro","year"), all.x = TRUE, sort = FALSE)
df$EPW[is.na(df$EPW)] <- 0
df  <- df[df$tradable_emp_share > 0 & !is.na(df$manuf_share_of_tradable), ]
df  <- df[order(df$year, df$micro), ]          # canonical row order for this script
rownames(df) <- NULL
say("S0 sample: %d rows, %d micros (df_estimation_v7.rds filtered as R00_setup.R)", nrow(df), length(unique(df$micro)))

sh <- as.data.frame(readRDS(file.path(D, "exposure_shares_isic_v7.rds"))); sh$micro <- as.character(sh$micro)
gk <- as.data.frame(readRDS(file.path(D, "sectoral_shocks_isic_v7.rds")))
inds <- sort(unique(sh$isic4))
mkW <- function(col) { W <- matrix(0, nrow(df), length(inds), dimnames = list(NULL, inds))
  i <- match(sh$micro, df$micro[df$year == 2014]); ok <- !is.na(i)
  W1 <- matrix(0, sum(df$year == 2014), length(inds), dimnames = list(NULL, inds))
  W1[cbind(i[ok], match(sh$isic4[ok], inds))] <- sh[[col]][ok]
  # rows are year-major and micro-sorted within year, so stack W1 three times
  stopifnot(identical(df$micro[df$year == 2014], df$micro[df$year == 2018]),
            identical(df$micro[df$year == 2014], df$micro[df$year == 2022]))
  rbind(W1, W1, W1) }
W_tot  <- mkW("s_rj"); W_trad <- mkW("s_rj_trad")
G <- sapply(YC, function(t) { v <- setNames(rep(0, length(inds)), inds)
  x <- gk[gk$year == as.numeric(t), ]; v[x$isic4[x$isic4 %in% inds]] <- x$g_jt[x$isic4 %in% inds]; v })
yi <- match(as.character(df$year), YC)
bart <- function(W, G) rowSums(W * t(G[, yi]))
x_tot <- bart(W_tot, G); x_trad <- bart(W_trad, G)
say("S0 rebuild vs epw_panel_isic_v7$EPW: max|diff| total-shares = %.3e ; tradable-shares = %.3e",
    max(abs(x_tot - df$EPW)), max(abs(x_trad - df$EPW)))
say("S0 rebuild vs df_estimation_v7$delta_EPW (stored col): max|diff| total = %.3e ; tradable = %.3e",
    max(abs(x_tot - df$delta_EPW_stored)), max(abs(x_trad - df$delta_EPW_stored)))
say("S0 sum_j s_rj (total shares) vs tradable_emp_share: max|diff| = %.3e", max(abs(rowSums(W_tot) - df$tradable_emp_share)))
say("S0 raw treatment: mean %.4f sd %.4f min %.3f max %.3f (PDF Table 3: 0.112, 0.494, -4.726, 9.107)",
    mean(x_tot), sd(x_tot), min(x_tot), max(x_tot))

# ---------------- generic machinery -------------------------------------------
fe_resid <- function(v, ctrl, sy) {             # FWL: residualise on controls + state^year
  X <- model.matrix(~ ., data = data.frame(ctrl, sy = factor(sy)))
  as.numeric(lm.fit(X, v)$residuals) }
zs <- function(v) (v - mean(v)) / sd(v)

diagnose <- function(tag, W, G, x_raw, ctrl, sy, yi, thetaname, theta_lin, labels = NULL) {
  sdx <- sd(x_raw); x <- x_raw / sdx           # scale only; mean absorbed by FE
  xp  <- fe_resid(x, ctrl, sy)
  # ---- Rotemberg (GPSS) weights at the unit-year level, pooled estimator ----
  A <- sapply(seq_along(YC), function(k) { rows <- yi == k
    G[, k] * as.numeric(crossprod(W[rows, , drop = FALSE], xp[rows])) / sdx })
  A <- A / sum(A); dimnames(A) <- list(rownames(G), YC)
  stopifnot(abs(sum(A) - 1) < 1e-10)
  a_unit <- rowSums(A)
  hhi <- function(a) { a <- abs(a) / sum(abs(a)); 1 / sum(a^2) }
  # ---- BHJ exposure weights s_n (unweighted regression: mean of s_rn) --------
  S <- sapply(seq_along(YC), function(k) colSums(W[yi == k, , drop = FALSE]))
  s_ny <- S / sum(S); s_n <- rowSums(s_ny)
  # ---- AKM estimand weights pi_n ∝ sum_r s_rn^2 * (g_nt - mu_t)^2 ------------
  mu <- colSums(S * G) / colSums(S)               # exposure-weighted mean shock by year
  Q  <- sapply(seq_along(YC), function(k) colSums(W[yi == k, , drop = FALSE]^2))
  P  <- Q * sweep(G, 2, mu)^2; P <- P / sum(P); p_unit <- rowSums(P)
  # ---- BHJ recentring: share of residual treatment variance from mu_t*theta --
  xm  <- mu[yi] * theta_lin / sdx
  xmp <- fe_resid(xm, ctrl, sy)
  r2_mean <- sum(xmp * xp)^2 / (sum(xmp^2) * sum(xp^2))
  # ---- serial correlation of the cumulative shocks (exposure weighted) -------
  wc <- function(a, b, w) { w <- w / sum(w); ma <- sum(w*a); mb <- sum(w*b)
    sum(w*(a-ma)*(b-mb)) / sqrt(sum(w*(a-ma)^2) * sum(w*(b-mb)^2)) }
  rho <- c(`14-18` = wc(G[,1], G[,2], s_n), `14-22` = wc(G[,1], G[,3], s_n), `18-22` = wc(G[,2], G[,3], s_n))
  top <- function(v, n = 8) { o <- order(-abs(v))[1:n]
    data.frame(unit = names(v)[o], label = if (is.null(labels)) "" else labels[names(v)[o]], weight = round(v[o], 4)) }
  res <- list(
    tag = tag, n = nrow(W), units = nrow(G), sdx = sdx,
    rot_neg_share = sum(abs(A[A < 0])) / sum(abs(A)),
    rot_eff_unit_year_pooled = hhi(as.vector(A)),
    rot_eff_unit_pooled = hhi(a_unit),
    rot_eff_by_year = sapply(seq_along(YC), function(k) hhi(A[, k])),
    rot_top3_unit = sum(sort(abs(a_unit), decreasing = TRUE)[1:3]) / sum(abs(a_unit)),
    bhj_eff_unit_year = 1 / sum(s_ny^2), bhj_eff_unit = 1 / sum(s_n^2),
    bhj_max_sn = max(s_n), bhj_top_sn = top(s_n, 5),
    akm_eff_unit = hhi(p_unit), akm_top = top(p_unit, 5),
    mu = mu, recentre_r2 = r2_mean, rho = rho,
    rot_top_unit = top(a_unit, 8),
    rot_top_by_year = lapply(seq_along(YC), function(k) top(A[, k], 3)),
    A = A, s_n = s_n, p_unit = p_unit, xp = xp)
  res }

# ---------------- S0 ---------------------------------------------------------
lab0 <- c(`0610`="crude petroleum", `0620`="natural gas", `0710`="iron ores", `0111`="cereals/legumes/oilseeds (soy)",
          `1010`="meat processing", `0810`="stone/sand/clay quarrying", `1701`="pulp & paper", `1920`="refined petroleum",
          `1072`="sugar", `0127`="beverage crops (coffee)", `2410`="basic iron & steel", `2910`="motor vehicles",
          `1061`="grain mill products", `1040`="vegetable & animal oils", `0729`="other non-ferrous ores",
          `1050`="dairy", `0115`="tobacco growing", `1200`="tobacco products", `2011`="basic chemicals",
          `0141`="cattle", `1702`="paperboard/packaging", `2420`="basic precious & non-ferrous metals",
          `0610_0620`="crude petroleum + natural gas (composite)")
cb   <- c("ln_gdp_pc", "ln_pop", "tradable_emp_share")
ctrl0 <- as.data.frame(lapply(df[, cb], zs))
sy0  <- paste(df$state, df$year)
S0   <- diagnose("S0", W_tot, G, x_tot, ctrl0, sy0, yi, "tradable_emp_share", df$tradable_emp_share, lab0)

# reproduce stored pooled S0 Dalton coefficient (base controls, full sample)
y0 <- zs(df$delta_P_dalton); b0 <- sum(S0$xp * fe_resid(y0, ctrl0, sy0)) / sum(S0$xp^2)
e1 <- read.csv(file.path(PD, "E1_estimates.csv"))
e1s <- e1[e1$rung == "S0" & e1$sample == "full" & e1$ctrls == "base" & e1$outcome == "delta_P_dalton" & e1$term == "pooled", ]
say("S0 pooled Dalton beta: recomputed %.6f | stored E1_estimates.csv %.6f", b0, e1s$beta)

# extended controls variant of the Rotemberg concentration (PDF quotes ~2.4 'under the extended control set')
ce <- c(cb, "urban_share", "educ_share", "manuf_share_of_tradable")
S0e <- diagnose("S0_ext", W_tot, G, x_tot, as.data.frame(lapply(df[, ce], zs)), sy0, yi, "tradable_emp_share", df$tradable_emp_share, lab0)

# ---------------- S3_N2ex ----------------------------------------------------
E0 <- readRDS(file.path(PD, "E0_frame.rds")); fr <- as.data.frame(E0$frame)
d1 <- readRDS(file.path(PD, "D1_s_rd.rds")); gd <- as.data.frame(readRDS(file.path(PD, "D3_g_dt.rds")))
srd <- as.data.frame(d1$s_rd); srd$micro <- as.character(srd$micro); srd$destino <- as.integer(srd$destino)
gd$destino <- as.integer(gd$destino)
ENT <- c("NLD","SGP","HKG","ARE","LCA")
ent <- d1$baci_countries$destino[d1$baci_countries$baci_iso3 %in% ENT]
dests <- sort(setdiff(intersect(unique(srd$destino), unique(gd$destino)), ent))
fr$micro <- as.character(fr$micro)
fr  <- fr[order(fr$year, fr$micro), ]; rownames(fr) <- NULL
stopifnot(identical(fr$micro, df$micro), all(fr$year == df$year))
W3 <- matrix(0, nrow(fr), length(dests), dimnames = list(NULL, paste0("d", dests)))
s2 <- srd[srd$destino %in% dests, ]
for (k in seq_along(YC)) { rows <- which(fr$year == YRS[k])
  i <- match(s2$micro, fr$micro[rows]); ok <- !is.na(i)
  W3[cbind(rows[i[ok]], match(s2$destino[ok], dests))] <- s2$s_rd_n2[ok] }
G3 <- sapply(YRS, function(t) { v <- setNames(rep(0, length(dests)), paste0("d", dests))
  x <- gd[gd$ano == t & gd$destino %in% dests, ]; v[paste0("d", x$destino)] <- x$g_dt; v }); colnames(G3) <- YC
yi3 <- match(as.character(fr$year), YC)
x3 <- bart(W3, G3)
say("S3 rebuild vs E0_frame$epw_S3_N2ex: max|diff| = %.3e", max(abs(x3 - fr$epw_S3_N2ex)))
iso <- setNames(gd$iso3, paste0("d", gd$destino)); iso <- iso[!duplicated(names(iso))]
ctrl3 <- data.frame(ctrl0, Theta_log = fr$Theta_log, Theta_zero = fr$Theta_zero)
S3 <- diagnose("S3_N2ex", W3, G3, x3, ctrl3, sy0, yi3, "theta_r_dest", fr$theta_r_dest, iso)
y3 <- fr$delta_P_dalton; b3 <- sum(S3$xp * fe_resid(y3, ctrl3, sy0)) / sum(S3$xp^2)
e3 <- e1[e1$rung == "S3_N2ex" & e1$sample == "full" & e1$ctrls == "base" & e1$outcome == "delta_P_dalton" & e1$term == "pooled", ]
say("S3 pooled Dalton beta: recomputed %.6f | stored E1_estimates.csv %.6f", b3, e3$beta)
say("S3 treatment: exporting micros %d of %d; corr(S0,S3) = %.3f", sum(rowSums(W3[yi3==1,])>0), sum(yi3==1), cor(x_tot, x3))

# ---------------- report -----------------------------------------------------
for (R in list(S0, S0e, S3)) {
  cat("\n================", R$tag, "================\n")
  say("rows %d | shock units %d | sd(raw treatment) %.4f", R$n, R$units, R$sdx)
  say("Rotemberg: eff. units (unit level, years summed) %.2f | eff. unit-years %.2f | by year %s",
      R$rot_eff_unit_pooled, R$rot_eff_unit_year_pooled, paste(sprintf("%.2f", R$rot_eff_by_year), collapse = " / "))
  say("Rotemberg: share of |alpha| that is negative %.3f | top-3 units carry %.3f of |alpha|", R$rot_neg_share, R$rot_top3_unit)
  say("BHJ exposure weights: 1/sum s_n^2 unit level %.1f | unit-year %.1f | max s_n %.3f", R$bhj_eff_unit, R$bhj_eff_unit_year, R$bhj_max_sn)
  say("AKM estimand weights (s_rn^2 * (g-mu)^2): eff. units %.2f", R$akm_eff_unit)
  say("Exposure-weighted mean shock mu_t: %s", paste(sprintf("%.4f", R$mu), collapse = " / "))
  say("BHJ recentring: R^2 of residualised treatment on residualised mu_t*sum-of-shares = %.3f", R$recentre_r2)
  say("Serial corr of shocks (exposure-weighted): %s", paste(names(R$rho), sprintf("%.2f", R$rho), collapse = "  "))
  cat("Top units by pooled Rotemberg weight:\n"); print(R$rot_top_unit, row.names = FALSE)
  for (k in 1:3) { cat("Top-3", YC[k], ":\n"); print(R$rot_top_by_year[[k]], row.names = FALSE) }
  cat("Top AKM estimand weights:\n"); print(R$akm_top, row.names = FALSE)
  cat("Top BHJ exposure weights s_n:\n"); print(R$bhj_top_sn, row.names = FALSE)
}
saveRDS(list(S0 = S0[names(S0) != "xp"], S0e = S0e[names(S0e) != "xp"], S3 = S3[names(S3) != "xp"]), "step1_results.rds")

# ---------------- addenda: code-style per-year Rotemberg, within-year shares, leverage
peryear <- function(W, G, x_raw, ctrl, st, yrv, yi) sapply(seq_along(YC), function(k) {
  rows <- yi == k; d <- data.frame(ctrl[rows, , drop = FALSE], st = factor(st[rows]))
  X <- model.matrix(~ ., d); xp <- lm.fit(X, x_raw[rows])$residuals
  a <- G[, k] * as.numeric(crossprod(W[rows, , drop = FALSE], xp)); a <- a / sum(a)
  c(eff = 1 / sum((abs(a)/sum(abs(a)))^2), top = max(a), which = as.numeric(which.max(a))) })
py0 <- peryear(W_tot, G, x_tot, ctrl0, df$state, df$year, yi)
py0e <- peryear(W_tot, G, x_tot, as.data.frame(lapply(df[, ce], zs)), df$state, df$year, yi)
py3 <- peryear(W3, G3, x3, ctrl3, df$state, df$year, yi3)
cat("\nCode-style (ss_rotemberg: within-year residualisation, within-year normalisation)\n")
say("S0 base eff by year %s | top alpha %s (%s)", paste(sprintf("%.2f", py0["eff",]), collapse=" / "),
    paste(sprintf("%.3f", py0["top",]), collapse=" / "), paste(inds[py0["which",]], collapse=","))
say("S0 ext  eff by year %s | mean %.2f | top alpha %s (%s)", paste(sprintf("%.2f", py0e["eff",]), collapse=" / "), mean(py0e["eff",]),
    paste(sprintf("%.3f", py0e["top",]), collapse=" / "), paste(inds[py0e["which",]], collapse=","))
say("S3 base eff by year %s | top alpha %s (%s)", paste(sprintf("%.2f", py3["eff",]), collapse=" / "),
    paste(sprintf("%.3f", py3["top",]), collapse=" / "), paste(iso[paste0("d", dests[py3["which",]])], collapse=","))

# leverage: share of the identifying covariance sum_r x_perp*x carried by microregions
lev <- function(xp, x_raw, tag) { c_r <- xp * (x_raw / sd(x_raw)); c_r <- c_r / sum(c_r)
  agg <- tapply(c_r, df$micro, sum); o <- order(-abs(agg))
  say("%s: top-10 microregions carry %.3f of sum(x_perp*x); top-25 %.3f; eff. micros %.1f", tag,
      sum(agg[o[1:10]]), sum(agg[o[1:25]]), 1 / sum((abs(agg)/sum(abs(agg)))^2))
  data.frame(micro = names(agg)[o[1:10]], share = round(agg[o[1:10]], 3)) }
xp0 <- fe_resid(x_tot / sd(x_tot), ctrl0, sy0); xp3 <- fe_resid(x3 / sd(x3), ctrl3, sy0)
l0 <- lev(xp0, x_tot, "S0"); l3 <- lev(xp3, x3, "S3")
nm <- unique(as.data.frame(readRDS(file.path(D, "exposure_shares_isic_v7.rds")))[, c("micro","state")]); nm$micro <- as.character(nm$micro)
print(merge(l0, nm, sort = FALSE)); print(merge(l3, nm, sort = FALSE))
# shock scale: why oil/iron dominate (capital-intensity gradient)
gsd <- apply(G, 1, sd); s_tot <- colSums(W_tot[yi == 1, ])
cat("\nS0 shocks g_jt for top industries (2014/2018/2022) and national L_j share:\n")
for (j in c("0610","0710","0111","0141","1010")) say("%s g = %s | exposure weight s_n = %.3f", j,
  paste(sprintf("%.2f", G[j, ]), collapse=" / "), s_tot[j]/sum(s_tot))
say("median |g_jt| across 152 industries by year: %s", paste(sprintf("%.3f", apply(abs(G), 2, median)), collapse=" / "))

# ---------------- what the boom / bust regressors are made of ----------------
contrib <- W_tot * t(G[, yi])                      # r x j contributions to raw EPW
bust <- x_tot < 0; boom <- x_tot > 0
cb_ <- function(rows, j) sum(contrib[rows, j]) / sum(x_tot[rows])
say("Bust rows %d: share of sum(EPW-) from 0710 iron ores %.3f, 0610 oil %.3f", sum(bust), cb_(bust, "0710"), cb_(bust, "0610"))
say("Boom rows %d: share of sum(EPW+) from 0610 oil %.3f, 0710 %.3f, 0111 soy %.3f", sum(boom), cb_(boom, "0610"), cb_(boom, "0710"), cb_(boom, "0111"))
say("Top-10 leverage overlap S0 vs S3: %s", paste(intersect(l0$micro, l3$micro), collapse = ","))
