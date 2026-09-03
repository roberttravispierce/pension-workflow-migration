# Pension Workflow Migration

A working simulation of a legacy batch-platform migration: undocumented Informatica-style ETL workflows moving to **Temporal + Rails 8**, with the validation, documentation, and observability discipline that kind of migration actually requires. Built as a working lab — the git history reads as the story, in order.

## The scenario

A pension administrator runs decades-old, undocumented ETL workflows that compute benefit payments. The original authors are nearing retirement. Converting the workflows is ordinary work; **proving the conversion reproduces a system nobody fully remembers — before the people who remember it leave — is the actual project.**

## The five artifacts

| Artifact | Where | What it demonstrates |
|---|---|---|
| The frozen input | `data/input/` + `script/generate_dataset.rb` | 1,013 members, seeded and byte-reproducible; 13 curated edge cases (retroactive adjustments, rehires, duplicate effective dates, a leap-day birthday). Several deliberately have no documented right answer. |
| The legacy system | `legacy/` | `WF_M_PENS_CALC_03.XML`, a PowerCenter-shaped workflow whose business rules are uncommented expression strings — and `integration_service.rb`, an engine that interprets them. **The XML is the specification.** Running it captures the golden output (`data/golden/`). |
| AI documentation, guarded | `docs/legacy/` + `script/doc_check.rb` | Generated docs with a provenance lifecycle, a mechanical checker diffing the doc's claims against the export (it caught the AI miscounting in its first draft), and a review-by-disagreement record — two generations disagreed on exactly one section. |
| The migration | `app/workflows/`, `app/activities/`, `app/models/pension/` | The same calculation as a Temporal workflow in Rails 8, built clean-room from the documentation. Domain logic in plain Ruby objects; thin chunked activities exchanging file references; the workflow ID is the run's business identity (`pension-calc-2026-09`). |
| The reconciliation gate | `script/reconcile.rb` + `data/reconciliation/` | Row count, member set, checksums, column totals, then **every field of every member — no sampling, no tolerance on money.** Nonzero exit on any discrepancy: a gate, not a report. |

## What reconciliation found

First run of the migration against the golden output: **row count matched (381 = 381), member set matched** — the checks most migrations gate on were green. Underneath: **18 discrepancies across 11 members, four causes, every one an undocumented rule.**

1. **Rehire service bridging** — the legacy bridges prior service; the clean-room reading counted only the current employment period. One member silently loses **$910.82/month, 44% of their pension.**
2. **Duplicate effective dates** — the legacy keeps the last row read; the migration kept the first. File order decides a pension.
3. **Gap-spanning averaging windows** — the legacy treats adjacent available years as consecutive across a missing year; the migration required calendar-consecutive years.
4. **Rounding placement** — the legacy rounds final average salary to the cent before multiplying; the migration rounds once at the end. Eight members off by exactly one cent.

The full report: `data/reconciliation/RECON_2026-09.txt`. The FAS-window ambiguity was also the one section two independent documentation generations disagreed on (`docs/legacy/disagreements.md`) — resolved empirically by the golden data, not by prose. Captured behavior answers questions after the experts are gone; documentation stops being checkable the day its reviewer leaves.

## Running the whole demonstration

```
temporal server start-dev            # local Temporal server, Web UI at localhost:8233
docker run -d --name pension-lab-mysql -e MYSQL_ALLOW_EMPTY_PASSWORD=yes -p 3306:3306 mysql:8.4
bin/setup --skip-server

ruby script/generate_dataset.rb                       # regenerate the frozen input (idempotent)
ruby legacy/integration_service.rb 2026-09            # run the legacy workflow -> golden output
ruby script/doc_check.rb                              # verify the AI docs against the export

ruby script/worker.rb                                 # Temporal worker (own terminal)
bin/rails runner script/start_pension_calc.rb 2026-09 # run the migration
ruby script/reconcile.rb 2026-09                      # the verdict
```

`bin/rails test` covers the migration's domain objects; where a rule is contested between implementations, the golden dataset is the test.

## Provenance

Built AI-assisted throughout — generation guarded by mechanical checks and reconciliation, the same discipline the scenario itself argues for.
