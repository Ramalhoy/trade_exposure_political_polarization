library(data.table)
D <- Sys.getenv("SS_DATA_DIR", "D"); PD <- file.path(D, "output", "packet_D")
cr <- readRDS("audit/out/cleanroom_s3.rds")
d1 <- readRDS(file.path(PD, "D1_s_rd.rds")); s <- as.data.table(d1$s_rd)
gd <- as.data.table(readRDS(file.path(PD, "D3_g_dt.rds")))
E0 <- as.data.table(readRDS(file.path(PD, "E0_frame.rds"))$frame)
# shares
m <- merge(cr$X[, .(micro = as.integer(micro), d, s_cr = s)], s[, .(micro = as.integer(micro), d = as.integer(destino), s_p = s_rd_n2)],
           by = c("micro", "d"), all = TRUE)
cat(sprintf("shares: cells CR %d | pipeline %d | in both %d | max rel diff (both) %.3e | value only-CR %.4f%% | only-pipeline %.4f%%\n",
  sum(!is.na(m$s_cr)), sum(!is.na(m$s_p)), sum(!is.na(m$s_cr) & !is.na(m$s_p)),
  max(abs(m$s_cr / m$s_p - 1), na.rm = TRUE), 100 * sum(m$s_cr[is.na(m$s_p)]) / sum(m$s_cr, na.rm = TRUE),
  100 * sum(m$s_p[is.na(m$s_cr)]) / sum(m$s_p, na.rm = TRUE)))
# shocks
g <- merge(cr$G[, .(d, ano = t, g_cr = g)], gd[, .(d = as.integer(destino), ano, g_p = g_dt)], by = c("d", "ano"))
g <- g[d %in% cr$keep]
cat(sprintf("shocks: %d dest-years | max|diff| %.3e | corr %.8f\n", nrow(g), max(abs(g$g_cr - g$g_p)), cor(g$g_cr, g$g_p)))
print(head(g[order(-abs(g_cr - g_p))], 5))
# treatment
z <- merge(cr$z[, .(micro = as.character(micro), year, z_cr)], E0[, .(micro = as.character(micro), year, z_p = epw_S3_N2ex)],
           by = c("micro", "year"), all.y = TRUE); z[is.na(z_cr), z_cr := 0]
cat(sprintf("treatment: %d rows | max|diff| %.3e | max rel %.3e | corr %.10f\n", nrow(z), max(abs(z$z_cr - z$z_p)),
            max(abs(z$z_cr - z$z_p)) / sd(z$z_p), cor(z$z_cr, z$z_p)))
