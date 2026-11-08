# =============================================================================
# Brazil Polarization Map — Microregional Level | Election Years 2010–2022
# 2x2 grid: one map per election year, quintiles computed within each year
# =============================================================================

## [REV-H1 2026-07-30] The hard-coded Windows path is kept for provenance but
## commented out: it aborts the script on this machine. The canonical data
## directory now comes from 00_config.R (which also setwd()s to it).
# setwd("C:/Users/Yago Ramalho/Documents/tema mestrado/data")
source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
FIG_OUT <- "/Users/solenoide/Documents/dissertação/data/figuras"

# --- 1. Install & load packages ----------------------------------------------

# Run once if not yet installed:
# install.packages(c("geobr", "ggplot2", "dplyr", "sf", "patchwork", "scales"))

library(geobr)     # Official Brazil shapefiles (IBGE)
library(ggplot2)   # Plotting
library(dplyr)     # Data wrangling
library(sf)        # Spatial data handling
library(scales)    # Label formatting helpers


# --- 2. Load Brazil microregion shapefile ------------------------------------
# We use a single boundary year for consistency across all election maps.
# 2010 is ideal if your data aligns with the census; 2020 also works.

micro_shapes <- read_micro_region(year = 2010, showProgress = FALSE) %>%
  mutate(code_micro = as.integer(code_micro))

# Preview: glimpse(micro_shapes)


# --- 3. Your data ------------------------------------------------------------
# ADAPT THIS SECTION to point to your actual dataframe.
#
# Requirements:
#   - One row per microregion × year combination
#   - A column with the IBGE microregion code (5-digit integer, e.g. 11001)
#   - A column with the election year (2010, 2014, 2018, 2022)
#   - A column with your polarization metric (numeric)
#
# Example structure:
#   code_micro  |  year  |  polarization
#   11001       |  2010  |  0.72
#   11001       |  2014  |  0.68
#   ...

# ---- REPLACE the line below with your real dataframe -----------------------

## [REV-H1] The referenced file does not exist in the repo (only the .xlsx
## export does, and it is a superseded vintage). Point at the canonical stage-02
## output in DATA_DIR instead. Original line kept, commented:
# my_data <- readRDS("indices_polarizacao_completos.rds")
 my_data <- readRDS("dalton_panel_presidencial.rds") |>
   dplyr::rename(microregion_code = microregion_code)

# Column name aliases — change these to match YOUR column names:
ID_COL     <- "microregion_code"    # IBGE microregion code column
YEAR_COL   <- "year"          # Election year column
METRIC_COL <- "P_dalton"  # Your polarization metric column

# Election years to map:
ELECTION_YEARS <- c(2010, 2014, 2018, 2022)


# --- 4. Prepare & compute within-year quintiles ------------------------------
# Quintiles are computed WITHIN each year so that each map shows the relative
# distribution for that election cycle independently.
# → Change ntile() grouping below if you prefer global quintiles across years.

map_data <- my_data %>%
  rename(
    code_micro = all_of(ID_COL),
    year       = all_of(YEAR_COL),
    metric     = all_of(METRIC_COL)
  ) %>%
  filter(year %in% ELECTION_YEARS) %>%
  group_by(year) %>%
  mutate(
    quintile = ntile(metric, 5),
    quintile_label = factor(
      quintile,
      levels = 1:5,
      labels = c("Q1 (lowest)", "Q2", "Q3", "Q4", "Q5 (highest)")
    )
  ) %>%
  ungroup() %>%
  mutate(
    code_micro = as.integer(code_micro),
    year_label = factor(paste0("Election ", year), # panel title
                        levels = paste0("Election ", ELECTION_YEARS))
  )


# --- 5. Join shapefile with all years ----------------------------------------
# Expand the shapefile to cover all election years, then join data.

micro_map <- micro_shapes %>%
  # Cross-join: one copy of the shapefile per election year
  cross_join(data.frame(year = ELECTION_YEARS)) %>%
  mutate(year_label = factor(paste0("Election ", year),
                             levels = paste0("Election ", ELECTION_YEARS))) %>%
  left_join(
    map_data %>% select(code_micro, year, metric, quintile_label),
    by = c("code_micro", "year")
  )

# Warn about unmatched microregions
n_missing <- sum(is.na(micro_map$quintile_label))
if (n_missing > 0) {
  warning(sprintf(
    "%d microregion × year combination(s) had no match and will appear grey.",
    n_missing
  ))
}


# --- 6. Color palette --------------------------------------------------------
# Sequential palette: light blue → teal → yellow → bold red for Q5

quintile_colors <- c(
  "Q1 (lowest)" = "#f0f0f0",  # near white
  "Q2"          = "#bdbdbd",  # light gray
  "Q3"          = "#878787",  # medium gray
  "Q4"          = "#525252",  # dark gray
  "Q5 (highest)"    = "#0d0d0d"   # near black
)

# --- 7. Build the 2x2 faceted map --------------------------------------------

p <- ggplot(micro_map) +
  geom_sf(
    aes(fill = quintile_label),
    color     = "white",
    linewidth = 0.04
  ) +
  facet_wrap(
    ~ year_label,
    ncol = 2
  ) +
  scale_fill_manual(
    values   = quintile_colors,
    na.value = "grey85",
    name     = "Polarization\nQuintile",
    drop     = FALSE,
    guide    = guide_legend(
      title.position = "top",
      title.hjust    = 0.5,
      keywidth       = unit(0.7, "cm"),
      keyheight      = unit(0.45, "cm"),
      reverse        = TRUE   # Q5 at top of legend
    )
  ) +
  labs(
    ## [REV-H1] Both strings below were production placeholders. DECISION: keep
    ## the greyscale palette (the paper prints in B&W and its note already reads
    ## "grey shades denote microregional quintiles") and fix the subtitle to
    ## match it; fix the source line to the actual sources.
    ## Originals, kept for provenance:
    ##   subtitle = "Quintiles computed within each election year | Red (Q5) = top intensity"
    ##   caption  = "Source: your data | Shapefile: IBGE via {geobr}"
    title    = "Polarization Index by Microregion - Brazil",
    subtitle = "Quintiles computed within each election year | Darkest shade (Q5) = most polarized",
    caption  = paste("Source: author, from TSE first-round returns and Brazilian",
                     "Legislative Survey ideology scores (Zucco & Power).",
                     "Shapefile: IBGE 2010 microregions via {geobr}.")
  ) +
  theme_void(base_family = "sans") +
  theme(
    # Overall titles
    plot.title      = element_text(size = 17, face = "bold",    hjust = 0.5,
                                   margin = margin(b = 4)),
    plot.subtitle   = element_text(size = 11, color = "grey40",  hjust = 0.5,
                                   margin = margin(b = 10)),
    plot.caption    = element_text(size = 8,  color = "grey55",  hjust = 1),

    # Facet strip labels (year titles above each panel)
    strip.text      = element_text(size = 12, face = "bold",
                                   margin = margin(b = 4)),

    # Legend
    legend.position = "right",
    legend.title    = element_text(size = 10, face = "bold"),
    legend.text     = element_text(size = 9),

    # Spacing between panels
    panel.spacing   = unit(0.5, "cm"),

    # Background & margins
    plot.background = element_rect(fill = "white", color = NA),
    plot.margin     = margin(12, 12, 12, 12)
  )

print(p)


# --- 8. Save the map ---------------------------------------------------------

## [REV-H1] write to the figuras/ folder explicitly (the working directory is
## now DATA_DIR, not the repo root) and also drop a copy in the revision output.
## [REV-H1] cairo/X11 are not present on this machine, so `cairo_pdf` and the
## ragg png device both fail silently-ish (they warn and write nothing). Use the
## base grDevices pdf device and the quartz png device instead; output is
## identical for a vector map with no transparency.
ggsave(
  filename = file.path(FIG_OUT, "brazil_polarization_map_2x2.png"),
  plot     = p,
  width    = 12,
  height   = 11,
  dpi      = 300,
  bg       = "white",
  device   = grDevices::png, type = "quartz"
)

save_pdf <- function(path) ggsave(path, plot = p, width = 11, height = 8,
                                  device = grDevices::pdf, useDingbats = FALSE)
save_pdf(file.path(FIG_OUT, "brazil_polarization_map_2x2.pdf"))

dir.create(file.path("output", "revision", "H1"), showWarnings = FALSE, recursive = TRUE)
save_pdf(file.path("output", "revision", "H1", "brazil_polarization_map_2x2.pdf"))
cat("[REV-H1] map rebuilt: placeholder subtitle and source line replaced.\n")



