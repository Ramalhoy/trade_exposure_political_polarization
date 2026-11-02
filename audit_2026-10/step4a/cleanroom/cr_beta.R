# =============================================================================
# cr_beta.R — CLEAN-ROOM headline coefficient (A1.4, A3.3.6). Imports no project
# code. From the clean-room treatment objects (cr_s0.R, cr_s3.R) and the written
# plan (02_analysis_plan.md §1) only:
#   - exchangeability units: columns with identical shares in every microregion
#     are merged (their shocks add, since s*g1 + s*g2 = s*(g1+g2));
#   - strata: S0 ISIC section from the 2-digit division (01-03 A, 05-09 B,
#     10-33 C); S3 World Bank region (wb_regions.csv), 10 uncoded territories by
#     geography (plan §1), EAP+SA and ECA+NA merged;
#   - mu_rt = sum_k (sum_{n in k} s_rn) * gbar_kt, gbar = unweighted stratum-year mean;
#   - x = (z - mu) / sd over the 1,671-row frame; y = Δ deputy Dalton (2010 -> t),
#     standardised over the same frame;
#   - fixest::feols(y ~ x + controls | state^year); S0 controls ln GDP pc,
#     ln pop, theta; S3 controls ln GDP pc, ln pop, log(1 + theta_dest), 1{theta_dest = 0},
#     theta_dest = sum of the clean-room destination shares.
# Pass (A1.4/A3.3.6): |β_cr / β_audit − 1| <= 1e-8 for both designs.
# =============================================================================
invisible(Sys.setlocale("LC_ALL", "C.UTF-8")); suppressMessages({ library(data.table); library(fixest) })
D <- Sys.getenv("SS_DATA_DIR", "D")
df <- as.data.table(readRDS(file.path(D, "df_estimation_v7.rds")))
df <- df[year %in% c(2014, 2018, 2022) & tradable_emp_share > 0 & !is.na(manuf_share_of_tradable)]
df[, micro := as.integer(microregion_code)]; setorder(df, year, micro)
dp <- as.data.table(readRDS(file.path(D, "dalton_panel_deputado_federal.rds")))
b0 <- dp[year == 2010, .(micro = as.integer(microregion_code), d0 = P_dalton)]
dt <- dp[, .(micro = as.integer(microregion_code), year, d = P_dalton)]
df <- merge(merge(df, dt, by = c("micro", "year")), b0, by = "micro"); setorder(df, year, micro)
std <- function(v) (v - mean(v)) / sd(v)
df[, y := std(d - d0)]
recentre <- function(S, G, strata) {   # S: micro x unit share matrix; G: unit x year (cols "2014","2018","2022")
  key <- apply(S, 2, function(v) paste(sprintf("%.15e", v), collapse = ","))
  grp <- match(key, unique(key)); first <- !duplicated(grp)
  G2 <- rowsum(G, grp)[as.character(grp[first]), , drop = FALSE]
  S2 <- S[, first, drop = FALSE]; st2 <- strata[first]
  stopifnot(all(tapply(strata, grp, function(v) length(unique(v)) == 1)))
  gbar <- apply(G2, 2, function(g) ave(g, st2))
  list(z = S2 %*% G2, mu = S2 %*% gbar, merged = sum(!first), units = ncol(S2)) }
out <- list()
# ---- S0 --------------------------------------------------------------------------------
c0 <- readRDS("audit/out/cleanroom_s0.rds")
s0 <- dcast(as.data.table(c0$s), microregion_code ~ j, value.var = "s", fill = 0)
S <- as.matrix(s0[, -1]); rownames(S) <- s0$microregion_code
S <- S[, c0$uni]; S <- S[as.character(df[year == 2014, micro]), ]
d2 <- as.integer(substr(c0$uni, 1, 2)); strata <- ifelse(d2 <= 3, "A", ifelse(d2 <= 9, "B", "C"))
out$S0 <- list(r = recentre(S, c0$g, strata), ctrl = "ln_gdp_pc + ln_pop + tradable_emp_share")
# ---- S3 --------------------------------------------------------------------------------
c3 <- readRDS("audit/out/cleanroom_s3.rds")
X <- as.data.table(c3$X)[d %in% c3$keep]
s3 <- dcast(X, micro ~ d, value.var = "s", fill = 0, fun.aggregate = sum)
S <- matrix(0, nrow(df[year == 2014]), length(c3$keep), dimnames = list(df[year == 2014, micro], sort(c3$keep)))
S3 <- as.matrix(s3[, -1]); rownames(S3) <- s3$micro; S3 <- S3[rownames(S3) %in% rownames(S), , drop = FALSE]
S[rownames(S3), colnames(S3)] <- S3
G <- dcast(as.data.table(c3$G)[d %in% c3$keep], d ~ t, value.var = "g"); Gm <- as.matrix(G[, -1]); rownames(Gm) <- G$d
Gm <- Gm[colnames(S), ]
cc <- fread(file.path(D, "baci", "country_codes_V202601.csv"))
iso <- cc$country_iso3[match(as.integer(colnames(S)), cc$country_code)]
wb <- fread(Sys.getenv("SS_WB_CSV", "wb_regions.csv")); reg <- wb$Region[match(iso, wb$Code)]
terr <- c(IOT = "EAP", COK = "EAP", NFK = "EAP", PCN = "EAP", WLF = "EAP", S19 = "EAP", FLK = "LAC", MSR = "LAC", ANT = "LAC", AIA = "LAC")
reg <- ifelse(!is.na(reg), reg, terr[iso]); stopifnot(!anyNA(reg))
reg <- ifelse(grepl("East Asia|South Asia|^EAP$", reg), "EAP+SA", ifelse(grepl("Europe|North America", reg), "ECA+NA",
       ifelse(grepl("Latin|^LAC$", reg), "LAC", ifelse(grepl("Middle East", reg), "MENA", ifelse(grepl("Sub-Saharan", reg), "SSA", NA)))))
stopifnot(!anyNA(reg))
df14 <- df[year == 2014]; th <- rowSums(S)[as.character(df14$micro)]
df[, theta_dest := th[as.character(micro)]]; df[, `:=`(th_log = log1p(theta_dest), th_zero = as.numeric(theta_dest == 0))]
out$S3 <- list(r = recentre(S, Gm, reg), ctrl = "ln_gdp_pc + ln_pop + th_log + th_zero")
# DIAGNOSTIC variant (not the gate): theta_dest summed over ALL destinations in the 2010
# Comex shares, entrepots included — the definition found in E0_frame.rds (theta_r_dest).
tha <- as.data.table(c3$X)[, .(t = sum(s)), by = micro]; ta <- tha$t[match(df$micro, tha$micro)]; ta[is.na(ta)] <- 0
df[, `:=`(tha_log = log1p(ta), tha_zero = as.numeric(ta == 0))]
out$S3_diag_theta_all <- list(r = out$S3$r, ctrl = "ln_gdp_pc + ln_pop + tha_log + tha_zero")
# ---- estimates ---------------------------------------------------------------------------
au <- read.csv("audit/out/step4_primary.csv")
res <- rbindlist(lapply(names(out), function(nm) { r <- out[[nm]]$r
  yi <- match(df$year, c(2014, 2018, 2022)); m <- match(as.character(df$micro), rownames(r$z))
  zt <- r$z[cbind(m, yi)] - r$mu[cbind(m, yi)]; df[, x := zt / sd(zt)]
  fit <- feols(as.formula(paste("y ~ x +", out[[nm]]$ctrl, "| state^year")), data = df)
  b <- coef(fit)[["x"]]; ba <- au$beta[au$design == sub("_.*", "", nm)]
  data.table(design = nm, units = r$units, merged = r$merged, n_used = nobs(fit), beta_cleanroom = b, beta_audit = ba,
             rel_diff = b / ba - 1, pass = abs(b / ba - 1) <= 1e-8) }))
print(res); fwrite(res, "audit/out/step4_cleanroom_beta.csv")
