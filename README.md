# Pension Workflow Migration

A working simulation of a legacy batch-platform migration: **Informatica-style ETL workflows →
Temporal + Rails 8**, with the validation, documentation, and observability discipline that kind
of migration actually requires.

## The scenario

A pension administrator runs decades-old, undocumented ETL workflows that compute benefit
payments. The original authors are nearing retirement. The migration has five problems, and this
repo works through each of them with running code:

1. **The legacy workflow** — an undocumented, PowerCenter-shaped XML workflow definition,
   executed by a minimal runner. Nobody remembers why it does what it does.
2. **AI-generated documentation, expert-verified** — documentation generated from the legacy
   artifacts, mechanically ground-truthed against extracted metadata, with ambiguous sections
   routed to expert review and an explicit sign-off lifecycle.
3. **The Temporal implementation** — the same computation rebuilt as Temporal workflows and
   activities inside a Rails 8 application.
4. **The validation harness** — a golden dataset captured from the legacy run, and full-set,
   field-level reconciliation proving the new implementation produces identical output for
   identical input.
5. **Auditing and observability** — structured logging with correlation IDs, Temporal's event
   history as the audit trail, and detection of the failure most monitoring misses: the job that
   never ran at all.

## Why these problems

Because converting a batch job is ordinary work. Proving the conversion reproduces a system
nobody fully remembers — before the people who remember it leave — is the actual project.

## Running it

```
temporal server start-dev        # local Temporal server, Web UI at localhost:8233
bin/setup                        # app dependencies
ruby script/worker.rb            # Temporal worker (own terminal)
```

Sections above are built in order; the git history reads as the same sequence.
