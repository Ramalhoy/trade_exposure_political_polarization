# =============================================================================
# ss_core.R — shared objects for the step-3 gates (base R only).
# Builds, for S0 and S3_N2ex: the share matrix W (total-employment convention),
# the shock-path matrix G, strata, exchangeability units, the Borusyak-Hull
# expected treatment mu (closed form under within-stratum permutation of whole
# shock paths), the recentred treatment z_tilde, controls, FE cells, and the
# B = 9,999 permutation draws (seed 2026). No outcome enters this file except
# the deputy Dalton panel, which is loaded but only residualised on controls.
# =============================================================================
D  <- Sys.getenv("SS_DATA_DIR", "D"); PD <- file.path(D, "output", "packet_D")
YRS <- c(2014, 2018, 2022); YC <- as.character(YRS); B <- 9999L
zs <- function(v) (v - mean(v)) / sd(v)

# ---- estimation frame (as R00_setup.R / step1) -------------------------------
df  <- as.data.frame(readRDS(file.path(D, "df_estimation_v7.rds")))
df$micro <- as.character(df$microregion_code)
df  <- df[df$year %in% YRS & df$tradable_emp_share > 0 & !is.na(df$manuf_share_of_tradable), ]
df  <- df[order(df$year, df$micro), ]; rownames(df) <- NULL
stopifnot(nrow(df) == 1671)
yi  <- match(as.character(df$year), YC)
m14 <- df$micro[yi == 1]
stopifnot(identical(m14, df$micro[yi == 2]), identical(m14, df$micro[yi == 3]))

stack3 <- function(W1) rbind(W1, W1, W1)

# ---- S0: shares (total employment) and shocks --------------------------------
sh <- as.data.frame(readRDS(file.path(D, "exposure_shares_isic_v7.rds"))); sh$micro <- as.character(sh$micro)
stopifnot(max(abs(sh$s_rj - sh$theta_r * sh$s_rj_trad)) < 1e-12)       # total convention
inds <- sort(unique(sh$isic4))
W0_1 <- matrix(0, length(m14), length(inds), dimnames = list(m14, inds))
ok <- sh$micro %in% m14
W0_1[cbind(match(sh$micro[ok], m14), match(sh$isic4[ok], inds))] <- sh$s_rj[ok]
gk <- as.data.frame(readRDS(file.path(D, "sectoral_shocks_isic_v7.rds")))
G0 <- sapply(YRS, function(t) { v <- setNames(rep(0, length(inds)), inds)
  x <- gk[gk$year == t & gk$isic4 %in% inds, ]; v[x$isic4] <- x$g_jt; v }); colnames(G0) <- YC
sec0 <- with(list(d2 = as.integer(substr(inds, 1, 2))), ifelse(d2 <= 3, "A", ifelse(d2 <= 9, "B", "C")))
names(sec0) <- inds

# ---- S3_N2ex: destination shares and shocks -----------------------------------
d1  <- readRDS(file.path(PD, "D1_s_rd.rds")); gd <- as.data.frame(readRDS(file.path(PD, "D3_g_dt.rds")))
srd <- as.data.frame(d1$s_rd); srd$micro <- as.character(srd$micro); srd$destino <- as.integer(srd$destino)
gd$destino <- as.integer(gd$destino)
ENT  <- c("NLD", "SGP", "HKG", "ARE", "LCA")
ent  <- d1$baci_countries$destino[d1$baci_countries$baci_iso3 %in% ENT]
dests <- sort(setdiff(intersect(unique(srd$destino), unique(gd$destino)), ent))
s2 <- srd[srd$destino %in% dests & srd$micro %in% m14, ]
W3_1 <- matrix(0, length(m14), length(dests), dimnames = list(m14, paste0("d", dests)))
W3_1[cbind(match(s2$micro, m14), match(s2$destino, dests))] <- s2$s_rd_n2
G3 <- sapply(YRS, function(t) { v <- setNames(rep(0, length(dests)), paste0("d", dests))
  x <- gd[gd$ano == t & gd$destino %in% dests, ]; v[paste0("d", x$destino)] <- x$g_dt; v }); colnames(G3) <- YC
iso <- setNames(gd$iso3, paste0("d", gd$destino)); iso <- iso[!duplicated(names(iso))][colnames(W3_1)]
wb  <- read.csv(Sys.getenv("SS_WB_CSV", "wb_regions.csv"), stringsAsFactors = FALSE)   # Code, Region
reg <- wb$Region[match(iso, wb$Code)]
fix <- c(S19 = "East Asia & Pacific", COK = "East Asia & Pacific", NFK = "East Asia & Pacific",
         PCN = "East Asia & Pacific", WLF = "East Asia & Pacific", IOT = "East Asia & Pacific",
         FLK = "Latin America & Caribbean", MSR = "Latin America & Caribbean",
         ANT = "Latin America & Caribbean", AIA = "Latin America & Caribbean")
reg[is.na(reg)] <- fix[iso[is.na(reg)]]
stopifnot(!anyNA(reg))
reg[reg %in% c("East Asia & Pacific", "South Asia")]        <- "EAP+SA"
reg[reg %in% c("Europe & Central Asia", "North America")]   <- "ECA+NA"
reg[reg == "Latin America & Caribbean"] <- "LAC"
reg[reg == "Middle East, North Africa, Afghanistan & Pakistan"] <- "MENA"
reg[reg == "Sub-Saharan Africa"] <- "SSA"
sec3 <- setNames(reg, colnames(W3_1))

# ---- exchangeability units: merge columns with identical shares in every r ----
merge_units <- function(W1, G, strata) {
  key <- apply(W1, 2, function(v) paste(format(v, digits = 15), collapse = "|"))
  grp <- match(key, unique(key))
  dup <- split(colnames(W1), grp); dup <- dup[lengths(dup) > 1]
  if (length(dup)) for (d in dup) {
    stopifnot(length(unique(strata[d])) == 1)
    G[d[1], ] <- colSums(G[d, , drop = FALSE]); keep <- setdiff(colnames(W1), d[-1])
    W1 <- W1[, keep, drop = FALSE]; G <- G[keep, , drop = FALSE]; strata <- strata[keep] }
  list(W1 = W1, G = G, strata = strata, merged = dup) }

# ---- recentring and permutations ----------------------------------------------
build_design <- function(W1, G, strata, seed = 2026) {
  W <- stack3(W1)
  z <- rowSums(W * t(G[, yi]))
  gbar <- apply(G, 2, function(g) ave(g, strata))            # stratum-year means (unweighted)
  mu <- rowSums(W * t(gbar[, yi]))
  zt <- z - mu
  set.seed(seed)
  idx <- split(seq_along(strata), strata)
  perms <- replicate(B, { p <- seq_along(strata); for (k in idx) p[k] <- if (length(k) > 1) sample(k) else k; p })
  list(W1 = W1, W = W, G = G, strata = strata, z = z, mu = mu, zt = zt, perms = perms)
}

# ---- FE + controls projection ---------------------------------------------------
proj_maker <- function(ctrl) {
  X <- model.matrix(~ ., data.frame(ctrl, sy = factor(paste(df$state, df$year))))
  Q <- qr.Q(qr(X)); function(M) M - Q %*% crossprod(Q, M) }

ctrl_base0 <- data.frame(ln_gdp_pc = zs(df$ln_gdp_pc), ln_pop = zs(df$ln_pop), theta = zs(df$tradable_emp_share))
E0 <- as.data.frame(readRDS(file.path(PD, "E0_frame.rds"))$frame); E0$micro <- as.character(E0$micro)
E0 <- E0[order(E0$year, E0$micro), ]; stopifnot(identical(E0$micro, df$micro))
ctrl_base3 <- data.frame(ln_gdp_pc = zs(df$ln_gdp_pc), ln_pop = zs(df$ln_pop),
                         Theta_log = E0$Theta_log, Theta_zero = E0$Theta_zero)

# ---- permuted, recentred, residualised treatments (n x B) -----------------------
perm_matrix <- function(des, P, sdx) {
  Zs <- matrix(0, nrow(des$W), B)
  for (b in seq_len(B)) { Gp <- des$G[des$perms[, b], , drop = FALSE]
    Zs[, b] <- rowSums(des$W * t(Gp[, yi])) }
  Zs <- (Zs - des$mu) / sdx
  P(Zs) }

# ---- primary outcome: deputy Dalton, 2010 -> t ----------------------------------
dep <- as.data.frame(readRDS(file.path(D, "dalton_panel_deputado_federal.rds")))
dep$micro <- as.character(dep$microregion_code)
b10 <- setNames(dep$P_dalton[dep$year == 2010], dep$micro[dep$year == 2010])
dlt <- setNames(dep$P_dalton, paste(dep$micro, dep$year))
y_dep <- dlt[paste(df$micro, df$year)] - b10[df$micro]
stopifnot(!anyNA(y_dep)); y_dep <- zs(as.numeric(y_dep))

# ---- RI machinery ------------------------------------------------------------------
ri_fit <- function(yp, xp, Xs) {          # yp, xp: residualised; Xs: residualised permuted x (n x B)
  ss <- colSums(Xs^2); bh <- sum(xp * yp) / sum(xp^2)
  bs <- as.numeric(crossprod(Xs, yp)) / ss
  cs <- as.numeric(crossprod(Xs, xp)) / ss
  list(beta = bh, bstar = bs, c = cs, p = (1 + sum(abs(bs) >= abs(bh))) / (B + 1)) }
p_at <- function(f, b) (1 + sum(abs(f$bstar - b * f$c) >= abs(f$beta - b))) / (B + 1)
ci_inv <- function(f, level = 0.90, step = 0.0005, span = 0.4) {
  a <- 1 - level; g <- seq(f$beta - span, f$beta + span, by = step)
  acc <- g[vapply(g, function(b) p_at(f, b) > a, TRUE)]
  if (!length(acc)) return(c(NA, NA))
  if (min(acc) <= min(g) + step || max(acc) >= max(g) - step) warning("CI touches grid edge")
  c(min(acc), max(acc)) }
