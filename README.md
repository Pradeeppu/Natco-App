# NATCO Assessment App

An offline-first assessment pipeline for school field work: master data →
assessment setup → OMR capture → machine reading → human validation →
scoring → sync → analytics.

It is built for the conditions it actually runs in — weak or absent internet,
low-end Android phones, imperfect photographs of answer sheets taken in a
classroom — so the design priorities are, in order: **data integrity, OMR
reliability, offline reliability, security, auditability, ease of field use,
analytics, visual polish.** Where those conflict, the earlier one wins.

| | |
|---|---|
| **Status** | Phases 1–2 of 12 complete · UI reviewable through Phase 11 |
| **Verification** | `flutter analyze` clean · 363 tests passing |
| **Toolchain** | Flutter 3.47.2 · Dart 3.13.2 · JDK 17 · Android API 23–34 |
| **Backend** | Firebase (Auth, Firestore, Storage, Functions, Crashlytics) |

**New here? Start with [docs/00-project-status.md](docs/00-project-status.md)** —
what is built, what is left, and the two environment traps that will otherwise
cost you an afternoon.

---

## Contents

- [Project overview](#project-overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Flutter setup](#flutter-setup)
- [Android setup](#android-setup)
- [Firebase setup](#firebase-setup)
- [Environment variables](#environment-variables)
- [Firestore setup](#firestore-setup)
- [Storage setup](#storage-setup)
- [Cloud Functions](#cloud-functions)
- [Local database](#local-database)
- [OMR engine](#omr-engine)
- [Running the app](#running-the-app)
- [Running tests](#running-tests)
- [Building an APK](#building-an-apk)
- [Building a release](#building-a-release)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Privacy](#privacy)
- [Deployment](#deployment)
- [Contributing](#contributing)

---

## Project overview

The product is not an OMR scanner with a database bolted on; it is a data
pipeline with an OMR stage in the middle. Everything is arranged around one
question: **can this number be trusted, and can you prove where it came
from?**

That produces a few rules the code does not bend:

- A machine reading is **evidence**. A human can decide differently, but the
  machine's answer, its confidence and its per-option measurements are kept
  and never overwritten.
- A low-confidence sheet **cannot be scored** until a person has ruled on it.
- A published answer key is **immutable**. A correction is a new version with
  a recorded reason, and the old version stays readable so old scores stay
  explainable.
- Nothing captured in the field is **ever lost** — not to a crash, a flat
  battery, a failed upload or a closed app.
- The app **shows no number it has not measured**. There is no OMR accuracy
  figure anywhere in this repository, because none has been measured yet.

### Roles

Six, and the monitoring role is **Supervisor** — the word "Coordinator" is not
used anywhere in this product, and a test enforces that against the whole
source tree.

| Role | Holds |
|---|---|
| Super Admin | Everything, including the only rights to create master data and correct a score |
| Assessment Admin | Assessments, questions, answer keys, assessment analytics |
| Supervisor | Monitoring within assigned areas: validation, exceptions, sync conflicts, reports |
| PST Teacher | Their own school: conduct assessments, capture OMRs, sync, see permitted results |
| Scanner Operator | Capture and process OMRs, review scan quality, send ambiguous sheets on |
| Viewer | Read-only dashboards and reports |

Permission is one question, scope is the other, and both must pass:
`may this role do this?` and `may this user touch this school?` Full matrix in
[docs/04-security-model.md](docs/04-security-model.md).

### Geographic hierarchy

```
State → District → Cluster → School → Grade → Section → Student
```

These are controlled master data. A teacher never types a school name; every
such value comes from a selector backed by the hierarchy.

---

## Architecture

```
Presentation  →  Domain  →  Data  →  Services / Infrastructure
```

The domain layer is **pure Dart** — no Flutter imports, no Firebase imports.
That is what makes scoring, confidence classification, duplicate detection and
the permission matrix testable without a device or a backend.

```
lib/
├── app/         composition root, router, route guards, theme, shell
├── core/        Result, Failure, logger + redaction, pagination, shared widgets
├── features/    one folder per feature, each with data/ · domain/ · presentation/
└── data/        local (Hive) and remote (Firebase) implementations
```

Every backend touchpoint is an interface with a Firebase implementation and an
in-memory one, so the backend is replaceable and the whole app runs with no
backend at all. See [lib/README.md](lib/README.md) for the layering rules and
how to add a feature, and [docs/01-architecture.md](docs/01-architecture.md)
for the reasoning.

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Flutter | 3.47.2 (stable) | `pubspec.yaml` pins `sdk: ^3.13.2` |
| Dart | 3.13.2 | bundled with Flutter |
| JDK | 17 | required by the Android Gradle plugin |
| Android SDK | API 34 to compile, API 23 minimum | Android-first |
| Firebase CLI | latest | only for deploying rules and Functions |

`flutter doctor -v` should be clean for *Android toolchain*. A red mark there
stops `flutter build apk` but not `flutter analyze` or `flutter test`, both of
which run on a bare Flutter install.

> **Two traps on the current development machine.** They look like project
> faults and are not. See [Troubleshooting](#troubleshooting) before you spend
> time on either.

---

## Flutter setup

```bash
git clone <repository-url>
cd natco_app
flutter pub get
```

That is enough to run, test and analyze — demo mode needs nothing else.

---

## Android setup

- `applicationId`: `org.natco.natco_app` (a per-environment suffix such as
  `.dev` is supported).
- `minSdk` 23, `targetSdk`/`compileSdk` 34.
- Permissions declared: camera, and storage access through the system document
  picker (SAF), which grants access per file rather than to the whole library.
- `google-services.json` goes in `android/app/` and is **git-ignored** — each
  environment supplies its own, from a CI secret or a developer's local copy.
  It is not needed for `NATCO_ENV=demo`.

---

## Firebase setup

Do this once per environment (`dev`, `staging`, `prod`). Skip it entirely if
you only need demo mode.

1. Create the project in the Firebase console.
2. Add an Android app with the applicationId above.
3. Download `google-services.json` into `android/app/`.
4. Enable **Authentication → Email/Password**. No other provider is used.
5. Create **Firestore** in Native mode, in the region closest to the
   deployment (`asia-south1` for India).
6. Create a **Storage** bucket.
7. Enable **Crashlytics**. Analytics is deliberately left off — see
   [docs/09-dependencies.md](docs/09-dependencies.md).
8. Deploy the rules and indexes — see [Firestore setup](#firestore-setup).
9. Seed the role mirror: write `roles/{roleId}` documents matching
   `kRolePermissions` in
   `lib/features/auth/domain/entity/user_role.dart`.
10. Create the first Super Admin: create the Auth user, then a `users/{uid}`
    document with `role: "SUPER_ADMIN"`, `scope: {level: "GLOBAL"}`,
    `isActive: true`. Every other user is created from inside the app.

Full walkthrough, including the shape of a user profile document:
[docs/11-environment-setup.md](docs/11-environment-setup.md).

---

## Environment variables

There are no `.env` files and no secrets in the repository. Configuration
comes from three places, in precedence order:

1. **Compile-time** — `--dart-define=NATCO_ENV=<env>` selects the environment
   and its defaults. Nothing outside `lib/app/config/app_config.dart` reads
   `String.fromEnvironment`.
2. **Server-side** — the `app_config/global` Firestore document overrides
   feature flags, scanner thresholds and controlled vocabularies at runtime,
   so a threshold can be recalibrated without shipping a release.
3. **Per-device** — user settings, such as whether to upload images on mobile
   data.

| `NATCO_ENV` | Backend | Log level | Purpose |
|---|---|---|---|
| `demo` | none — in-memory | debug | Run and test the whole app with no Firebase project. **The default** when unset or unrecognised. |
| `dev` | development project | debug | Day-to-day development |
| `staging` | staging project | info | Pre-release verification |
| `prod` | production project | warning | Release |

An unrecognised value resolves to `demo`, never to `prod` — defaulting a
misconfigured build to production would be the most dangerous possible guess.

---

## Firestore setup

Collections, deterministic document ids, the uniqueness-guard pattern and the
composite indexes are specified in
[docs/03-firestore-schema.md](docs/03-firestore-schema.md).

```
users · roles · states · districts · clusters · schools
students · student_dedupe · student_enrollments
assessments · assessment_questions · answer_keys
assessment_assignments · assessment_sessions
omr_submissions · omr_registry · omr_answers · omr_validations
results · question_analytics · scope_analytics
sync_receipts · audit_logs · app_config
```

Deploy rules and indexes **before** the first client build reaches a project.
A Firestore database created without rules is open, and an open database with
student data in it is an incident.

```bash
cd firebase
firebase use <project-alias>
firebase deploy --only firestore:rules,firestore:indexes,storage:rules
```

Test against the emulator first:

```bash
firebase emulators:start --only firestore,storage,auth
```

See [firebase/README.md](firebase/README.md) for what the rules enforce.

---

## Storage setup

Object paths encode the ancestry, so a Storage rule can authorise a read by
comparing path segments with no database lookup:

```
omr/{academicYear}/{assessmentId}/{stateId}/{districtId}/{clusterId}/{schoolId}/{date}/OMR_{omrId}.jpg
```

No student name appears in any object key. Original captures are
**write-once**: `allow update, delete: if false` for every client, because a
captured sheet is evidence. Retention deletion runs server-side under
`enforceRetention` with admin credentials, and every deletion is audited.

---

## Cloud Functions

Not yet implemented — there is no `functions/` directory. The surface is
specified in [docs/03-firestore-schema.md](docs/03-firestore-schema.md) and
lands with the phases that need it:

| Function | Purpose | Phase |
|---|---|---|
| `onUserWrite` | Mirror role and scope into Auth custom claims, bump `claimsVersion` | 1 (deferred) |
| `publishAnswerKey` | Freeze a key version server-side | 3 |
| `submitOmrBundle` | Idempotent submission intake | 9 |
| `scoreSubmission` | The only writer of `results` | 8 |
| `rollupAnalytics` | Maintain scope and question rollups | 10 |
| `enforceRetention` | Scheduled retention deletion | 12 |

Scores are never client-writable: `results` is `allow write: if false`.

---

## Local database

Hive (`hive_ce`, the maintained fork) provides typed boxes with no on-device
schema migrations, initialised in `lib/data/local/hive_bootstrap.dart`.

- The **session cache** is encrypted with a device-bound key held in the
  Android Keystore via `flutter_secure_storage`. It stores a session record
  and an expiry — never a password, never a token. Offline use is permitted
  for a configurable window (default 7 days) measured from the last successful
  server check, not from sign-in.
- **Master data** (schools, students) deliberately uses Firestore's own
  offline cache rather than a hand-rolled Hive layer — those screens are
  read-mostly. The Hive offline-*write* path is Phase 4's job, for session and
  OMR data, which genuinely is written while offline.
- A failure to initialise Hive is logged and swallowed rather than fatal.
  Crashing on a storage problem would leave a field user with an app that
  will not open at all.

---

## OMR engine

Not yet built — Phases 5 and 6. The design is in
[docs/07-omr-pipeline.md](docs/07-omr-pipeline.md); the calibration and
accuracy-measurement plan is in
[docs/10-omr-calibration-testing.md](docs/10-omr-calibration-testing.md).

```
Camera image → quality analysis → registration markers → perspective correction
→ rotation → template alignment → OMR ID → bubble regions → fill measurement
→ classification → confidence → validation decision → scoring
```

Three decisions worth knowing before you touch it:

1. **No single threshold.** Every option gets a measured darkness score; the
   classifier compares them. Two nearly-equal marks are reported as
   `MULTIPLE_MARK`, not silently resolved to the darker one.
2. **The pipeline runs in a worker isolate**, so processing never freezes the
   UI.
3. **Accuracy is measured, not asserted.** A golden-dataset harness reports
   per-question accuracy, blank and multiple-mark detection, and the figure
   that actually gates a release: the **silent error rate** — answers the
   machine was confident about and got wrong.

An OpenCV wrapper package was evaluated and rejected (maintenance, 20–40 MB
per ABI, NDK/CMake collisions). The pipeline is written against our own
`OmrImageProcessor` interface with a pure-Dart implementation first, so a
native accelerator can arrive later behind the same five methods.

Version 1 targets a **controlled NATCO template**, not arbitrary sheets:
fixed bubble positions, four registration markers, a printed OMR ID.

---

## Running the app

```bash
flutter run --dart-define=NATCO_ENV=demo
```

Demo mode runs the **real** router, permission matrix, session controller and
repositories over in-memory services — it is how the test suite runs, not a
toy. Password for every demo account is `natco1234`; the login screen lists
them as tappable chips.

| Sign-in | Role | Scope it demonstrates |
|---|---|---|
| `superadmin@natco.demo` | Super Admin | Global |
| `assessmentadmin@natco.demo` | Assessment Admin | One state |
| `supervisor@natco.demo` | Supervisor | Two clusters |
| `teacher@natco.demo` | PST Teacher | One school, Grade 5 Section A only |
| `scanner@natco.demo` | Scanner Operator | Two schools |
| `viewer@natco.demo` | Viewer | Read-only |

Seeded: 1 state, 2 districts, 3 clusters, 5 schools, 100 students, sharing ids
with those scopes so the two cannot drift.

**Phases 3–11 are present as UI previews on sample data.** Each carries a band
saying so, because this product shows no number it has not measured, and a
test fails if one loses its band. See
[docs/00-project-status.md §3a](docs/00-project-status.md).

---

## Running tests

```bash
flutter test                          # everything — no device, no backend
flutter test test/features/           # domain and data logic only
flutter test test/widget/             # widget and navigation tests
flutter test --coverage
flutter analyze                       # must be clean before any commit
```

363 tests. See [test/README.md](test/README.md) for how the suite is
organised and what each group protects.

---

## Building an APK

```bash
# debug
flutter build apk --debug --dart-define=NATCO_ENV=dev

# release, split per ABI to keep the download small on cheap devices
flutter build apk --release --split-per-abi --dart-define=NATCO_ENV=prod
```

---

## Building a release

```bash
flutter build appbundle --release --dart-define=NATCO_ENV=prod
```

Keep the keystore **outside** the repository and reference it from
`android/key.properties`, which is git-ignored. Never commit a keystore or a
password. Release checklist and rollout steps:
[docs/12-deployment.md](docs/12-deployment.md).

---

## Troubleshooting

### Every `flutter` command hangs at 100% CPU, printing nothing

The SDK at `C:\Program Files\flutter` is **not writable by the current user**.
`flutter.bat` takes a lock by opening a file inside its own cache; when that
is denied it loops straight back to `:acquire_lock` with no delay, so a
permissions error is indistinguishable from a hang — no output, no `dart`
child process, CPU pinned. Use the writable copy:

```powershell
$env:FLUTTER_ROOT = "D:\flutter-sdk"
& "D:\flutter-sdk\bin\flutter.bat" test
```

### Version solving fails against Dart 3.7.2

`C:\flutter\flutter` is a stale SDK that currently wins on `PATH`. This
project needs `^3.13.2`. Check resolution order:

```powershell
Get-Command flutter -All
```

### Other symptoms

| Symptom | Cause | Fix |
|---|---|---|
| App opens on the login screen showing demo accounts in a `dev` build | `NATCO_ENV` not passed, so it fell back to `demo` | add `--dart-define=NATCO_ENV=dev` |
| "Your account is not fully set up" | Auth user exists, `users/{uid}` does not | create the profile document |
| "Your account settings could not be read" | `role` or `scope` unresolvable | check wire names against `UserRole` and `ScopeLevel` |
| Everything returns permission-denied | rules not deployed, or claims not minted | deploy rules; sign out and in to refresh the token |
| A Supervisor sees no schools | scope ids do not match the school ancestry | compare `clusterIds` against the schools' `clusterId` |
| A role change has no effect | ID token carries stale claims | the app refreshes on reconnect and resume; signing out and in is the manual path |
| `flutter build apk` fails on `google-services.json` | file missing | it is git-ignored by design; copy the environment's own |
| Gradle fails with a JDK error | wrong JDK | use JDK 17 |

---

## Security

Enforcement is **server-side**. Client-side guards hide what a user cannot
use; they are not the boundary. A rooted phone with a patched APK gets exactly
as far as the Firestore and Storage rules allow it.

Invariants no client can bypass — see
[firebase/README.md](firebase/README.md) and
[docs/04-security-model.md](docs/04-security-model.md):

| Invariant | Enforced by |
|---|---|
| Published answer keys are immutable | `answer_keys` updatable only while `DRAFT`; publishing is Functions-only |
| Machine detection is write-once | `omr_answers` machine fields must be unchanged on every update |
| Scores are not client-writable | `results`: `allow write: if false` |
| OMR ids are never reused | `omr_registry` guard document; update and delete denied |
| Student identities are not merged | `student_dedupe` guard document created in the same transaction |
| Audit logs are append-only | `audit_logs`: update and delete denied to everyone |
| Nobody reads outside their scope | every collection's read rule checks the caller's scope |
| A user cannot promote themselves | `users`: `role` and `scope` require `manageUsers` |
| Original captures cannot be altered | Storage: `allow update, delete: if false` |

Secrets: none in the repository. No service-account JSON in the Flutter
project — `.gitignore` blocks `*-service-account*.json`,
`google-services.json` and `firebase_options*.dart`. The mobile app holds only
the public Firebase client config, which is not a secret; the boundary is the
rules, not config obscurity.

---

## Privacy

The system handles children's educational data.

- Only necessary data is collected, and access is restricted by role and
  geographic scope.
- **No student name, date of birth or external code** appears in any Storage
  path, log line, crash report or export filename.
- The structured logger runs a **redaction pass** over known-sensitive keys
  before anything is emitted, so a careless `log.info(user.toJson())` cannot
  leak.
- Crashlytics receives an opaque `userId` and never PII.
- Student data is **not sent to any external AI service**.
- Retention and controlled deletion run server-side from policy in
  `app_config`, and every deletion is audited.

---

## Deployment

Rules first, then Functions, then the app — a client build must never reach a
project whose rules are not yet deployed. Environment promotion, release
checklist and rollback:
[docs/12-deployment.md](docs/12-deployment.md).

---

## Contributing

- `flutter analyze` must be clean and `flutter test` green before any commit.
  A phase does not start until the previous one's are.
- Business logic does not live in widgets. A new route cannot be registered
  without declaring the permission it requires — the guard fails closed.
- Prefer immutable models, typed errors (`Result` / `Failure`), and small
  testable functions.
- Do not write `TODO: implement later` for core functionality. If something is
  deferred, name the phase that owns it — the deferral tables in
  [docs/08-mvp-implementation-plan.md](docs/08-mvp-implementation-plan.md) are
  the pattern.
- Use **Supervisor**. Never "Coordinator". A test checks.

## Documentation

| | |
|---|---|
| [docs/](docs/README.md) | Architecture, data model, schema, security, sync, OMR pipeline, plan, deployment |
| [lib/](lib/README.md) | Code layout, layering rules, how to add a feature |
| [test/](test/README.md) | Test organisation and conventions |
| [firebase/](firebase/README.md) | Rules, indexes and what they enforce |
