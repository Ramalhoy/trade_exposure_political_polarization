# =============================================================================
# step7_figures.R — figures for the v4 text, in the style of the author's scripts
# (data/figuras/brazil_polarization_map_2x2.R, data/exports graph.R).
# Boundaries: IBGE municipal polygons (tbrugz/geodata-br, geojs-100-mun.json)
# dissolved to 2010 microregions with municipios_ibge.rds, since geobr's servers are
# not reachable from this workspace.
# Outputs (figures/): brazil_polarization_map_2x2.pdf (deputy), exports.pdf,
# ri_distribution_studentized.pdf, spec_curve.pdf, exposure_map.pdf
# =============================================================================
suppressMessages({ library(data.table); library(ggplot2); library(sf); library(scales); library(patchwork) })
sf_use_s2(FALSE); dir.create("figures", showWarnings = FALSE)
GEO <- Sys.getenv("GEO_MUN", "/tmp/claude-0/geo/br_mun.json")
# ---- microregion polygons ----------------------------------------------------
mun <- as.data.table(readRDS("D/municipios_ibge.rds"))
g <- st_read(GEO, quiet = TRUE); g$code <- as.integer(g$id)
g$micro <- as.integer(mun$microregion_code[match(g$code, as.integer(mun$municipality_code_ibge))])
cat("municipal polygons:", nrow(g), " unmatched to a microregion:", sum(is.na(g$micro)), "\n")
g <- st_make_valid(g[!is.na(g$micro), ])
micro <- aggregate(g["micro"], by = list(code_micro = g$micro), FUN = function(x) x[1])
micro <- st_simplify(st_make_valid(micro), dTolerance = 0.01)
cat("microregion polygons:", nrow(micro), "\n")
qcols <- c("Q1 (lowest)" = "#f0f0f0", "Q2" = "#bdbdbd", "Q3" = "#878787", "Q4" = "#525252", "Q5 (highest)" = "#0d0d0d")
quint_map <- function(dat, years, lab, title, fill_name) {
  dat <- copy(dat)[year %in% years]
  dat[, q := factor(names(qcols)[ceiling(5 * frank(metric, ties.method = "first") / .N)], levels = names(qcols)), by = year]
  m <- merge(micro[rep(seq_len(nrow(micro)), length(years)), ], data.frame(code_micro = rep(micro$code_micro, length(years)),
             year = rep(years, each = nrow(micro))), by = "code_micro", all.x = FALSE)
  m <- m[!duplicated(paste(m$code_micro, m$year)), ]
  m <- merge(m, dat[, .(code_micro, year, q)], by = c("code_micro", "year"), all.x = TRUE)
  m$year_label <- factor(paste(lab, m$year), levels = paste(lab, years))
  ggplot(m) + geom_sf(aes(fill = q), color = "white", linewidth = 0.04) + facet_wrap(~year_label, ncol = 2) +
    scale_fill_manual(values = qcols, na.value = "grey85", name = fill_name, drop = FALSE,
      guide = guide_legend(title.position = "top", title.hjust = 0.5, reverse = TRUE)) +
    labs(title = title, subtitle = "Quintiles computed within each year | Darkest shade (Q5) = highest") +
    theme_void(base_family = "sans") +
    theme(plot.title = element_text(size = 15, face = "bold", hjust = 0.5), plot.subtitle = element_text(size = 10, color = "grey40", hjust = 0.5),
          strip.text = element_text(size = 11, face = "bold"), legend.position = "right", panel.spacing = unit(0.4, "cm"),
          plot.background = element_rect(fill = "white", color = NA)) }
# ---- Fig. 3: deputy Dalton, levels by year -------------------------------------
dep <- as.data.table(readRDS("D/dalton_panel_deputado_federal.rds"))[, .(code_micro = as.integer(microregion_code), year, metric = P_dalton)]
p3 <- quint_map(dep, c(2010, 2014, 2018, 2022), "Election", "Dalton index of the federal-deputy vote, by microregion", "Polarization\nquintile")
ggsave("figures/brazil_polarization_map_2x2.pdf", p3, width = 11, height = 9, device = grDevices::pdf, useDingbats = FALSE)
# descriptive numbers used in the text (share of each macro-region in the top quintile, mean quintile)
dep[, uf := code_micro %/% 1000][, reg := fcase(uf < 20, "North", uf < 30, "Northeast", uf < 40, "Southeast", uf < 50, "South", default = "Centre-West")]
dep[, qn := ceiling(5 * frank(metric, ties.method = "first") / .N), by = year]
fwrite(merge(dcast(dep[, .(v = round(mean(qn == 5), 2)), by = .(reg, year)], reg ~ year, value.var = "v"),
             dcast(dep[, .(v = round(mean(qn), 2)), by = .(reg, year)], reg ~ year, value.var = "v"), by = "reg", suffixes = c("_shareQ5", "_meanQ")),
       "audit/out/step7_deputy_map_quintiles.csv")
# ---- App. C: exposure map (ΔEPW, v7) ---------------------------------------------
df <- as.data.table(readRDS("D/df_estimation_v7.rds"))[, .(code_micro = as.integer(microregion_code), year, metric = delta_EPW)]
pC <- quint_map(df, c(2014, 2018, 2022), "Change 2010 to", "Industry-export exposure (raw change in EPW), by microregion", "EPW change\nquintile")
ggsave("figures/exposure_map.pdf", pC, width = 11, height = 9, device = grDevices::pdf, useDingbats = FALSE)
# ---- Fig. 4: exports ---------------------------------------------------------------
ex <- fread("step5/out/s5_exports_series.csv")
p4 <- ggplot(ex, aes(ano, real_bn, color = "Total exports")) + geom_line(linewidth = 0.8) + geom_point(size = 1.4) +
  scale_color_manual(values = c("Total exports" = "#c0392b"), guide = guide_legend(override.aes = list(shape = NA, linewidth = 1))) +
  scale_x_continuous(breaks = 2010:2022) + scale_y_continuous(limits = c(150, 260)) +
  labs(x = "Year", y = "Value (USD billions, constant 2010 prices)", color = NULL) + theme_classic(base_size = 13) +
  theme(legend.position = "bottom", panel.grid = element_blank())
ggsave("figures/exports.pdf", p4, width = 8, height = 5, device = grDevices::pdf)
# ---- Fig. 5: studentized RI distributions ------------------------------------------
dr <- fread("audit/out/step7_ri_draws.csv")
dr[, lab := fifelse(design == "S0", "S0: industry exports", "S3: destination demand")]
obs <- dr[, .(t_obs = t_obs[1], p = (1 + sum(abs(tstar) >= abs(t_obs[1]))) / (.N + 1)), by = lab]
p5 <- ggplot(dr[abs(tstar) < 8], aes(tstar)) + geom_histogram(bins = 80, fill = "grey60", color = "white", linewidth = 0.1) +
  geom_vline(data = obs, aes(xintercept = t_obs), linewidth = 0.7) + facet_wrap(~lab, ncol = 2) +
  geom_text(data = obs, aes(x = t_obs, y = Inf, label = sprintf("observed t = %.2f\np = %.3f", t_obs, p)), vjust = 1.4, hjust = -0.05, size = 3.5) +
  labs(x = expression(t^"*" == hat(beta)^"*" / se[AKM]), y = "Permutation draws") + theme_classic(base_size = 12) +
  theme(strip.text = element_text(face = "bold"), strip.background = element_blank())
ggsave("figures/ri_distribution_studentized.pdf", p5, width = 9, height = 4, device = grDevices::pdf)
# ---- Specification curve -------------------------------------------------------------
sc <- fread("audit/out/step4_speccurve.csv")
sc[, design := fifelse(design == "S0", "S0: industry exports", "S3: destination demand")]
sc[, rk := frank(beta, ties.method = "first"), by = design]
sc[, sig := factor(fifelse(p < 0.05, "p < 0.05", fifelse(p < 0.10, "p < 0.10", "p >= 0.10")), levels = c("p < 0.05", "p < 0.10", "p >= 0.10"))]
ps <- ggplot(sc, aes(rk, beta)) + geom_hline(yintercept = 0, linewidth = 0.3) +
  geom_hline(yintercept = c(-0.162, 0.162), linetype = "dashed", linewidth = 0.3, color = "grey40") +
  geom_point(aes(shape = sig, color = headline), size = 1.3) + facet_wrap(~design, ncol = 2) +
  scale_color_manual(values = c(`FALSE` = "grey55", `TRUE` = "black"), labels = c("Other specifications", "Main specification"), name = NULL) +
  scale_shape_manual(values = c(17, 15, 16), name = NULL, drop = FALSE) +
  labs(x = "Specifications ranked by estimate", y = expression(hat(beta)~"(SD per SD)")) + theme_classic(base_size = 12) +
  theme(strip.text = element_text(face = "bold"), strip.background = element_blank(), legend.position = "bottom")
ggsave("figures/spec_curve.pdf", ps, width = 9, height = 4.6, device = grDevices::pdf)
cat("figures written:", paste(list.files("figures"), collapse = ", "), "\n")
