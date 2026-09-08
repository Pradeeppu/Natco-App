# NATCO Assessment App — Architecture Plan

> Terminology note: the monitoring role is called **Supervisor**. The word
> "Coordinator" is not used anywhere in this product, its data model, its UI,
> or its documentation.

## 1. What this system is

NATCO is an **assessment data pipeline**, not an OMR scanner with a database
bolted on. The scanner is one stage of a longer chain, and every stage must be
able to prove what it did:

```
Master data → Assessment setup → Session → Capture → Quality gate →
Detection → Confidence → Human validation → Scoring → Sync → Analytics → Audit
```

The properties that drive every design decision, in priority order:

| # | Priority | What it forces |
|---|----------|----------------|
| 1 | Data integrity | Append-only evidence, versioned answer keys, no silent overwrite |
| 2 | OMR reliability | Measured accuracy, confidence-gated automation, human fallback |
| 3 | Offline reliability | Local-first writes, durable sync queue, crash-safe |
| 4 | Security | Server-enforced RBAC + geographic scope |
| 5 | Auditability | Every state transition and score change recorded |
| 6 | Field usability | Low-end Android, one-handed, large targets, plain-language errors |
| 7 | Analytics | Pre-aggregated rollups, drill-down |
| 8 | Visual polish | Last |

## 2. Layering

```
┌─────────────────────────────────────────────────────────┐
│ Presentation   Widgets, Riverpod controllers, go_router │  knows Domain
├─────────────────────────────────────────────────────────┤
│ Domain         Entities, value objects, policies,       │  knows nothing
│                repository *interfaces*, use cases       │
├─────────────────────────────────────────────────────────┤
│ Data           Repository impls, DTOs, mappers,         │  knows Domain
│                local + remote data sources             │
├─────────────────────────────────────────────────────────┤
│ Services /     Firebase, Hive, camera, OMR engine,      │  knows nothing
│ Infrastructure logger, connectivity, clock, uuid        │  about features
└─────────────────────────────────────────────────────────┘
```

Rules enforced by review and by `analysis_options.yaml`:

- **Domain is pure Dart.** No `package:flutter`, no `package:firebase_*`. This
  is what makes the scoring engine, the confidence classifier, and the
  permission matrix unit-testable without a device or an emulator.
- **Presentation never touches a data source.** It talks to a repository
  interface through a Riverpod provider.
- **Business logic never lives in a widget.** Widgets read state and dispatch
  intents.

### Why the backend stays replaceable

Section 5 of the requirements asks for Firebase but demands that Supabase (or
anything else) can be introduced later. Every backend touchpoint is expressed
as a domain-layer abstract class:

```dart
abstract interface class AuthService { ... }        // core/services/auth
abstract interface class RemoteDatabase { ... }     // data/remote
abstract interface class RemoteFileStore { ... }    // data/remote
abstract interface class CrashReporter { ... }      // core/services
```

Firebase lives behind `FirebaseAuthService`, `FirestoreDatabase`,
`FirebaseFileStore`. Swapping backends means writing new implementations and
changing one composition-root file (`app/config/service_locator.dart`) — not
touching any feature.

A second consequence, useful immediately: `InMemoryAuthService` +
`InMemoryDatabase` let the whole app run, and the whole test suite pass,
with no Firebase project configured. That is how `--dart-define=NATCO_ENV=demo`
works.

## 3. Folder structure

```
natco_app/
├── lib/
│   ├── main.dart                      # bootstrap: env → services → runApp
│   ├── app/
│   │   ├── app.dart                   # root widget, theme + router wiring
│   │   ├── router.dart                # declarative routes + role guards
│   │   ├── theme.dart                 # Material 3 light/dark
│   │   └── config/
│   │       ├── app_config.dart        # env-specific configuration object
│   │       ├── app_environment.dart   # dev | staging | prod | demo
│   │       ├── feature_flags.dart
│   │       ├── scanner_thresholds.dart# calibratable OMR thresholds
│   │       └── service_locator.dart   # composition root
│   │
│   ├── core/
│   │   ├── constants/                 # collection names, route paths, limits
│   │   ├── errors/                    # Failure hierarchy, error mapping
│   │   ├── utils/                     # Result<T>, clock, id generation
│   │   ├── services/                  # logger, connectivity, crash reporter,
│   │   │                              #   auth service abstraction, device info
│   │   ├── widgets/                   # shared UI: states, buttons, banners
│   │   └── network/                   # connectivity-aware execution helpers
│   │
│   ├── features/
│   │   ├── auth/                      # login, session, roles, permissions
│   │   ├── dashboard/                 # role-specific home dashboards
│   │   ├── schools/                   # state/district/cluster/school master
│   │   ├── students/                  # student master + enrollments
│   │   ├── assessments/               # assessments, questions, answer keys
│   │   ├── assessment_sessions/       # session lifecycle
│   │   ├── omr_capture/               # camera + gallery + quality gate
│   │   ├── omr_processing/            # detection pipeline orchestration
│   │   ├── omr_validation/            # human validation queue
│   │   ├── results/                   # scores, question-level results
│   │   ├── analytics/                 # drill-down dashboards
│   │   ├── reports/                   # CSV export (PDF/Excel later)
│   │   ├── sync/                      # queue, retry, conflict resolution
│   │   └── settings/                  # profile, diagnostics, calibration
│   │
│   └── data/
│       ├── local/                     # Hive boxes, local DAOs
│       ├── remote/                    # RemoteDatabase / RemoteFileStore
│       └── repositories/              # cross-feature repository impls
│
├── test/                              # unit + widget tests, mirrors lib/
├── integration_test/                  # end-to-end workflow tests
└── android/                           # Android host project
```

Every feature folder is:

```
features/<name>/
├── data/          dto/ , datasource/ , repository/
├── domain/        entity/ , repository/ (interface) , usecase/
└── presentation/  screen/ , widget/ , controller/
```

## 4. State management

`flutter_riverpod` with code-free providers (no generated `riverpod_annotation`
for now, to keep the build_runner surface small — only `freezed` and
`json_serializable` run through it).

- **Repository providers** are overridden in tests and in demo mode.
- **Controllers** are `AsyncNotifier` / `Notifier` subclasses holding immutable
  state built with `freezed`.
- **No `BuildContext` in controllers**, so they are testable headlessly.

## 5. Concurrency model

OMR work is CPU-bound and must never block the UI thread (Critical Rule 13).

```
UI isolate                          Worker isolate
──────────                          ──────────────
capture JPEG bytes  ── Isolate.run ──►  decode
                                        quality metrics
                                        marker detection
                                        perspective warp
                                        bubble sampling
                    ◄─── result ──────  classification
persist + render
```

`Isolate.run` (Dart 3) is used rather than a hand-rolled `ReceivePort`, because
the pipeline is a single request/response per sheet. Anything that has to touch
platform APIs (OpenCV via a native bridge) is invoked from the worker through a
platform channel wrapper that is safe to call off the root isolate, or, if that
proves unreliable on low-end devices, moved wholly into native code and
invoked once per sheet.

## 6. Error handling

Two-layer approach.

1. **Typed failures in the domain.** Every repository returns
   `Result<T, Failure>` — never throws for expected conditions. `Failure` is a
   sealed hierarchy (`NetworkFailure`, `AuthFailure`, `PermissionFailure`,
   `ValidationFailure`, `ConflictFailure`, `StorageFailure`,
   `OmrProcessingFailure`, `UnexpectedFailure`).
2. **Human messages in the presentation.** `Failure.userMessage` is written for
   a teacher standing in a classroom, never for a developer.
   `FirebaseException: permission-denied` becomes
   *"You do not have access to this school."* Diagnostic detail goes to the
   structured logger and Crashlytics, not to the screen.

Every critical failure path does four things, in order: **preserve local data →
show a plain message → log diagnostics → offer a recovery action.**

## 7. Offline-first posture

The app is **local-first for everything a field user does**. A teacher's write
lands in Hive and in the sync queue in the same transaction-like step; the
network is an eventual consistency detail, never a precondition. See
[06-offline-sync-strategy.md](06-offline-sync-strategy.md).

## 8. Testing strategy

| Layer | Tooling | What is covered |
|-------|---------|-----------------|
| Domain | `flutter_test` (pure Dart) | scoring, answer-key comparison, confidence classification, duplicate detection, session/OMR state machines, permission + scope logic, sync retry policy |
| Data | fakes over abstractions | repository mapping, queue durability, conflict detection |
| Presentation | widget tests | login, dashboards, capture states, validation screen, results |
| End-to-end | `integration_test` | full assessment workflow, offline capture, reconnect + sync, duplicate OMR, ambiguous validation, role restrictions |
| OMR accuracy | golden dataset harness | per-question / per-sheet accuracy, FP/FN, blank + multi-mark detection (see [10-omr-calibration-testing.md](10-omr-calibration-testing.md)) |

OMR accuracy is **measured, never asserted**. No accuracy figure appears in
any document unless it was produced by the harness against a labelled dataset.

## 9. Build phases

Implementation follows the twelve phases in
[08-mvp-implementation-plan.md](08-mvp-implementation-plan.md). Phase 1
(foundation: architecture, theme, routing, auth, roles) is complete; each
later phase begins only after the analyzer and the test suite are clean.
