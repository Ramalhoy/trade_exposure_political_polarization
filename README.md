# trade_exposure_political_polarization
Code repository for my MSc dissertation 


# Trade Exposure and Political Polarization: Evidence from the Brazilian Case

**MSc Dissertation** | Federal University of Espírito Santo (UFES) | Graduate Program in Economics  
**Author:** Yago Ramalho Silva | **Advisor:** Prof. Dr. Henrique Augusto Campos Fernandez Hott | **Year:** 2026

---

## Overview

This project investigates whether and how exposure to trade shocks shapes political polarization at the local level in Brazil. The central question is: do changes in export performance (varying across regions depending on their industrial composition) influence voters' preferences for ideologically extreme candidates?

The study covers four presidential elections (2010, 2014, 2018, and 2022), a period that captures both the tail of the commodity super-cycle and Brazil's subsequent economic and political turbulence, including the rise of *antipetismo* sentiment and the consolidation of a far-right electoral coalition.

## Research Design

The empirical strategy combines three main components:

- **Polarization measurement:** A microregion-level political polarization index is constructed using the vote-share-weighted standard deviation of party ideological positions (Dalton index), where party scores are drawn from the Brazilian Legislative Survey (BLS). Supplementary measures are reported for robustness.

- **Trade exposure (shift-share):** Local exposure to export shocks is measured through a Bartik-style shift-share variable (*Exposure per Worker*, EPW), which interacts pre-determined sectoral employment shares (2010 baseline) with national-level changes in Brazilian exports by industry. This captures the heterogeneous impact of global trade dynamics on local labor markets.

- **Instrumentation (IV/2SLS):** To address residual endogeneity, particularly the confound between the 2014–2016 economic contraction and simultaneous political crisis, EPW is instrumented using export growth from structurally similar *peer countries* in each sector. A complementary commodity-price instrument is used as a robustness check. Two-Stage Least Squares (2SLS) is the main estimator.

## Hypotheses

The main hypothesis is that trade exposure amplifies local political polarization, with negative export shocks driving voters toward populist candidates. Three auxiliary hypotheses examine: (1) asymmetric effects, with negative shocks having larger effects than positive ones; (2) a predominantly right-wing mechanism, consistent with the rise of conservative mobilization in Brazil; and (3) heterogeneity across commodity-exporting versus manufacturing-oriented regions.

## Data Sources

| Component | Source |
|---|---|
| Electoral outcomes | TSE (Tribunal Superior Eleitoral) |
| Party ideology scores | Brazilian Legislative Survey (BLS/ZUCCO) |
| Local employment structure | RAIS (formal labor market registry) |
| Export flows | MDIC/ComexStat |
| Commodity prices (robustness) | World Bank Pink Sheet / IMF |

## Methods

`Shift-share design` · `Instrumental Variables (2SLS)` · `Panel data with state-year fixed effects` · `Shock-level balance tests` · `Asymmetric shock decomposition`
