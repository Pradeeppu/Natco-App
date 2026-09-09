# Documentation

Thirteen documents. They are numbered in the order you would read them to
understand the system from scratch, not in the order they were written.

Each one answers a question. If you are looking for something specific, find
the question rather than skimming all thirteen.

| # | Document | The question it answers |
|---|---|---|
| 00 | [Project status and runbook](00-project-status.md) | Where is the build, how do I run it, what is left? **Start here.** |
| 01 | [Architecture](01-architecture.md) | How is the code layered, and why is the domain layer pure Dart? |
| 02 | [Data model](02-data-model.md) | What are the entities and their fields? |
| 03 | [Firestore schema](03-firestore-schema.md) | What are the collections, ids, indexes and guard documents? |
| 04 | [Security model](04-security-model.md) | Who may do what, to which schools, and how is that enforced? |
| 05 | [Navigation map](05-navigation-map.md) | What are the routes and which permission does each require? |
| 06 | [Offline and sync strategy](06-offline-sync-strategy.md) | What works offline, and how does it reconcile? |
| 07 | [OMR pipeline](07-omr-pipeline.md) | How does a photograph become a set of answers? |
| 08 | [MVP implementation plan](08-mvp-implementation-plan.md) | What are the twelve phases and what gates each one? |
| 09 | [Dependencies](09-dependencies.md) | Why is each package here, and what was rejected? |
| 10 | [OMR calibration and testing](10-omr-calibration-testing.md) | How is scanner accuracy measured rather than claimed? |
| 11 | [Environment setup](11-environment-setup.md) | How do I set up Flutter, Android and a Firebase project? |
| 12 | [Deployment](12-deployment.md) | How does a build reach a device safely? |

## If you are…

**Joining the project.** Read 00, then 01, then 04. That is enough to run the
app, find your way around the code, and not accidentally weaken the access
model. Read 08 to see where your work fits in the sequence.

**Picking up the next phase.** Read 08 for the gate you have to satisfy, then
the document for your phase: 03 for anything touching the schema, 06 for
offline work, 07 and 10 for the OMR engine.

**Reviewing security.** 04 is the model, `firebase/firestore.rules` is the
enforcement, and 03 explains the guard-document pattern that makes uniqueness
work without a unique constraint.

**Debugging something that will not run.** 11, Troubleshooting — including two
traps on the current development machine that look like project faults and are
not.

## Conventions in these documents

- **§n** refers to a numbered section of the original requirement document.
- **Critical Rule n** refers to the fifteen non-negotiable product rules.
- Where a decision could reasonably have gone the other way, the document
  states what was rejected and why. Those paragraphs are the useful ones —
  they are the difference between a decision and an accident.
- No document claims an OMR accuracy figure. None has been measured.
