# New Table 3 rows for the v4 text: deputy and governor Dalton changes, and the recentred treatments
source("audit/ss_core.R"); suppressMessages(library(data.table))
u0 <- merge_units(W0_1, G0, sec0); d0 <- build_design(u0$W1, u0$G, u0$strata)
u3 <- merge_units(W3_1, G3, sec3); d3 <- build_design(u3$W1, u3$G, u3$strata)
dep <- as.data.frame(readRDS(file.path(D, "dalton_panel_deputado_federal.rds"))); dep$micro <- as.character(dep$microregion_code)
b10 <- setNames(dep$P_dalton[dep$year == 2010], dep$micro[dep$year == 2010]); lv <- setNames(dep$P_dalton, paste(dep$micro, dep$year))
ydep <- as.numeric(lv[paste(df$micro, df$year)] - b10[df$micro])
gv <- as.data.frame(readRDS("audit/out/dalton_panel_governador_repaired.rds")); gv$micro <- as.character(gv$microregion_code)
g10 <- setNames(gv$P_dalton[gv$year == 2010], gv$micro[gv$year == 2010]); gl <- setNames(gv$P_dalton, paste(gv$micro, gv$year))
ygov <- as.numeric(gl[paste(df$micro, df$year)] - g10[df$micro])
v <- list(`dDalton deputy` = ydep, `dDalton governor (repaired)` = ygov, `dDalton president` = df$delta_P_dalton,
          `S0 z (raw)` = d0$z, `S0 z recentred` = d0$zt, `S3 z (raw)` = d3$z, `S3 z recentred` = d3$zt, theta_dest = theta_dest)
r <- rbindlist(lapply(names(v), function(k) { x <- v[[k]]; data.table(var = k, N = sum(!is.na(x)), mean = mean(x, na.rm = TRUE), sd = sd(x, na.rm = TRUE),
  min = min(x, na.rm = TRUE), p25 = quantile(x, .25, na.rm = TRUE), med = median(x, na.rm = TRUE), p75 = quantile(x, .75, na.rm = TRUE), max = max(x, na.rm = TRUE)) }))
r <- rbind(r, data.table(var = "share dDalton deputy > 0", N = length(ydep), mean = mean(ydep > 0)), fill = TRUE)
r <- rbind(r, data.table(var = "corr(S0 z~, S3 z~)", N = length(ydep), mean = cor(d0$zt, d3$zt)), fill = TRUE)
fwrite(r, "step5/out/s5_table3_new.csv"); print(r[, lapply(.SD, function(z) if (is.numeric(z)) round(z, 3) else z)])
