# WF_M_PENS_CALC_03 — Monthly Benefit Calculation (generated documentation)

> Provenance: AI-generated from `legacy/WF_M_PENS_CALC_03.XML` (see `provenance.yml`).
> Mechanical claims below are verified against the repository export by
> `script/doc_check.rb`. Sections marked **[FLAGGED]** carry genuine ambiguity —
> two independent generations disagreed there (`disagreements.md`) and the
> reading requires expert confirmation or empirical resolution.

## Overview

Monthly defined-benefit calculation run. Scheduled monthly (day 3, 03:30). Three
sessions execute in sequence, each gated on the predecessor's success. The
workflow variable `$$RUN_PRD_END` bounds both adjustment visibility and payability.

## Inventory (mechanically verified)

| Object | Count |
|---|---|
| Mappings | 3 |
| Sessions | 3 |
| Transformations | 11 |
| Expression ports carrying business rules | 18 |

Sequence: `s_m_SAL_EFF_01` → `s_m_SVC_VEST_02` → `s_m_BEN_CALC_03`.

## Session 1 — s_m_SAL_EFF_01 (mapping m_SAL_EFF_01)

Builds effective annual salary per member-year.

- Source: salary history; lookup against pension adjustments.
- The lookup SQL override restricts adjustments to `POSTED_DT <= $$RUN_PRD_END`
  — **an adjustment does not exist until it is posted**, regardless of its
  effective date. Lookup policy "Use Last Value" over `ORDER BY POSTED_DT`:
  the latest posting for a member-year wins.
- `EFF_SAL = IIF(ISNULL(CORR_ANN_SAL), ANN_SAL, CORR_ANN_SAL)` — corrected
  salary replaces base salary outright when present.

## Session 2 — s_m_SVC_VEST_02 (mapping m_SVC_VEST_02)

Service, vesting, and benefit factors per member; filters to payable members.

- Service months: `IIF(ISNULL(REHIRE_DT), MONTHS_BETWEEN(TERM_DT, HIRE_DT),
  MONTHS_BETWEEN(PRI_TERM_DT, HIRE_DT) + MONTHS_BETWEEN(TERM_DT, REHIRE_DT))`
  — **a rehired member's prior service is bridged**: both employment periods
  count toward credited service.
- Service years: months / 12, truncated to 4 decimals (truncation, not rounding).
- Vesting: 5 or more service years (inclusive at exactly 5).
- Early retirement: reduction of 0.5% per whole month of retirement before age
  65 (age in months >= 780 means no reduction; the months-early quantity is
  truncated toward zero before applying).
- Survivor factors: js50 -> 0.90, js100 -> 0.84, otherwise 1.0.
- Accrual rates: clergy -> 1.75%/yr, lay -> 1.50%/yr.
- Payability filter: vested AND retirement date present AND retirement on or
  before `$$RUN_PRD_END`.

## Session 3 — s_m_BEN_CALC_03 (mapping m_BEN_CALC_03)

Final average salary and the monthly benefit.

- Input sorted by member, then salary year **descending**.
- **[FLAGGED] FAS window semantics.** The rolling window is implemented as a
  variable-port state machine over the sorted rows (`V_YR_RNK`, `V_WIN_SUM`,
  `V_SAL_1`, `V_SAL_2`, `V_FAS_MAX`). It averages three successive ROWS within
  the ten most recent ROWS per member. Whether "successive rows" means
  consecutive CALENDAR years or merely adjacent AVAILABLE years — the two
  differ exactly when a member has a missing salary year — is not decidable
  from the expressions alone. See `disagreements.md`; resolved empirically.
- FAS is **rounded to the cent at this step** (`ROUND(V_FAS_MAX, 2)`), before
  any multiplication.
- Aggregation takes the LAST row's running maximum per member; a normal join
  drops members without salary data.
- `MO_BEN = ROUND(FAS * ACCR_RT * SVC_YRS * EARLY_FCT * SURV_FCT / 12, 2)`.

## Behaviors defined only by execution (not stated anywhere in the export)

- **Duplicate effective dates:** two salary rows for the same member-year are
  resolved by engine read order — the last row read wins. File order is
  load-bearing.
- **NULL propagation:** arithmetic with NULL yields NULL; comparisons with NULL
  are false. Non-retired members fall out of the filter this way, not by
  explicit rule.
