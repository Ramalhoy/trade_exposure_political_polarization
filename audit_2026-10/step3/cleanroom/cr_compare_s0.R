# compares the clean-room S0 objects with the audited pipeline's stored objects
D <- Sys.getenv("SS_DATA_DIR", "D")
cr <- readRDS("audit/out/cleanroom_s0.rds")
gk <- as.data.frame(readRDS(file.path(D, "sectoral_shocks_isic_v7.rds")))
ep <- as.data.frame(readRDS(file.path(D, "epw_panel_isic_v7.rds")))
pu <- sort(unique(gk$isic4))
cat("units: clean-room", length(cr$uni), "| pipeline", length(pu), "| only CR:", paste(setdiff(cr$uni, pu), collapse=","),
    "| only pipeline:", paste(setdiff(pu, cr$uni), collapse=","), "\n")
com <- intersect(cr$uni, pu)
Lp <- tapply(gk$L_j_2010, gk$isic4, `[`, 1)
cat(sprintf("L_j: max rel diff %.3e\n", max(abs(cr$Lj[com] / Lp[com] - 1))))
for (t in c(2014, 2018, 2022)) { gp <- setNames(gk$g_jt[gk$year == t], gk$isic4[gk$year == t])
  d <- cr$g[com, as.character(t)] - gp[com]
  cat(sprintf("g %d: max|diff| %.3e | units with |diff|>1e-8: %d %s\n", t, max(abs(d)), sum(abs(d) > 1e-8),
      paste(head(names(sort(-abs(d))[abs(sort(-abs(d))) > 1e-8]), 6), collapse = ","))) }
m <- merge(cr$z, transform(ep[ep$year != 2010, c("micro", "year", "EPW")], micro = as.character(micro)), by = c("micro", "year"))
cat(sprintf("z: %d rows matched | max|diff| %.3e | corr %.8f\n", nrow(m), max(abs(m$z_cr - m$EPW)), cor(m$z_cr, m$EPW)))
