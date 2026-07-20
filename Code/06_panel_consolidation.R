# =============================================================================
# 06_panel_consolidation.R  (pipeline stage 3 — panel consolidation)
# Joins the EPW treatment (v7) + polarization indices + controls into the
# stacked first-difference estimation frame. Formerly "DF panel final.R".
# =============================================================================
source("C:/Users/Yago Ramalho/Documents/tema mestrado/data/códigos/_config.R")

library(tidyverse)

# =============================================================================
# STEP 1 — LOAD DATA
# =============================================================================

epw_panel <- readRDS("epw_panel_isic_v7.rds")
# [FIX] read the current presidential Dalton panel produced by
# 02_polarization_indices.R (was reading the deprecated un-suffixed
# "dalton_panel.rds" left over from the old April ideology script).
dalton     <- readRDS("dalton_panel_presidencial.rds")
controls   <- readRDS("controls_micro.rds")

cat("EPW panel:   ", nrow(epw_panel),  "rows |", n_distinct(epw_panel$micro),  "micros\n")
cat("Dalton panel:", nrow(dalton),     "rows |", n_distinct(dalton$microregion_code), "micros\n")
cat("Controls:    ", nrow(controls),   "rows |", n_distinct(controls$micro),   "micros\n\n")


# =============================================================================
# STEP 2 — STANDARDISE KEY TYPES AND NAMES
#
# All three files may have microregion code stored as different types
# (integer from Sidra, character from IBGE API, numeric from RAIS).
# Force to character everywhere before any join.
# =============================================================================

epw_panel <- epw_panel |>
  mutate(microregion_code = as.character(micro)) |>
  select(-micro)

dalton <- dalton |>
  mutate(microregion_code = as.character(microregion_code))

controls <- controls |>
  mutate(microregion_code = as.character(micro)) |>
  select(-micro)


# =============================================================================
# STEP 3 — JOIN EPW AND POLARIZATION INTO LEVELS PANEL
# =============================================================================

panel_levels <- dalton |>
  left_join(
    epw_panel |> select(microregion_code, year, EPW,
                        any_of(c("state", "mesoregion_code", "mesoregion_name"))),
    by = c("microregion_code", "year")
  )

cat("Levels panel:", nrow(panel_levels), "rows\n")
cat("Years present:", paste(sort(unique(panel_levels$year)), collapse = ", "), "\n\n")


# =============================================================================
# STEP 4 — EXTRACT 2010 BASELINE POLARIZATION
# =============================================================================

baseline_pol <- panel_levels |>
  filter(year == 2010) |>
  select(microregion_code,
         P_dalton_2010 = P_dalton,
         P_center_2010 = P_center)

cat("Baseline polarization rows:", nrow(baseline_pol), "(target: 558)\n\n")


# =============================================================================
# STEP 5 — COMPUTE FIRST DIFFERENCES (stacked 2010→2014, 2010→2018, 2010→2022)
# =============================================================================

df_raw <- panel_levels |>
  filter(year %in% c(2014, 2018, 2022)) |>
  left_join(baseline_pol, by = "microregion_code") |>
  mutate(
    delta_P_dalton = P_dalton - P_dalton_2010,
    delta_P_center = P_center - P_center_2010,
    delta_EPW      = EPW        # already a cumulative change from 2010 by construction
  )

cat("First-differences panel:", nrow(df_raw), "rows (target: 1,674 = 558 × 3)\n\n")

saveRDS(df_raw, "df_raw_v7.rds")    
# =============================================================================
# STEP 6 — JOIN TIME-INVARIANT CONTROLS
#
# Controls are 2010 cross-section values — one row per microregion.
# They enter as levels (not differences) because they serve as baseline
# characteristics that may confound the EPW→polarization relationship.
# =============================================================================

df <- df_raw |>
  left_join(
    controls |> select(microregion_code,
                       ln_pop, urban_share, educ_share,
                       ln_gdp_pc, manuf_share),
    by = "microregion_code"
  ) |>
  select(
    # Identifiers
    microregion_code,
    any_of(c("state", "mesoregion_code", "mesoregion_name")),
    year,
    P_dalton, P_center,                 
    # Outcome variables
    delta_P_dalton, delta_P_center,
    # Treatment
    delta_EPW,
    # Baseline polarization (pre-trend controls)
    P_dalton_2010, P_center_2010,
    # Cross-sectional controls (2010 baseline)
    ln_pop, urban_share, educ_share, ln_gdp_pc, manuf_share
  ) |>
  arrange(microregion_code, year)


# =============================================================================
# STEP 7 — QUALITY CHECKS
# =============================================================================

cat("=== Final estimation dataframe ===\n")
cat("Rows:          ", nrow(df), "\n")
cat("Microregions:  ", n_distinct(df$microregion_code), "\n")
cat("Years:         ", paste(sort(unique(df$year)), collapse = ", "), "\n\n")

cat("--- Missing values per variable ---\n")
missing_summary <- df |>
  summarise(across(everything(), ~ sum(is.na(.)))) |>
  pivot_longer(everything(), names_to = "variable", values_to = "n_missing") |>
  filter(n_missing > 0)

if (nrow(missing_summary) == 0) cat("No missing values.\n") else print(missing_summary)

cat("\n--- Distribution of key variables ---\n")
df |>
  select(delta_P_dalton, delta_P_center, delta_EPW,
         ln_pop, urban_share, educ_share, ln_gdp_pc, manuf_share) |>
  summary() |>
  print()

cat("\n--- Observations per year ---\n")
df |> count(year) |> print()

cat("\n--- Controls coverage: microregions in df but missing controls ---\n")
n_missing_controls <- df |>
  filter(is.na(ln_pop) | is.na(ln_gdp_pc) | is.na(educ_share)) |>
  distinct(microregion_code) |>
  nrow()
cat("Microregions with at least one missing control:", n_missing_controls,
    "(target: 0)\n")


# =============================================================================
# STEP 8 — SAVE
# =============================================================================

saveRDS(df, "df_estimation_v7.rds")                  
write_csv(df, "df_estimation_v7.csv")               
