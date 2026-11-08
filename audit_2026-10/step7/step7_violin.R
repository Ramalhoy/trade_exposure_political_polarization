# =============================================================================
# step7_violin.R — Figure 2 (BLS party positions by wave), corrected version of
# data/figuras/ideology_strip_violin.R (same palette, theme and layout).
# Fixes: (1) parties only — president entries (COLLOR, FHC, ITAMAR, LULA, DILMA,
# SARNEY, TEMER, BOLSONARO) are dropped, since the polarization indices use party
# scores; (2) no text labels (they were placed at each name's first wave, offset
# from the jittered points); (3) the ±1 SE bars now share the points' jitter
# (before, bars were drawn at the unjittered x and floated beside their points).
# =============================================================================
suppressMessages({ library(tidyverse) })
PRES <- c("BOLSONARO", "COLLOR", "DILMA", "FHC", "ITAMAR", "LULA", "SARNEY", "TEMER")
df <- readRDS("D/bls9_estimates_partiespresidents_long.rds") |>
  mutate(name = as.character(party.or.pres), year = as.integer(as.character(year))) |>
  filter(!name %in% PRES) |>
  mutate(camp = factor(case_when(ideo < -0.25 ~ "Left", ideo > 0.25 ~ "Right", TRUE ~ "Center"), levels = c("Left", "Center", "Right")))
waves <- sort(unique(df$year))
set.seed(42)
df <- df |> mutate(xpos = match(year, waves), xj = xpos + runif(n(), -0.15, 0.15))
camp_colors <- c(Left = "#C0392B", Center = "#7D8A8A", Right = "#2471A3")
base_theme <- theme_classic(base_size = 12) +
  theme(plot.background = element_rect(fill = "#FAFAFA", color = NA), panel.background = element_rect(fill = "#FAFAFA", color = NA),
        panel.grid.major.y = element_line(color = "#EAECEE", linewidth = 0.3), panel.grid.major.x = element_blank(),
        panel.grid.minor = element_blank(), axis.line = element_line(color = "grey40", linewidth = 0.5),
        axis.ticks = element_line(color = "grey40"), axis.text = element_text(size = 10, color = "grey20"),
        legend.position = "top", legend.text = element_text(size = 10), legend.title = element_text(size = 9),
        legend.key.size = unit(0.8, "lines"))
p <- ggplot(df) +
  annotate("rect", xmin = -Inf, xmax = Inf, ymin = -0.25, ymax = 0.25, fill = "#BDC3C7", alpha = 0.18) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "#AAB7B8", linewidth = 0.8) +
  geom_violin(aes(x = xpos, y = ideo, group = xpos), fill = "#D5D8DC", color = NA, alpha = 0.35, width = 0.7) +
  geom_linerange(aes(x = xj, ymin = ideo - ideo.se, ymax = ideo + ideo.se, color = camp), alpha = 0.4, linewidth = 0.5, show.legend = FALSE) +
  geom_point(aes(x = xj, y = ideo, color = camp, fill = camp), size = 2.5, shape = 21, stroke = 0.4, alpha = 0.82) +
  scale_color_manual(values = camp_colors, name = "Ideological camp") +
  scale_fill_manual(values = camp_colors, guide = "none") +
  scale_y_continuous(limits = c(-1.25, 1.25)) +
  scale_x_continuous(breaks = seq_along(waves), labels = waves, expand = expansion(add = 0.6)) +
  labs(x = "BLS wave", y = "Ideology score (scaled)") + base_theme
ggsave("figures/ideology_strip_violin.pdf", p, width = 12, height = 6, bg = "#FAFAFA", device = grDevices::pdf)
# numbers used in the text (parties only)
st <- df |> group_by(year) |> summarise(n = n(), mean = round(mean(ideo), 3), n_gt_06 = sum(ideo > 0.6), max = round(max(ideo), 3))
write_csv(st, "audit/out/step7_violin_wave_stats.csv"); print(st)
