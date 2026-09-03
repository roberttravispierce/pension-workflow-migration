# Review by disagreement — WF_M_PENS_CALC_03

Two independent generations documented the same export. Where they agree, the
source was unambiguous. Where they disagree, the source is genuinely ambiguous —
and that, not the whole document, is where scarce expert review time should go.

## Agreed by both generations (not queued for review)

Adjustment visibility and last-posting-wins; bridged rehire service; truncation
(not rounding) of service years; vesting inclusive at 5; early-reduction
truncation; survivor and accrual tables; the payability filter; FAS rounded to
the cent before multiplication; final benefit rounding.

## DISAGREEMENT 1 — FAS window semantics (m_BEN_CALC_03 / EXP_FAS_WIN)

**Generation A:** "Averages the best three consecutive calendar years within
the member's final ten years."

**Generation B:** "Averages three successive rows of the member's available
salary years — a missing year does not break the window, because the state
machine ranks rows, not calendar years."

The expressions rank ROWS (`V_YR_RNK` increments per row, not per year), which
supports B — but nothing in the export states the intent, and A is what a
reasonable implementer writes from a prose description.

**Expert review status:** the original author is unavailable. **Resolved
empirically instead:** member EDGE-0006 (salary gap inside the window, peak
straddling it) produces FAS 82,000.00 under the legacy run — the cross-gap
window. **Generation B describes the system as it behaves.** The golden dataset
answered the question the expert would have.

**Migration consequence, confirmed:** an implementation built on reading A
diverges by -$52.06/month on EDGE-0006. Caught by field-level reconciliation.
