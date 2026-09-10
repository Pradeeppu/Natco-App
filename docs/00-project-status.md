# Project Status and Runbook

The single entry point: where the build is, how to run it, and what is left.
The numbered documents that follow this one carry the depth; this one carries
the state.

**Status: 10 of 12 phases complete and tested; phase 5's code is complete and
untested on real hardware; phases 6 and 12 are blocked on a physical device
and real scanned sheets.**
`flutter analyze` clean. **576 of 576 tests passing.** A release APK builds
and is signed with a **real release key**, verified with `apksigner` — see
[§8](#8-building-a-release-apk).

No OMR accuracy figure appears anywhere in this repository, because none has
been measured yet (Critical Rule 14).

---

## 1. Running it

The app runs with **no Firebase project and no network**. Demo mode wires the
real router, the real permission matrix and the real controllers over
in-memory services.

```bash
cd d:\natco_app
flutter pub get
flutter run --dart-define=NATCO_ENV=demo
```

Password for every demo account is `natco1234`; the login screen lists them as
tappable chips.

| Demo sign-in | Role | Scope it demonstrates |
|---|---|---|
| `superadmin@natco.demo` | Super Admin | Global — the only role with unrestricted reach |
| `assessmentadmin@natco.demo` | NATCO Admin | One state |
| `supervisor@natco.demo` | Supervisor | Two clusters — can also onboard PST Teachers and edit students in-scope |
| `teacher@natco.demo` | PST Teacher | One school, Grade 5 Section A only — can register students in their own class |
| `scanner@natco.demo` | Scanner Operator | Two schools, no student list |
| `viewer@natco.demo` | Viewer | Read-only |

Seeded demo data: 1 state, 2 districts, 3 clusters, 5 schools, 100 students, 3
assessments (one active with a published key, one closed with a corrected
key, one draft), 1 in-progress session, 5 OMR submissions spanning every
validation scenario (clean, ambiguous, faint mark, erased answer, multiple
mark) — all sharing ids across features so nothing can drift apart.

### Verifying

```bash
flutter analyze      # must be clean
flutter test         # 576 tests, no device and no backend required
```

### Building

```bash
flutter build apk --release --split-per-abi --dart-define=NATCO_ENV=prod
flutter build appbundle --release --dart-define=NATCO_ENV=prod
```

Environments are `demo`, `dev`, `staging`, `prod`. An unrecognised value falls
back to `demo`, never to `prod`. Firebase setup: [11-environment-setup.md](11-environment-setup.md).

---

## 2. Two environment traps on the current machine

Both are written up with symptoms in
[11-environment-setup.md](11-environment-setup.md#troubleshooting).

1. **Every `flutter` command hangs at 100% CPU, printing nothing.** The SDK at
   `C:\Program Files\flutter` is not writable by the current user.
   `flutter.bat` acquires a lock by opening a file inside its own cache and,
   when that is denied, loops back to `:acquire_lock` with no delay — so a
   permissions error is indistinguishable from a hang. A writable copy is at
   `D:\flutter-sdk`:

   ```powershell
   $env:FLUTTER_ROOT = "D:\flutter-sdk"
   & "D:\flutter-sdk\bin\flutter.bat" test
   ```

2. **A stale SDK shadows the right one.** `Get-Command flutter -All` lists
   every match in order if this recurs.

---

## 3. What is built

### Phase 1 — Foundation ✅

- Composition root with four environments; every backend touchpoint is an
  interface with a Firebase and an in-memory implementation.
- 6 roles, a compile-time permission matrix, `AccessScope` with
  hierarchy-aware membership, and `Authorization` as the single decision point.
- Auth: sign-in, offline session restore from an expiring encrypted cache,
  server-authoritative revalidation on reconnect.
- Every route declares a required permission, behind a fail-closed guard.
- Sealed `Failure` hierarchy, `Result<T>`, redacting logger, Material 3 theme.
- `firebase/firestore.rules` and `firebase/storage.rules`.

### Phase 2 — Master data ✅

- State → District → Cluster → School → Student, behind
  `SchoolHierarchyRepository` and `StudentRepository`, each with an in-memory
  and a Firestore data source composed by one audit-logging repository.
- Students: paginated, searchable, scope-filtered, with create and inline edit.
- CSV import previewing "N ready / M rejected", checking duplicates within the
  file and against registered students.
- `PagedListController` — debounced search, infinite scroll, stale-response
  dropping — the shared base every paginated list in the app builds on.

### Users — account management (not one of the 12 numbered phases; added per a
direct requirements change) ✅

Built to close a specific request: **Supervisors need to onboard their own PST
Teachers**, and the existing permission matrix had no way to grant that
without also granting a Supervisor the ability to mint a second Super Admin.

- Renamed `ASSESSMENT_ADMIN`'s display name to **NATCO Admin** (wire name
  unchanged — it's in stored claims and security rules).
- New `Permission.manageUsers`/`viewUsers`, granted to Super Admin and
  Supervisor.
- **The escalation guard**: `UserRole.assignableRoles` — a second matrix,
  independent of the permission matrix, answering "which roles may this role
  create". A Supervisor's set is `{PST Teacher}` only. `manageUsers` alone
  would have let a Supervisor create a Super Admin; this is what stops that.
- `UserProvisioningPolicy` — pure-Dart, checks both the role grant and that a
  granted scope is actually inside the actor's own scope (resolved through
  real school ancestry, not assumed).
- PST Teacher gained `manageStudents` (register a student in their own class)
  and `exportReports` (report cards for their own students) — deliberately
  *not* `importStudents`, since bulk CSV error-checking is a different risk
  profile than one row.
- Full `UserRepository` (list/get/create/update/deactivate — never delete, so
  every audit entry and captured sheet naming a user stays answerable),
  `ScopeEditor` widget (builds an `AccessScope` from real hierarchy picks, no
  free-typed ids per requirement §10), Users list + detail + create screens.

### Phase 3 — Assessments ✅

- `Assessment`, `AnswerKey` (versioned, immutable once published),
  `AssessmentAssignment` entities; `AnswerKeyPolicy` enforces Critical Rule 7
  end to end: a published key cannot be edited, a correction creates version
  *n+1* with a mandatory reason and marks *n* superseded, and a key cannot
  publish while incomplete.
- Real screens: assessments list/detail/create, the answer-key editor (grid
  entry across all questions), full version history on the detail screen.
- `AssessmentRepositoryImpl` composes the data source with the policy and
  audit logging (`ANSWER_KEY_PUBLISHED`, `ANSWER_KEY_CORRECTION_STARTED`, …).

### Phase 4 — Offline assessment sessions ✅

- `AssessmentSession` with a one-way status machine
  (`READY → IN_PROGRESS → COMPLETED`/`ABANDONED`) and a per-student roster
  tracking attendance.
- **Local-first store**: `HiveAssessmentSessionStore` persists sessions as
  JSON maps in a Hive box (no code-generated `TypeAdapter` — deliberately, so
  a shape change through later phases is never an on-device schema
  migration), matching before an in-memory store for demo/tests.
- The session pins the answer-key version in force at start — a correction
  published mid-sitting cannot silently change what an already-captured sheet
  is scored against.
- Real session screen: roster, attendance marking, capture-progress summary.

### Phase 7 — OMR Validation ✅

The point where a person is allowed to overrule a machine, and the point
Critical Rule 3 ("machine evidence is never overwritten") had to become code
rather than a comment.

- `OmrSubmission`, `OmrAnswer`, `ImageQualityReport` entities
  (`features/omr_processing/`) matching the security rules' field-level
  invariants exactly — `machineAnswer`/`machineConfidence`/`machineStatus`/
  `optionScores` have no `copyWith` path that can touch them once written.
  `OmrAnswer.withValidation()` is the *only* way a human decision is applied,
  and it has no parameter that could reach a machine field.
- `OmrValidationPolicy`: the fixed set of choices a validator may record
  (`A`/`B`/`C`/`D`/`Blank`/`Multiple`), and the completeness check that gates
  a submission from reaching `SCORED` while anything is still flagged.
- Append-only `OmrValidationRecord` log, separate from the answer itself, so
  a re-validation never erases the first decision.
- Real queue screen (scope-filtered, exactly like every other list) and
  detail screen — the cropped-bubble-row visualisation and per-option
  darkness bars are real, driven by the actual `optionScores` on the answer,
  not sample data.
- **22 tests**, including a demo dataset spanning every scenario: a clean
  high-confidence sheet, a genuinely ambiguous two-way coin-flip, a faint
  mark, an erased/re-marked answer, and a multiple mark.

### Phase 8 — Scoring ✅

- `AssessmentResult` — named that, not the docs' bare "Result", because this
  codebase's `Result<T>` is the universal success/failure wrapper and a
  second class named `Result` would shadow it everywhere.
- `ScoringEngine`: pure Dart, refuses to run at all while any answer still
  needs validation, computes **both** a final score (against the validator's
  decision) and a machine-only preview score in the same pass, and reports
  exactly which questions a validator overruled — the "discrepancy" the demo
  results screen surfaces rather than silently reconciling.
- Negative marking, blank handling (never penalised), and a missing key entry
  refuses to score rather than silently marking a question wrong.
- Re-scoring **supersedes** — a new `AssessmentResult` is written and the old
  one gets `supersededBy` set; no scored field is ever mutated in place
  (Critical Rule 5), proven by a test that scores the same submission twice
  and checks the first row is untouched.
- `ResultRepository.ensureScored()` — call it once per assessment (the real
  results screen does, on open) and it scores every ready, not-yet-scored
  submission and skips what's already scored; it is not a re-score sweep.
- Real results list (with class average/high/low) and per-student
  question-by-question screen, machine vs. final columns kept visibly apart.
- **13 tests** covering the scoring rule itself and the full repository flow
  against the demo data.

### Phase 9 — Synchronization ✅ (one step short by design, not oversight)

Built by a second agent working in parallel this session, then finished in
this pass. What's real and tested:

- `SyncQueueEntry`, exponential backoff with jitter, dependency-ordered
  draining (`session → omr_submission → omr_answers → omr_validations →
  file uploads`), error classification into transient/permission/validation/
  conflict.
- `SyncConflictPolicy` — Keep Server / Keep Local / Create Review Case, gated
  on `Authorization.can(Permission.resolveSyncConflict)` (not a hardcoded role
  check) so anyone without that permission may only escalate, never choose a
  side, on anything touching scores, validations or answers.
- Real `/sync` screen: queue, retry, conflict cards, all live.
- **The core exit criterion is proven, not just asserted**: a test simulates
  a server that processes a write and then drops the connection before the
  client hears back, and proves the retry short-circuits on the idempotency
  key rather than writing a second record.
- **The crash reconciler now does 3 of 4 recovery steps**: resets a stuck
  `UPLOADING` entry, resets a crashed-mid-process `PROCESSING` submission back
  to `CAPTURED`, and — the one that matters most — marks a submission
  `UNREADABLE_EVIDENCE_MISSING` and audits it when its image file is gone,
  rather than losing that fact silently. The fourth step (re-enqueuing an
  orphaned entity with no queue record) is genuinely not buildable yet: no
  code path in this app writes an entity without also writing its queue entry
  in the same step, because that write-path only exists once phase 5's
  capture flow does — there is nothing today that could produce an orphan to
  re-enqueue.
- **A retry-attempt cap** (`kMaxAutoRetryAttempts = 8`): an entry that keeps
  failing stops auto-retrying and surfaces under "Retry Failed Uploads"
  rather than backing off forever. Proving this cap actually works surfaced
  two real bugs, both now fixed: the drain filter treated a stopped
  (`FAILED`) entry as retry-eligible whenever its backoff had merely elapsed
  — meaning the very next automatic sync (periodic timer, reconnect, app
  resume) would silently retry something that had already surfaced to a
  person — and `SyncQueueEntry.copyWith` had no way to actually clear a
  nullable field to `null`, so "reset this entry" would have silently kept
  its stale error and backoff timestamp. Both fixed; a test proves the cap
  survives repeated automatic syncs and that the explicit retry action still
  works with a genuinely fresh attempt count.

### Phase 10 — Analytics ✅

- `QuestionAnalytics` and `AssessmentAnalyticsSummary`, computed **live** from
  the same real `AssessmentResult`/`OmrAnswer` records the results screen
  already shows — deliberately not a separate cached rollup a second
  implementation could let drift, which is what makes "metrics reconcile
  against raw results" (the phase's exit criterion) true by construction. A
  Cloud-Function-maintained rollup (`question_analytics`/`scope_analytics`,
  already reserved in the schema) is the right answer at real scale — this
  project's own words are "a district dashboard never fans out over a
  hundred thousand answer documents from a phone" — and the Firestore
  implementation here reads exactly that, compiled but unexercised like every
  other Firestore path in this app.
- Real screen: scope summary (scored/expected/completion/average/high/low),
  per-question performance bars — reads `assessmentId` from the query string
  via a new "View analytics" button on the assessment detail screen.
- Scope-filtering is proven by test, not assumed: a cluster-scoped caller's
  summary excludes a school outside their clusters.

### Phase 11 — Reports ✅

All nine report types from requirement §32, each a real CSV built from real,
scoped records — student result, school/cluster/district summary, assessment
summary, question analysis, OMR processing, validation history, and sync
failures (the one type that is device-local rather than scope-filtered, like
the sync queue itself). Every export writes one `REPORT_EXPORTED` audit entry
naming the row count and column names — never a value from a row, which is
exactly where a student's name could otherwise leak into the audit log.
Filenames are `{reportType}_{timestamp}.csv`, carrying no student name or
other personal identifier (Critical Rule 11).

**Deliberately not built**: writing the CSV to a shareable file or a share
sheet. That needs `path_provider`'s platform channel, which — like camera
access — cannot be verified without a device in this environment, so the
reports screen shows the generated content in-app rather than claim a save
succeeded that was never actually exercised.

### Phase 5 — OMR capture ⚠️ code complete; unverified on real hardware

Every piece of this phase is now wired to real repositories and real device
APIs. What is genuinely built:

- **`ImageQualityAnalyzer`**: the actual image-quality gate, computing real
  blur (variance of Laplacian), brightness, contrast (5th-95th percentile
  luminance spread) and shadow deviation (max 4x4-block deviation) from
  decoded image bytes, checked against `ImageQualityThresholds` (already
  defined in phase 1's `scanner_thresholds.dart`). Deliberately does **not**
  attempt sheet or marker detection — that needs phase 6's homography stage,
  and the gate has to run *before* that pipeline even starts, on a photo
  nothing has confirmed is a legible sheet yet. Tested against synthetic
  bitmaps built in the test itself (a flat gray image, a sharp checkerboard,
  one deliberately shadowed corner) — no real photo needed to prove the
  math is right.
- **`OmrImageWriter`**: writes captured bytes durably to disk
  (`flush: true`, so the write completes before the call returns) at the
  path `StoragePaths.omrOriginal` already defines. Takes the documents root
  directory as a parameter rather than calling `path_provider` itself, so
  the whole thing is testable with a fake file system — a real caller adds
  exactly one line, `(await getApplicationDocumentsDirectory()).path`.
- **`OmrValidationRepository.createSubmission`**: the one create path for a
  freshly captured sheet. Rejects a reused `omrId` — an in-memory map check
  for demo/tests, a Firestore transaction guarded by `omr_registry/{omrId}`
  for real — matching the same guard-document pattern `student_dedupe`
  already uses (Critical Rule 7). Audits `OMR_CAPTURED`, and
  `OMR_QUALITY_OVERRIDDEN` separately when a capturer forces past a failed
  gate, so a reviewer can find every override without reading every capture.
- **The real capture screen** (`OmrCaptureScreen`), reading `sessionId` from
  the query string exactly like `ResultsScreen` reads `assessmentId`:
  student picker from the session's pending roster, a manual OMR-ID field
  (phase 6's automatic bubble-grid read does not exist yet, so a person
  supplies it), capture-or-choose-from-gallery via `image_picker`, the real
  quality gate rendered from `ImageQualityAnalyzer`'s actual verdict, "Use
  anyway" gated by `Permission.overrideQualityGate` and recorded with a
  reason, then the durable write followed by `createSubmission` and
  `SessionRepository.attachOmr` in that order — so a crash between them loses
  at most an unlinked database row, never the photographed evidence.
  `AssessmentSessionScreen`'s "Capture next OMR" button now passes
  `?sessionId=`.
- Deliberately **not** a custom live camera preview
  (`CameraController`/`package:camera`). `image_picker`'s camera source hands
  the whole capture UI to the device's own camera app and hands back a file
  — the same photo, one less custom camera lifecycle (orientation, focus,
  disposal) to get wrong with no device here to catch a mistake in it. A
  future iteration can build a live preview with framing guides if that
  turns out to matter more than this simplification costs.

**What is genuinely still open, and why it can only be closed on a device**:
whether the device's camera app, `image_picker`'s plugin channel and the
`CAMERA` runtime permission actually behave together the way the code
assumes — a real photo through the real hardware path has never been taken.
The Android manifest and iOS `Info.plist` now declare the permission/usage
strings this needs; nobody has run the app on a phone to confirm it. Every
widget test that pumps `/omr/capture?sessionId=...` exercises the real form
(student picker, OMR-ID field, quality-gate rendering, save button) against
the demo session — that proves the screen renders and does not crash under
test, not that the camera hardware path works.

### Preview-only — not yet built behind real data

| Screen | Route | Phase |
|---|---|---|
| Scan result with confidence breakdown | `/omr/review/:omrId` | 6 |
| Scanner calibration and accuracy harness | `/settings/calibration` | 6 |

Each carries an unmissable "every figure below is made up" band
(`core/widgets/preview_kit.dart`), enforced by
`test/widget/preview_labelling_test.dart` — that test fails if a preview
screen loses its band, or if a real screen wrongly carries one. Calibration
is a deliberate exception: it shows an empty state, not an invented accuracy
figure, because none has been measured (Critical Rule 14).

---

## 4. What is left

| # | Phase | The gate | Why it's not fully done here |
|---|---|---|---|
| 5 | OMR capture | Image on disk before any processing; each quality failure has its own message; a kill mid-capture loses nothing | All of it is built and wired to real repositories (see above) — what's left is running it on a real phone once to confirm the camera/permission plumbing behaves the way the code assumes |
| 6 | OMR engine | Golden-dataset harness reports **measured** accuracy; an upside-down sheet is detected, not silently inverted | Needs real printed, scanned answer sheets with known-correct answers. Critical Rule 14 forbids inventing this number, so there is nothing to build against yet |
| 12 | Hardening | Rules pass a deny-by-default review; performance budgets met on the reference device | Blocked on a physical device regardless of code state |

Every remaining gap needs a physical device, real camera hardware, or real
scanned answer sheets — none of which exist in this environment.

---

## 5. Where the code lives

```
lib/
├── app/         composition root, router, guards, theme, shell
├── core/        Result, Failure, logger + redaction, pagination, widgets
├── features/
│   ├── auth · schools · students · users · dashboard      (built)
│   ├── assessments · assessment_sessions                  (built)
│   ├── omr_processing · omr_validation · results          (built — phases 7-8)
│   ├── sync                                                (partial — phase 9)
│   ├── omr_capture                                         (built — phase 5)
│   ├── omr_processing/presentation (scan-result screen)    (preview — phase 6)
│   └── analytics · reports · settings                      (preview — phases 10-11)
└── data/        local (Hive) and remote (Firebase) implementations
```

Every feature carries `data/ · domain/ · presentation/`. The domain layer is
pure Dart with no Flutter and no Firebase imports — that is what makes
scoring, the validation policy and the permission matrix testable without a
device. Architecture in full: [01-architecture.md](01-architecture.md).

---

## 6. Rules the build does not bend

Enforced in code and in the security rules, not merely written down.

| Rule | Enforced by |
|---|---|
| The monitoring role is **Supervisor**; "Coordinator" appears nowhere | A test scans the source tree on every run |
| Machine readings are evidence, never overwritten by a human decision | `OmrAnswer.withValidation()` has no parameter that reaches a machine field; the Firestore rule refuses the same fields client-side |
| Published answer keys are immutable; a correction is a new version | `AnswerKeyPolicy` + Firestore rules; publishing is Functions-only |
| No client of any role writes a score | `results`: `allow write: if false`; `ScoringEngine` output only ever reaches storage through the repository |
| A re-score supersedes, never mutates, a prior result | `AssessmentResult.copyWithSupersededBy` is the only mutation the entity permits |
| A submission cannot reach `SCORED` while anything needs validation | `OmrValidationPolicy.checkCanScore`, re-checked by `ScoringEngine` itself, not just the caller |
| A Supervisor cannot escalate their own reach by creating a user | `UserRole.assignableRoles` — independent of, and narrower than, `manageUsers` |
| Student identities are never silently merged | `student_dedupe` guard document + Unicode-safe key |
| Audit logs are append-only, Super Admin included | Rules deny update and delete |
| Nobody reads outside their geographic scope | Every collection's read rule, plus scope-derived queries |
| The app shows no number it has not measured | Calibration shows an empty state; every preview screen carries a labelled band, enforced by a test |
| A sync conflict is never auto-resolved | Three explicit choices only (Keep Server / Keep Local / Create Review Case); field roles may only escalate |

---

## 7. Known gaps

Honest and current:

1. **Sync reconciler's 4th step is deliberately deferred, not missed.**
   Re-enqueuing an orphaned entity (a non-terminal entity with no queue
   record) needs phase 5's capture flow to exist first — nothing today
   writes an entity without also writing its queue entry in the same step, so
   there is no code path that could produce an orphan to re-enqueue yet. The
   other three steps (reset stuck `UPLOADING`, reset a crashed `PROCESSING`
   submission, mark evidence missing) are built and tested.
2. **Fixed since the last pass**: `SyncQueueEntry.operation`/`entityType` are
   now `SyncOperation`/`SyncEntityType` enums, not bare strings; and
   `SyncConflictPolicy` now checks
   `Authorization.can(Permission.resolveSyncConflict)` rather than a
   hardcoded `UserRole` comparison, matching every other gate in the app.
3. **Phase 5's camera path has never run on a real device.** The code is
   complete and the demo flow is exercised by widget tests, but nobody has
   installed the app on a phone and taken an actual photo through it yet.

---

## 8. Building a release APK

```bash
flutter build apk --release --dart-define=NATCO_ENV=demo
```

Verified working end to end on this machine. Two environment-specific fixes
were needed and are already applied — both are one-time, machine-level
issues, not anything wrong with the project:

1. **Kotlin's incremental compiler crashes if the pub cache and the project
   sit on different Windows drive letters** (here: pub cache on `C:\`,
   project on `D:\`) — it tries to express a plugin's source path relative to
   the build directory, and a relative path across two drive roots is
   undefined on Windows. Fixed by disabling incremental compilation
   (`kotlin.incremental=false` in `android/gradle.properties`); the only cost
   is a slower from-scratch Kotlin compile, not a functional change.
2. **`flutter_secure_storage` and `permission_handler_android` both require
   compiling against Android SDK 37+**, one version ahead of the Flutter
   template's default (36). Fixed by setting `compileSdk = 37` explicitly in
   `android/app/build.gradle.kts`.

The resulting APK is signed with a **real release key**
(`android/keystore/natco-release.jks`, alias `natco_release`), not the debug
key — `android/app/build.gradle.kts` reads `android/key.properties` and picks
the real `signingConfigs.release` whenever that file exists, falling back to
the debug key only on a checkout that has neither (so `flutter run --release`
still works with no signing set up). Confirmed with the tool that actually
reads an APK's v2/v3 signature — `apksigner verify --print-certs`, at
`<Android SDK>/build-tools/<version>/apksigner.bat` — not `keytool
-printcert -jarfile`, which reports "Not a signed jar file" against a
correctly-signed APK because it only understands the older JAR signing
scheme.

**Both the keystore and `key.properties` are gitignored and exist only on
this machine.** They are never committed, shared in chat or email, or backed
up automatically. If this keystore is lost, no future release can be signed
as an update to this same app identity — back it up somewhere secure and
private, deliberately, before this machine's disk is the only copy.
