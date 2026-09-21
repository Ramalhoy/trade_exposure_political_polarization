# V-Party as a second ideology source — what it is and how it would be used

Companion note to `[PL-43]`. Written 21/09/2026.

---

## 1. What the dataset is

**V-Party** (Varieties of Party Identity and Organization) is the V-Dem Institute's expert
survey of *parties*, distinct from the country-level V-Dem indices. Confirmed figures for the
version I can verify (**v2, published February 2022**):

| property | value |
|---|---|
| unit of observation | **country–party–election date** (party-election-year) |
| coverage | **1970–2019** |
| scope | 169 countries, 1,955 parties, 1,560 elections, 6,330 party-election observations |
| Brazil | **25 parties** (election results back to 1900; expert-survey items 1970–2019) |
| formats | SPSS, Stata, CSV, R — free download |

The item you want is the **left–right ideology** placement (in the V-Dem naming scheme,
`v2pariglef`, normally supplied in ordinal, `_ord` and `_osp` variants). **Check the codebook
for the exact variable name and version before writing any code** — I have not verified it
against the file, and this is precisely the kind of unchecked premise that cost you `[PL-13]`.

## 2. Why it fits your problem, and where it stops

**Fits.** Your binding constraint is that BLS scores **13 / 14 / 20 / 20** parties while the
Chamber has **27 / 32 / 35 / 32** taking votes. V-Party covers **25** Brazilian parties and is
**time-varying by election**, so it addresses both halves of the gap at once — more parties,
and no wave-mismatch problem requiring a carry rule at all.

**Stops, hard, at two places.**

1. **2022 is very likely out of range.** v2 ends in 2019. Unless a later release extends it,
   V-Party covers your 2010, 2014 and 2018 cycles and **not 2022** — which is the cycle with
   the UNIÃO hole and the one your 2022 identification already rests on three petroleum
   microregions. Verify this on the V-Dem dataset page before anything else; if 2022 is
   missing, V-Party is a three-cycle robustness column, not a replacement primary.
2. **25 parties is better than 20, not complete.** The residual is the micro-party tail —
   PMN, PHS, PTC, PRTB, PRP, PCB, PCO and so on — which is small in vote terms but is the same
   tail BLS misses. Expect V-Party to fix the *large* holes (PSL, NOVO, PRB, SD, PSC, PROS)
   and leave the tail roughly where it is.

## 3. What it is *not*

V-Party's left–right item is an **expert placement**, produced by country experts coding party
platforms and behaviour. BLS is a **legislator survey** — deputies placing parties, including
their own. These are different instruments measuring a related construct, and they disagree in
documented ways. Zucco & Power's own 2025 work on elite ideological obfuscation in Brazil is
about precisely that: legislators misrepresenting party positions. So a disagreement between
the two sources is **not** evidence that one is broken; it is the thing you report.

Practical consequence: **never average the two into one score, and never pool them.** Build
them as parallel panels and compare.

## 4. How you would actually use it

### Step 1 — build the bridge table (the only fiddly part)
V-Party carries its own party identifiers, not TSE `SG_PARTIDO`. Two routes:

- **Party Facts** (`partyfacts.org`) maintains cross-dataset party identifiers and already
  links V-Party to other party datasets. This is the intended route and saves hand-matching.
- Otherwise match on V-Party's English party name plus abbreviation against your TSE labels,
  by hand, for 25 parties. Tedious but bounded.

Either way the output is a versioned `party_crosswalk_vparty.csv` with the same shape and the
same `verified` discipline as `party_crosswalk_bls.csv`. Renamings are handled the same way:
V-Party tracks party continuity across renamings, so **PMDB→MDB and PRB→Republicanos are
likely one party-series, not two** — which, if true, removes several of the rows that were
hardest to adjudicate in the BLS crosswalk.

### Step 2 — standardise within year, separately, on the estimation sample
BLS `ideo` is standardised around zero on roughly [−1, 1]. V-Party's item is on its own scale.
Do **not** rescale one onto the other. Standardise each within year on the microregions in the
estimation frame, then build the indices. This is the same convention `[D-64]` already uses.

One consequence to state in the text: the **centre-emptying index depends on an absolute band**
(`|ideo| ≤ 0.25`). That band is not transportable across sources. Under V-Party either
re-derive the band as a within-year quantile of the ideology distribution, or report `ΔP^N`
for BLS only and restrict the V-Party comparison to Dalton and Esteban–Ray — both of which are
**scale-equivariant after standardisation** and therefore comparable. I would do the latter:
it is cleaner, and `ΔP^N` is already the index you are considering demoting.

### Step 3 — build the parallel panel and compare at three levels
1. **Score level.** Correlate BLS `ideo` against standardised V-Party left-right, by wave, for
   the parties both cover. A high correlation is the licence to use V-Party as a robustness
   source at all; a low one is itself a finding about the BLS instrument.
2. **Index level.** Correlate `P_dalton` and `P_er` built from each source, by year, across
   microregions. This is the number that matters: if the *indices* agree even where the
   *scores* differ somewhat, the coefficient will not move.
3. **Coefficient level.** Re-run the baseline `ΔP ~ ΔEPW` specification on the V-Party index and
   report it beside the BLS one. That is the appendix table.

### Step 4 — what it buys you in the write-up
Three things, in order of value:

- It **retires the carry rule** for whichever cycles it covers. No `[PL-37]`, no backward
  injection, no `[PL-39]` three-way for those years — the score simply exists. That is worth
  more than the robustness column itself.
- It gives PSL-2018 a **contemporaneous** score from an independent instrument, which is the
  single cleanest answer to the objection that your 2018 index rests on an imputation.
- It converts "the ideology source has thin coverage" from a limitation into a **comparison**.

## 5. Cost, honestly

Roughly a day: download, build and verify the bridge for 25 parties, standardise, rebuild
indices, three comparison tables. The bridge is the only part that cannot be rushed.

Against a mid-February deadline and with Packet E unrun, I would **not** do this before the
`[PL-27]` decision at L5. If the Chamber index reproduces the presidential pathology, the
branch dies and V-Party is wasted effort. If it does not, V-Party becomes the obvious next
step and may well replace the carry rule entirely.

---

**Sources for the figures above:** V-Dem's [V-Party dataset page](https://www.v-dem.net/data/v-party-dataset/)
and [codebook](https://www.v-dem.net/documents/6/vparty_codebook_v2.pdf); coverage counts from
the [QoG data finder entry](https://datafinder.qog.gu.se/dataset/vparty); Brazilian party count
from [Party Facts](https://partyfacts.herokuapp.com/data/vparty/).
