# Packet D — Data Contracts

Exact schemas for every intermediate object. Every script asserts its inputs on read and its outputs on write. If a contract cannot be satisfied, **stop and report** — do not coerce, do not silently drop rows.

Companion to `packet_D_spec.md`. Conventions: `set.seed(2026)`, `B = 9999`, all monetary values in constant 2010 USD using the deflator already used by `00_epw_calculo_v7.R`.

---

## 0a. Rule for writing contracts — added 2026-08-10, binding on Phase 2

**Inspect first, then assert. Every claimed property gets a `stopifnot()`, never
an "expect".**

`[D-20]` was the third specification in this packet asserted from plausible
inference rather than inspection, after the two gates withdrawn as mis-specified
(`RATIONALE_D.md` `[D-30]` gate-design note). The pattern was identical each
time: a data property that *should* hold, written into a contract as though
verified, with the verification deferred to a log nobody was required to stop on.

Where a property cannot be checked before the contract is written, **the contract
says so explicitly** and the first thing the script does is check it.

All three affected items are now corrected, and none propagated into a reported
number — `[D-20]` was caught by an assertion at construction, and both gates were
caught before they blocked anything. That is luck plus attentive execution, not
process. The rule above is the process.

---

## 0. Objects read from the locked pipeline (read-only)

These are **inputs**, never rebuilt. Load from the v7 saved outputs.

### `shares_rj` — v7 employment shares
| column | type | constraint |
|---|---|---|
| `microrregiao` | integer | 6-digit IBGE code |
| `isic4` | character | 4-digit, post-composite-aggregation |
| `s_rj` | double | `>= 0`, finite |
| `L_r_2010` | double | `> 0` |

Assertions on load:
```r
stopifnot(
  all(shares_rj$s_rj >= 0),
  all(is.finite(shares_rj$s_rj)),
  n_distinct(shares_rj$isic4) == N_ISIC_EXPECTED,     # pin this constant
  n_distinct(shares_rj$microrregiao) == N_MICRO_EXPECTED
)
```

`N_MICRO_EXPECTED` **must be pinned to one value** and reconciled against the 556 / 558 discrepancy already flagged in the manuscript. Packet D does not inherit that ambiguity. Record the resolution as `[D-1]`.

### `crosswalk_ncm_isic` — v7 crosswalk object
Loaded, never rebuilt. Same vintage, same identified-composite aggregation, same producer-primacy rule, same restrict-then-renormalise fix. Branch B applies this object to BACI HS6 codes. Any divergence between its application to Comex and to BACI is a bug.

### `epw_v7` — baseline exposure, for the S0 rung of the ladder
| column | type |
|---|---|
| `microrregiao` | integer |
| `ano` | integer ∈ {2014, 2018, 2022} |
| `epw`, `epw_pos`, `epw_neg`, `theta_r` | double |

---

## 1. `baci_raw` — foreign trade panel

**Source, confirmed on disk 2026-08-10:** `DATA_DIR/baci/` (renamed from
`BACI_HS07_V202601/`), release **HS07 V202601**, CEPII. Files
`BACI_HS07_Y{2010,2014,2018,2022}_V202601.csv`. Do not chain vintages.

**Raw file schema, as shipped:**

| raw column | meaning | note |
|---|---|---|
| `t` | year | |
| `i` | exporter | numeric ISO 3166-1; **Brazil = 76** |
| `j` | importer | numeric ISO 3166-1 |
| `k` | HS6 product, HS2007 | **leading zeros stripped — pad to 6** |
| `v` | value | **thousand USD, CURRENT** |
| `q` | quantity | metric tons; supports the volume variant, §D.7.6 |

Metadata shipped alongside: `country_codes_V202601.csv`
(`country_code, country_name, country_iso2, country_iso3`) and
`product_codes_HS07_V202601.csv`.

**After ingest:**

| column | type | constraint |
|---|---|---|
| `ano` | integer | ∈ {2010, 2014, 2018, 2022} |
| `origem`, `destino` | integer | UN Comtrade **area** code, **not** ISO 3166-1 — join via alphabetic `iso3`, see §1b |
| `hs6` | character | 6 digits, **zero-padded**, HS2007 |
| `valor` | double | `> 0`, **deflated to constant 2010 USD via `cpi_us.rds`** |

Gates:
```r
stopifnot(
  all(nchar(baci_raw$hs6) == 6),                      # AFTER str_pad(width=6, pad="0")
  all(baci_raw$valor > 0),
  76L %in% baci_raw$origem,                           # Brazil present pre-filter
  setequal(unique(baci_raw$ano), c(2010, 2014, 2018, 2022))
)
```

The zero-padding assertion is the one that matters. BACI strips leading zeros, so
without padding every product in HS chapters 01–09 — live animals, meat, dairy,
vegetables, coffee — silently fails to match the crosswalk and drops out. The
failure is invisible: no error, just a smaller universe.

Deflation is not optional: `v` is current USD, and both endpoints of an arc growth
rate must be in the same constant currency (`packet_D_spec.md` §D.2). `03b`
already does this; new scripts must too.

Reconcile world totals per year against a published aggregate within **1%**.

## 1b. Country-code harmonisation — BACI keys on UN Comtrade area codes

**Corrected 2026-08-10 by `[D-20]`.** The previous text asserted that BACI's
`country_code` *is* the numeric ISO 3166-1 code and joins directly onto
`CO_PAIS_ISON3`. That is false, and it fails on the largest destinations:

| destination | ISO 3166-1 | BACI / Comtrade | 2010 share of Brazil's exports |
|---|---|---|---|
| United States | 840 | **842** | **9.63%** |
| France | 250 | **251** | 1.78% |
| India | 356 | **699** | 1.74% |
| Taiwan | 158 | **490** (Other Asia, nes) | 0.87% |
| Switzerland | 756 | **757** | 0.69% |
| Norway | 578 | **579** | 0.36% |

A numeric join silently drops **15.17% of 2010 export value across 19 areas**,
including Brazil's second-largest destination. The codes are Comtrade *areas*,
which aggregate territories into a metropole; they coincide with ISO 3166-1 for
most countries, which is what makes the error survive casual inspection.

**Required join.**

1. Join on the alphabetic `iso3` that BACI also ships. It is reliable.
2. Apply the explicit 14-entry aggregation map for territories Comtrade folds
   into a metropole: `PRI`, `VIR`, `UMI` → USA; `GLP`, `MTQ`, `GUF`, `REU`,
   `MCO` → France; `LIE` → Switzerland; `IMN`, `GGY` → UK; `FRO` → Denmark;
   `TWN` → Other Asia, nes.
3. **Fold Comex into BACI's scheme, never the reverse.** `m_dp_row` is built
   from BACI, so area 842 already contains Puerto Rico's imports and Comex's
   `PRI` must join onto it. Reversing the direction double-counts.
4. Assert every map target is present in BACI's own country list before use.

**Gate — this is an assertion, not an expectation.**

```r
stopifnot(
  "[D-20] unmatched destination codes carry value" =
    sum(unmatched$vl_fob) == 0,
  "[D-20] map target missing from BACI country list" =
    all(area_map$target %in% baci_countries$country_iso3)
)
```

The superseded text said to write `log_d_unmatched_codes.csv` and "expect it
near-empty, treating a long log as a bug rather than a data feature." That
framing was the actual defect: it invited a populated log to be explained rather
than stopped on. **The log must be empty and the script must assert it.**
Post-fix it is: 0 codes, 0.000000% of value.

**`[D-4]` item 4 carries the same error and is superseded by this section.**

## 2. `m_dp_row` — destination × product imports, Brazil excluded

```r
m_dp_row <- baci_raw |> filter(origem != "BRA") |>
  group_by(destino, hs6, ano) |> summarise(m = sum(valor), .groups = "drop")
```

| column | type | constraint |
|---|---|---|
| `destino`, `hs6` | character | |
| `ano` | integer | |
| `m` | double | `>= 0` |

Gate: `stopifnot(!any(m_dp_row$origem == "BRA"))` — Brazil must not appear anywhere downstream. This is the single most important assertion in the packet; a leak here silently destroys the exogeneity claim. Assert it again immediately before every use.

---

## 3. Branch B objects

### 3.1 `omega_jd` — Brazil's 2010 destination mix by industry
```
omega_jd  =  X_jd,2010^BR / Σ_d X_jd,2010^BR
```
| column | type | constraint |
|---|---|---|
| `isic4` | character | |
| `destino` | character | |
| `omega_jd` | double | `>= 0` |

Gate: `stopifnot(all(abs(rowsum(omega_jd, isic4) - 1) < 1e-8))` — sums to 1 within industry.

### 3.2 `z_jt` — Branch B shock
```
z_jt  =  Σ_d  omega_jd × arcΔ( m_dj_row[t] , m_dj_row[2010] )      [PRIMARY]
z_jt_level  =  z_jt × X_j_2010 / L_j_2010
```
| column | type | constraint |
|---|---|---|
| `isic4` | character | |
| `ano` | integer | ∈ {2014, 2018, 2022} |
| `z_jt` | double | ∈ [−2, 2] |
| `z_jt_level` | double | finite |

Gates:
```r
stopifnot(
  all(z_jt$z_jt >= -2 - 1e-9), all(z_jt$z_jt <= 2 + 1e-9),
  all(is.finite(z_jt$z_jt_level)),
  n_distinct(z_jt$isic4) == N_ISIC_EXPECTED           # same industry set as shares_rj
)
```
The industry set **must** match `shares_rj` exactly. An industry present in shares but absent from `z_jt` means the crosswalk applied differently to BACI than to Comex — stop and diagnose, do not left-join and fill with zero.

### 3.3 `g_jt_arc` — realised arc shock, for rung S1
```
g_jt_arc  =  arcΔ( X_jt^BR , X_j,2010^BR )      [PRIMARY; matches G3's g_arc]
```
Same schema, same bounds. Built from the **same Comex series the v7 pipeline uses**, not a fresh pull.

---

## 4. Branch A objects

### 4.1 `x_rd_2010` — microregion exports by destination

Source: Comex Stat *Municípios* (município × NCM × país × ano), aggregated via the IBGE município → microrregião correspondence for the **2010 territorial division** — pin the vintage, municipality boundaries changed over the period.

| column | type | constraint |
|---|---|---|
| `microrregiao` | integer | |
| `destino` | character | ISO3, harmonised to BACI codes |
| `x_rd` | double | `>= 0`, constant 2010 USD |

Gates:
```r
stopifnot(
  abs(sum(x_rd_2010$x_rd) - comex_national_total_2010) / comex_national_total_2010 < 1e-6,
  all(x_rd_2010$destino %in% baci_destinos),           # country-code harmonisation
  all(x_rd_2010$x_rd >= 0)
)
```
Country-code harmonisation between Comex (numeric país codes) and BACI (ISO3) must be **explicit and audited**, with an unmatched-code report written to disk. Log as `[D-3]`. Silent non-matches here quietly shrink exposure for the affected regions.

### 4.2 `s_rd` — exposure shares, both normalisations
| column | type | constraint |
|---|---|---|
| `microrregiao` | integer | |
| `destino` | character | |
| `s_rd_n2` | double | `= x_rd / L_r_2010`, `>= 0` |
| `s_rd_n1` | double | `= x_rd / Σ_d x_rd`, `>= 0` |

Gates:
```r
stopifnot(
  all(abs(rowsum(s_rd$s_rd_n1, s_rd$microrregiao) - 1) < 1e-8 |
      rowsum(s_rd$x_rd, s_rd$microrregiao) == 0),      # zero-export regions exempt
  all(s_rd$s_rd_n2 >= 0)
)
```
**Zero-export microregions:** retain at `s_rd_n2 = 0`, `theta_r = 0`; `s_rd_n1` undefined and the region is excluded from N1 only. Record the count and reconcile N across N1, N2 and the industry design in every table note. Log as `[D-4]`.

### 4.3 `s_rd_bridge` — employment-imputed shares (diagnostic only)
```
s_rd_bridge  =  Σ_j  s_rj × omega_jd
```
Not used in any reported specification. Its only output is the correlation with `s_rd_n1`, written to `tab_d_bridge.md`. **Gate: if `ρ < 0.5`, stop and diagnose before proceeding** — that indicates the Comex municipality-attribution problem is severe enough to change the design.

### 4.4 `g_dt` — Branch A shock
```
omega_pd  =  X_pd,2010^BR / Σ_p X_pd,2010^BR
g_dt      =  Σ_p  omega_pd × arcΔ( m_dp_row[t] , m_dp_row[2010] )   [PRIMARY]
g_dt_tot  =  arcΔ( Σ_p m_dp_row[t] , Σ_p m_dp_row[2010] )    # robustness variant
```
| column | type | constraint |
|---|---|---|
| `destino` | character | |
| `ano` | integer | |
| `g_dt`, `g_dt_tot` | double | ∈ [−2, 2] |

Gate: `stopifnot(all(abs(rowsum(omega_pd, destino) - 1) < 1e-8))`, bounds as above.

---

## 5. `epw_ladder` — the unified exposure panel

One row per microregion × year × rung. This is the object every estimation script consumes.

| column | type | constraint |
|---|---|---|
| `microrregiao` | integer | |
| `ano` | integer | ∈ {2014, 2018, 2022} |
| `rung` | character | ∈ {`S0`,`S1`,`S2L`,`S2`,`S3_N1`,`S3_N2`} |
| `epw`, `epw_pos`, `epw_neg` | double | finite |
| `theta_r` | double | `>= 0`; `NA` for `S3_N1` |

Gates:
```r
stopifnot(
  all(abs((epw_ladder$epw_pos + epw_ladder$epw_neg) - epw_ladder$epw) < 1e-10),
  all(epw_ladder$epw_pos >= 0),
  all(epw_ladder$epw_neg <= 0),                        # v7 sign convention: do NOT re-sign
  nrow(epw_ladder) == N_MICRO_EXPECTED * 3 * 6 - (n_excluded_S3_N1)
)
```

The `epw_neg <= 0` assertion is the guard against silently reintroducing the sign bug the v7 audit fixed. Keep it.

**S0 must reproduce `epw_v7` exactly.** Assert bitwise equality:
```r
stopifnot(all.equal(filter(epw_ladder, rung == "S0")$epw, epw_v7$epw, tolerance = 0))
```
If this fails, the ladder is not comparable to the published baseline and nothing downstream is interpretable. This is the packet's canary.

---

## 6. Outputs

All written to `output/packet_D/`. **No existing file is overwritten.** If a target path exists, abort.

| file | contents |
|---|---|
| `tab_d_ladder.md` | main table: β⁺, β⁻ by rung × outcome, RI p-values leading, clustered SEs in a secondary row |
| `tab_d_rotemberg.md` | α by unit and cycle, top-5, top-3 share, effective shock count, all rungs |
| `tab_d_balance.md` | BHJ balance by rung and cycle, with the 2022 conjecture flagged |
| `tab_d_independence.md` | correlation matrix of `epw` across rungs |
| `tab_d_bridge.md` | Comex vs employment-imputed share correlation (D.4.3) |
| `tab_d_firststage.md` | S2-IV first stage: coefficient, F, exposure-weighted |
| `tab_d_robustness.md` | leave-one-out, entrepôt, port exclusion, N1/N2, volume variant |
| `fig_d_ri.pdf` | RI permutation distributions, faceted by rung × cycle |
| `fig_d_shocks.pdf` | shock distributions by rung; top/bottom 20 units labelled |
| `log_d_unmatched_codes.csv` | country-code harmonisation failures (D.4.1) |
| `RATIONALE_D.md` | `[D-1]` … `[D-30]` entries, appended to the main `RATIONALE.md` at the end |

---

## 7. Pre-registration block

Written to `RATIONALE_D.md` **before** step 6 of the execution order, and not edited afterwards.

```
[D-PRE-1]  2022 balance conjecture.
  S0 fails BHJ balance at p ~ 0.01 in 2022; 2014 and 2018 pass.
  Prediction: 2022 passes at S2 and S3, because the failure reflects Brazilian
  supply expansion (pre-salt) rather than destination demand.
  Recorded before the test was run.

[D-PRE-2]  S2-IV first-stage threshold.
  Threshold F = ____ (fill in before running).
  Below threshold, S2-IV is not reported as a headline specification.

[D-PRE-3]  Independence threshold.
  If rho(EPW_S0, EPW_S3) > 0.9, Branch A is reframed in the write-up as a
  measurement robustness check rather than an identification robustness check.

[D-PRE-4]  Effective-shock claim.
  The manuscript currently asserts the arc respecification raises the effective
  number of shocks to "between five and nine." No output supports this figure.
  It is verified at step 6 or removed from the text.
```
