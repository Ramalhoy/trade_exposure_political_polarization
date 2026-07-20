# =============================================================================
# 00b_micro_centroids.R
# Build micro_centroids.rds: microregion centroids for Conley spatial SEs.
#
# SOURCE: IBGE 2010 microregion shapefile
#   https://geoftp.ibge.gov.br/organizacao_do_territorio/malhas_territoriais/
#   malhas_municipais/municipio_2010/Brasil/BR/
#   File: br_microrregioes_2010.zip (or equivalent)
#   Alternative: geobr package pulls it directly (no manual download needed).
# =============================================================================

source("C:/Users/Yago Ramalho/Documents/tema mestrado/data/códigos/_config.R")

library(tidyverse)
library(sf)

# -----------------------------------------------------------------------------
# OPTION A — geobr (recommended: no manual download, correct 2010 vintage)
# -----------------------------------------------------------------------------
# install.packages("geobr")
library(geobr)

micro_sf <- read_micro_region(year = 2010, showProgress = FALSE)

centroids <- micro_sf |>
  st_centroid() |>
  mutate(
    lon = st_coordinates(geom)[, 1],
    lat = st_coordinates(geom)[, 2],
    micro = as.character(code_micro)   # 5-digit IBGE microregion code
  ) |>
  st_drop_geometry() |>
  select(micro, lon, lat)

# Municipalities of Litoral Sul RN, dissolved to a microregion centroid
muni_rn <- geobr::read_municipality(code_muni = "RN", year = 2010, showProgress = FALSE)
# Litoral Sul RN municipalities (verify this list against IBGE):
litoral_sul_munis <- muni_rn |>
  filter(name_micro == "Litoral Sul" | code_micro == 24019)   # adjust to what geobr exposes

ls_centroid <- litoral_sul_munis |>
  sf::st_union() |> sf::st_centroid() |> sf::st_coordinates()

centroids <- bind_rows(centroids,
                       tibble(micro = "24019", lon = ls_centroid[,1], lat = ls_centroid[,2]))

saveRDS(centroids, "micro_centroids.rds")   # writes to canonical DATA_DIR
cat("Centroids saved:", nrow(centroids), "microregions\n")
print(head(centroids))



# Does a later vintage have 24019? (boundaries are stable, so its centroid ≈ 2010)
for (yr in c(2015, 2017, 2018, 2019, 2020)) {
  m <- geobr::read_micro_region(year = yr, showProgress = FALSE) |> sf::st_drop_geometry()
  cat(yr, ": 24019 present =", 24019 %in% m$code_micro, "\n")
}


m_alt <- geobr::read_micro_region(year = 2017, showProgress = FALSE)   # whichever year has it
ls <- m_alt |> dplyr::filter(code_micro == 24019)

ls_xy <- ls |> sf::st_centroid() |> sf::st_coordinates()
centroids <- dplyr::bind_rows(
  centroids,
  tibble::tibble(micro = "24019", lon = ls_xy[, 1], lat = ls_xy[, 2])
)
stopifnot(nrow(centroids) == 558, !anyNA(centroids$lat))
saveRDS(centroids, "micro_centroids.rds")
