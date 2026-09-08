# NATCO Assessment App

An offline-first, field-ready assessment data pipeline for school-based
educational assessments: master data, assessment setup, OMR capture,
confidence-gated machine reading, human validation, scoring, synchronisation,
analytics and a complete audit trail.

> **Terminology.** The monitoring role is **Supervisor**. The word
> "Coordinator" is not used anywhere in this product — a test
> (`test/terminology_test.dart`) scans the source tree to keep it that way.

**Status: Phase 1 (Foundation) complete.** Architecture, theming, routing,
configuration, authentication, the role and scope system, and the security
rules are implemented and tested. Phases 2–12 are scoped in
[docs/08-mvp-implementation-plan.md](docs/08-mvp-implementation-plan.md), and
the screens for them exist as guarded placeholders that name the phase which
implements each one.

`flutter analyze` is clean and 300 tests pass.

---

## Project overview

NATCO is not an OMR scanner with a database attached. It is a pipeline in which
every stage has to be able to prove what it did:

```
Master school/student data → Assessment setup → Teacher session →
OMR capture → Image quality gate → Detection → Confidence check →
Human validation where required → Scoring → Sync → Analytics → Reports/Audit
```

The design priorities, in the order that settles any conflict between them:

1. Data integrity
2. OMR reliability
3. Offline reliability
4. Security
5. Auditability
6. Ease of field use
7. Analytics
8. Visual polish

Three consequences worth stating up front, because they shape everything else:

- **No number appears in this app that it has not measured.** The dashboard
  leaves assessment metrics blank until the phases that produce them are in
  place, rather than showing plausible placeholders. There is no accuracy
  figure anywhere in this repository, because none has been measured yet.
- **Machine readings are evidence and are never overwritten.** A human
  validator's decision is recorded alongside the machine's, never on top of it.
- **Nothing is silently discarded.** Not a failed upload, not a duplicate
  sheet, not a conflicting revision.

## Architecture

```
Presentation  →  Domain  →  Data  →  Services / Infrastructure
```

The domain layer is pure Dart with no Flutter and no Firebase imports, which is
what makes the scoring engine, the confidence classifier and the permission
matrix testable without a device. Every backend touchpoint is an abstract
interface with a Firebase implementation and an in-memory one, so the backend is
replaceable and the whole app runs with no backend at all.

Full detail: [docs/01-architecture.md](docs/01-architecture.md).

### Documentation map

| Document | Contents |
|----------|----------|
| [01-architecture.md](docs/01-architecture.md) | layering, folder structure, concurrency, error model |
| [02-data-model.md](docs/02-data-model.md) | every entity and its fields |
| [03-firestore-schema.md](docs/03-firestore-schema.md) | collections, deterministic ids, uniqueness, indexes, Storage layout, Functions |
| [04-security-model.md](docs/04-security-model.md) | roles, the full permission matrix, scopes, claims, rule invariants, privacy |
| [05-navigation-map.md](docs/05-navigation-map.md) | routes, guards, per-role destinations |
| [06-offline-sync-strategy.md](docs/06-offline-sync-strategy.md) | local-first writes, queue, retry, idempotency, crash recovery, conflicts |
| [07-omr-pipeline.md](docs/07-omr-pipeline.md) | sheet template, the eleven pipeline stages, classification, state machine |
| [08-mvp-implementation-plan.md](docs/08-mvp-implementation-plan.md) | twelve phases with exit criteria; what phase 1 delivered; what is deferred and where |
| [09-dependencies.md](docs/09-dependencies.md) | every dependency and why, and what was rejected |
| [10-omr-calibration-testing.md](docs/10-omr-calibration-testing.md) | the accuracy dataset, harness, metrics and calibration screen |
| [11-environment-setup.md](docs/11-environment-setup.md) | toolchain, four environments, Firebase setup, running, testing, building, troubleshooting |
| [12-deployment.md](docs/12-deployment.md) | deployment order, release checklist, rollback, migration, monitoring |

## Repository layout

```
natco_app/            the Flutter application
├── lib/
│   ├── app/          composition root, router, guards, theme, shell, config
│   ├── core/         failures, Result, logger + redaction, services, widgets
│   ├── features/     auth, dashboard, and one folder per pipeline stage
│   └── data/         local (Hive) and remote (Firebase) implementations
└── test/             unit, widget and end-to-end tests
firebase/             firestore.rules, storage.rules, firestore.indexes.json
docs/                 the documents above
```

## Prerequisites

- Flutter 3.47.2 (stable) / Dart 3.13.2
- Android SDK, API 34+ to compile, API 23+ to run
- JDK 17
- Firebase CLI, for deploying rules

## Quick start — no Firebase project needed

```bash
cd natco_app
flutter pub get
flutter run --dart-define=NATCO_ENV=demo
```

`demo` runs the real app — real router, real guards, real permission matrix —
over in-memory services. The login screen lists one account per role; tap a
role chip to fill the form. The password is `natco1234`.

This is how the test suite runs too, which is why it needs no device and no
backend.

## Environments

`--dart-define=NATCO_ENV=<demo|dev|staging|prod>`. An unrecognised value falls
back to `demo`, never to `prod`. Details and per-environment defaults:
[docs/11-environment-setup.md](docs/11-environment-setup.md).

## Firebase setup

Summarised — the full sequence, including the first Super Admin and the role
mirror, is in
[docs/11-environment-setup.md](docs/11-environment-setup.md#firebase-project-setup).

1. Create a project per environment; add an Android app.
2. Put `google-services.json` in `natco_app/android/app/` (it is
   `.gitignore`d; every environment supplies its own).
3. Enable Authentication → Email/Password, Firestore (Native mode), Storage and
   Crashlytics.
4. Deploy rules and indexes **before** any client build points at the project:
   ```bash
   cd firebase && firebase use <alias>
   firebase deploy --only firestore:rules,firestore:indexes,storage:rules
   ```
5. Seed `roles/*` and `app_config/global`, then create the first Super Admin.

## Security

Two independent questions are answered on every access: does this **role** hold
the permission, and is the target inside this user's geographic **scope**. Both
are checked on the client for usability and on the server for enforcement — a
patched client gets exactly as far as the rules allow.

Enforced by `firebase/firestore.rules` and `firebase/storage.rules`, and not
bypassable by any client:

- Published answer keys are immutable; a correction is a new version with a
  recorded reason.
- Machine detection results are write-once.
- Scores are written only by a Cloud Function — no client, in any role, can
  write a score.
- OMR ids are never reused; student identities are never silently merged.
- Audit logs are append-only for everyone, Super Admin included.
- Original OMR images cannot be replaced or deleted by any client.
- Nobody reads outside their scope.

No service-account JSON ever enters the Flutter project, and the structured
logger runs a redaction pass so that no code path can emit a password, a token
or a student's personal data. Full model, including the permission matrix and
the reasoning behind the judgement calls:
[docs/04-security-model.md](docs/04-security-model.md).

## Local database

Hive (`hive_ce`), with the session box encrypted using a key held in the
platform keystore. Field-critical writes go to Hive **and** the sync queue in
one step, so the network is never a precondition for a teacher's work.
Firestore's own offline cache is enabled as a convenience for read-mostly admin
screens, but it is not the offline strategy —
[docs/06-offline-sync-strategy.md](docs/06-offline-sync-strategy.md) explains
why.

## OMR engine

One controlled template (`natco_v1`), with all bubble geometry stored as data
rather than code, so a future sheet layout is a new JSON file rather than a
rewrite. Eleven pipeline stages from decode to validation decision, run in a
worker isolate so heavy processing never blocks the UI. Thresholds live in
configuration and are calibratable without a release.

The goal is explicitly **not** maximum automatic recognition. It is to process
clear sheets automatically and route uncertain ones to a human — so the release
gate is the *silent error rate* (high-confidence answers that are wrong), not
the headline accuracy figure. See
[docs/07-omr-pipeline.md](docs/07-omr-pipeline.md) and
[docs/10-omr-calibration-testing.md](docs/10-omr-calibration-testing.md).

## Running tests

```bash
cd natco_app
flutter analyze              # must be clean
flutter test                 # 300 tests: unit, widget, end-to-end
flutter test --coverage
```

What is covered today:

| Area | Examples |
|------|----------|
| Permissions | every role's exact permission set; who may waive the quality gate, correct a score, calibrate the scanner |
| Scope | a Supervisor cannot reach a neighbouring cluster; a teacher cannot reach another section; a target with unknown ancestry does not match |
| Sessions | offline validity measured from last verification; deactivated users; malformed cached records refused |
| Routing | fail-closed on an undeclared route; deep link survives sign-in; no visible destination leads to /unauthorized |
| Auth repository | server wins when reachable, cache when not, definitive rejections clear the cache |
| Failures | no user-facing message leaks technical detail; retryability classified correctly |
| Logging | redaction survives a whole user object being logged carelessly |
| Identity | dedupe keys collide across name spellings and keep Indic vowel signs |
| End to end | sign-in, deep link, offline restart, role change while offline, deactivation, sign-out |
| Terminology | the forbidden term appears nowhere in the product |

On-device integration tests (`integration_test/`) arrive with phase 5, when
there is a camera to drive.

## Building

```bash
flutter build apk --release --split-per-abi --dart-define=NATCO_ENV=prod
flutter build appbundle --release --dart-define=NATCO_ENV=prod
```

`--split-per-abi` keeps the download small, which matters on the devices this
app targets. Release signing and the full checklist:
[docs/12-deployment.md](docs/12-deployment.md).

## Troubleshooting

Common symptoms and their causes are tabulated in
[docs/11-environment-setup.md](docs/11-environment-setup.md#troubleshooting) —
including the two most frequent: a `dev` build that shows demo accounts
(`NATCO_ENV` was not passed) and blanket permission-denied errors (rules not
deployed, or custom claims not yet minted).

## Contributing

- `flutter analyze` clean and `flutter test` green before any commit. Both run
  with no device and no backend.
- The domain layer stays free of Flutter and Firebase imports.
- Business logic does not live in widgets.
- A new route declares its required permission; the route table makes that
  field mandatory and the guard refuses anything undeclared.
- A change to the permission matrix changes three places together — the Dart
  matrix, `firebase/firestore.rules`, and the `roles/*` mirror — and the
  matrix tests are updated deliberately, not to make a red test go green.
- Deferred work is documented with the phase that owns it. `TODO` is not a
  design.
