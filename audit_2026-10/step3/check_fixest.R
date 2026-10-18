source("audit/ss_core.R"); library(fixest)
pre <- readRDS("audit/out/dalton_deputado_2002_2006.rds"); pre$micro <- as.character(pre$micro)
u0 <- merge_units(W0_1, G0, sec0); des <- build_design(u0$W1, u0$G, u0$strata)
r1 <- which(yi == 1); zbar <- (des$zt[yi == 1] + des$zt[yi == 2] + des$zt[yi == 3]) / 3
d0 <- setNames(pre$P_dalton[pre$year == 2002], pre$micro[pre$year == 2002])
dd <- data.frame(y = zs(as.numeric(b10[m14] - d0[m14])), x = zbar / sd(zbar), ctrl_base0[r1, ], st = df$state[r1])
cat(sprintf("fixest beta (S0, 2002->2010) = %.8f  [gate_d_falsification.csv: -0.01733748]\n",
            coef(feols(y ~ x + ln_gdp_pc + ln_pop + theta | st, dd))["x"]))
