# Dependency List and Rationale

Toolchain: **Flutter 3.47.2 (stable) / Dart 3.13.2**. Version constraints in
`natco_app/pubspec.yaml` are the source of truth; this document explains *why*
each dependency is present, and what was rejected.

## Runtime

| Package | Purpose | Why this one |
|---------|---------|--------------|
| `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `cloud_functions`, `firebase_crashlytics` | backend | First-party, offline-capable, and the requirement's stated preference. All are used behind our own abstractions so the choice is reversible. |
| `flutter_riverpod` | state management | Compile-time-safe dependency injection and provider overrides, which is what makes demo mode and widget tests possible without a service locator hack. Chosen over `provider` (no override ergonomics) and `bloc` (more ceremony than these screens need). |
| `go_router` | navigation | Declarative routes with a single `redirect` hook — the natural place for one fail-closed permission guard. Hand-rolled `Navigator 2.0` would put that logic in several places. |
| `freezed_annotation`, `json_annotation` | immutable models | Immutability and value equality are load-bearing here: entities cross an isolate boundary and get compared in tests. |
| `hive_ce`, `hive_ce_flutter` | local database | Typed boxes, no on-device schema migrations, fast key lookups — matching the access pattern (§6 of the offline strategy). `hive_ce` is the maintained community fork; original `hive` is unmaintained. |
| `flutter_secure_storage` | session key | The Hive box holding the cached session is encrypted with a device-bound key; the key belongs in the Keystore, not in the box. |
| `connectivity_plus` | interface state | Reports the link. |
| `internet_connection_checker_plus` | reachability | Reports whether the link goes anywhere. Both are needed — see offline strategy §7. |
| `camera` | OMR capture | Preview + still capture with resolution control. |
| `image_picker` | gallery | Required by §16. |
| `image` | pure-Dart image ops | Powers `DartOmrImageProcessor`, so the pipeline is testable on CI with no device. |
| `path_provider`, `path` | durable file paths | Images must be written to app documents storage before processing. |
| `permission_handler` | runtime permissions | Camera and storage, with a clear rationale screen. |
| `uuid` | client-generated IDs | Offline-created records must own their identity from birth; that is what makes sync idempotent. |
| `intl` | dates, numbers | Field-appropriate formatting; also the seam for localisation later. |
| `csv` | report export | §32 requires CSV first. |
| `crypto` | dedupe keys, idempotency keys | Deterministic SHA-256 for `student_dedupe` and sync receipts. |
| `package_info_plus`, `device_info_plus` | audit metadata | `deviceId` and `appVersion` are required audit fields (§26). |

## Dev

| Package | Purpose |
|---------|---------|
| `flutter_test`, `integration_test` | test harnesses |
| `flutter_lints` + project rules | static analysis |
| `build_runner`, `freezed`, `json_serializable` | code generation |
| `mocktail` | fakes without codegen; preferred over `mockito` here because it needs no `build_runner` pass for every test double |
| `hive_ce_generator` | typed Hive adapters |

## Rejected, and why

- **An OpenCV wrapper package as the primary image processor.** Evaluated
  against the seven checks in §7 of the requirements: maintenance cadence is
  uneven across the available wrappers, each adds 20–40 MB per ABI, and they
  pin NDK/CMake versions that collide with other plugins. The pipeline is
  therefore written against our own `OmrImageProcessor` interface with a
  pure-Dart implementation first and a thin native OpenCV accelerator behind
  the same interface (see [07-omr-pipeline.md](07-omr-pipeline.md) §5). The
  dependency, if it arrives, is ours and is five methods wide.
- **`google_ml_kit` / cloud OCR for the OMR ID.** Requires network or a large
  model, and the ID is a bubble grid we already sample with the same code path
  as the answers. Also: §35 forbids sending student data to external services.
- **`firebase_analytics`.** §5 permits it "only if genuinely useful and
  privacy-compliant". Nothing in the MVP needs product analytics, and the
  smallest correct amount of student-adjacent telemetry is none. Crashlytics
  (with no PII) covers diagnostics.
- **Google Drive as storage.** Explicitly forbidden as a primary store
  (Critical Rule 2). Reserved as an optional export target later.
- **`riverpod_generator`.** Extra codegen surface for syntax sugar; the
  hand-written providers here are few and explicit.

## Version policy

- Direct dependencies use caret constraints; `pubspec.lock` is committed so
  every developer and CI run resolves identically.
- Firebase packages are upgraded as a set — mixing generations produces
  link-time failures that are slow to diagnose.
- Upgrades run `flutter analyze` and the full suite before landing.
