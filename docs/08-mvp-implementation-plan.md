# MVP Implementation Plan

Twelve phases (§58). A phase starts only when the previous one's analyzer and
test suite are clean. Each phase lists its **exit criteria** — the check that
says "this is done", not "this compiles".

| Phase | Scope | Exit criteria | Status |
|-------|-------|---------------|--------|
| **1. Foundation** | project, architecture, theme, routing, config, auth, role + scope system, security rules, logging, error model | login works against Firebase and in demo mode; every route guarded; permission matrix unit-tested for all 6 roles; `flutter analyze` clean; test suite green | **complete** |
| **2. Master data** | states, districts, clusters, schools, students, CSV import, search, pagination | hierarchy CRUD within scope; duplicate student rejected with a named reason; 2 000-student school scrolls without loading all rows | **complete** |
| **3. Assessments** | assessments, questions, answer keys (versioned), assignments | key v1 publishes and becomes immutable; a correction produces v2 with a reason and supersedes v1 | **complete** |
| **4. Offline assessment** | Hive boxes, pre-download, session lifecycle, reconciler | session survives force-stop; airplane-mode run completes end to end | **complete** |
| **5. OMR capture** | camera, gallery, quality gate, durable image write, manual ID entry | image on disk before any processing; each quality failure gives its own message; kill-during-capture loses nothing | **complete** |
| **6. OMR engine** | template JSON, markers, homography, rotation, sampling, classification, confidence | pipeline runs in a worker isolate; golden dataset harness reports measured accuracy; upside-down sheet is detected, not silently inverted | **complete** |
| 7. Validation | review queue, per-question validation UI, audit trail | machine fields provably unchanged after validation; a submission needing validation cannot reach `SCORED` | next |
| 8. Scoring | scoring engine, results, question-level results | client and server scores agree on the dataset; re-score supersedes instead of mutating | |
| 9. Synchronization | queue drain, ordered upload, idempotency, retry, conflicts, sync dashboard | kill-during-upload produces exactly one server record; conflict shows both versions and never auto-resolves | |
| 10. Analytics | rollups, state→student drill-down, question analytics | metrics reconcile against raw results; a Supervisor sees only their scope | |
| 11. Reports | CSV for all nine report types | every export audited; no student name in any filename | |
| 12. Hardening | security review, performance, offline soak, OMR accuracy, crash testing, release | rules pass a deny-by-default review; budgets in §7 met on the reference device | |

## MVP definition (§59)

The MVP is complete when this runs end to end, with the OMR capture half done
on a device in airplane mode:

```
Admin creates school → student → assessment → answer key
  → Teacher logs in → selects school + assessment → starts session
  → captures OMR → image validated → scanned → student identified
  → answers detected → ambiguous flagged → human validates
  → score calculated → original image stored → result stored
  → data syncs → dashboard updates
```

## Phase 1 — what was built

Delivered in `natco_app/`:

- **Composition root** (`app/config/service_locator.dart`) with four
  environments (`dev`, `staging`, `prod`, `demo`) selected by
  `--dart-define=NATCO_ENV`. `demo` runs the full app on in-memory services
  with no Firebase project, which is also how the widget tests run.
- **Replaceable backend**: `AuthService`, `SessionStore`, `CrashReporter`,
  `AuditSink`, `Clock`, `IdGenerator` are all abstract; Firebase and in-memory
  implementations sit behind them.
- **Role + scope system**: 38 permissions, a compile-time role→permission
  matrix, `AccessScope` with hierarchy-aware membership tests, and
  `Authorization` as the single decision point used by both the router and the
  UI.
- **Auth feature**: login screen with field validation and plain-language
  errors, `SessionController` (`AsyncNotifier`), offline session restore from
  an expiring cached record, sign-out that clears local session state.
- **Routing**: 22 declared routes, each carrying its required permission, with
  a fail-closed guard and intended-location preservation across login.
- **Role-aware shell**: bottom navigation filtered by permission, so a teacher
  sees five destinations and a Super Admin sees ten.
- **Core**: sealed `Failure` hierarchy with user-facing messages,
  `Result<T>`, a structured logger with a redaction pass, Material 3 theme
  (light + dark) with status-colour semantics, and shared state widgets.
- **Security rules**: `firebase/firestore.rules` and `firebase/storage.rules`
  enforcing the invariant table in [04-security-model.md](04-security-model.md).
- **Tests**: unit tests for the permission matrix, scope membership, session
  state, route guards, failure mapping and log redaction; widget tests for
  login and the role-filtered dashboard shell.

### Deliberately deferred (not "TODO")

These are absent because they belong to a later phase, and each has a named
home:

| Deferred | Phase | Where it lands |
|----------|-------|----------------|
| Firestore repositories for master data | 2 | `data/remote/firestore_database.dart` |
| Answer-key versioning UI and Functions | 3 | `features/assessments/` |
| Hive boxes and the reconciler | 4 | `data/local/` |
| Camera, quality gate | 5 | `features/omr_capture/` |
| Detection pipeline | 6 | `features/omr_processing/` |
| Validation queue | 7 | `features/omr_validation/` |
| Scoring engine | 8 | `features/results/domain/` |
| Sync engine | 9 | `features/sync/` |
| Analytics rollups | 10 | `features/analytics/` |
| CSV exporters | 11 | `features/reports/` |

Phase-1 screens for those features exist as guarded placeholders that state
which phase implements them — a route that resolves and says so is more honest
than a route that 404s or a `TODO` buried in a widget.

## Phase 2 — what was built

Delivered in `natco_app/`:

- **Pagination primitive** (`core/utils/page.dart`): `PageRequest`/`Page<T>`,
  cursor-based rather than offset-based, shared by every list method in the
  app. No screen and no repository method returns a bare, unbounded `List<T>`.
- **Hierarchy domain**: a unified `GeoNode` entity (`HierarchyLevel`-tagged)
  for State/District/Cluster, and a dedicated `School` entity carrying the
  fields no other level needs (address, grades, mediums, a unique
  `schoolCode`). `SchoolsRepository` defines scope-aware, paginated reads at
  every level plus ancestry-validating creates.
- **Student domain**: `Student` (with a `dedupeKey` derived from school + name
  + grade + section + date of birth), `Gender`, and `StudentsRepository` with
  scope-aware paginated listing, single-student reads, and an
  `importStudents` batch path that reports per-row outcomes rather than
  succeeding or failing atomically.
- **CSV import**: `StudentCsvImporter`, a pure, persistence-free parser
  (`package:csv` v8) that turns raw CSV text into typed rows and per-row parse
  errors before anything touches a repository — a malformed row never reaches
  the dedupe check.
- **Duplicate rejection with a named reason**: a second student write for the
  same school/name/grade/section/date-of-birth combination is refused with the
  colliding record's own name, grade and section in the failure — never
  silently merged, never a bare "duplicate" with no way to tell which one.
- **In-memory implementations**: `InMemorySchoolsRepository` and
  `InMemoryStudentsRepository`, seeded synchronously (`seedState`/
  `seedDistrict`/`seedCluster`/`seedSchool`/`seedStudent`) so demo mode and
  every widget test share one deterministic, scope-correct dataset — the same
  posture as Phase 1's in-memory auth service.
- **Firestore implementations**: `FirestoreSchoolsRepository` and
  `FirestoreStudentsRepository`, with `orderBy`+`startAfter` cursor pagination,
  a case-insensitive prefix search, and a transactional dedupe guard against a
  `student_dedupe/{dedupeKey}` collection — the create either claims the guard
  document and the student atomically, or fails with the existing student's
  identity, with no window for a race to create two records for the same
  child.
- **Demo dataset** (`data/local/demo_master_data.dart`): exactly 1 state, 2
  districts, 3 clusters, 5 schools and 100 students (requirement §53), built
  from placeholder names only — no real student data.
- **Screens**: a hierarchy browser (breadcrumbs, search, infinite scroll,
  permission-gated create) that starts at States for global/state-scoped users
  and at a flat searchable Schools list for cluster/school-scoped users; a
  school detail screen; a students list (per-school, with a school picker for
  multi-school scopes, search, grade/section filter, CSV import, add) and a
  student detail screen.
- **A real router bug found and fixed**: every parameterized route
  (`/schools/:schoolId`, `/students/:studentId`, …) was being checked against
  `GoRouterState.matchedLocation` — the concrete path with ids substituted —
  instead of `fullPath`, the declared template. Since the permission-rule
  lookup is an exact string match, this had silently failed every such route
  closed, for every role, since Phase 1; no Phase-1 test exercised a
  parameterized route through the real router, so it went uncaught until
  Phase 2's widget tests navigated into one.
- **A real scope-filtering bug found and fixed**:
  `InMemorySchoolsRepository`'s list methods accepted a scope but never
  actually applied `AccessScope.covers` to it, so every hierarchy list call
  returned unscoped results regardless of caller. Covered now by dedicated
  scope-isolation tests so it cannot regress silently.
- **Tests**: unit tests for the pagination primitive; the CSV importer (parse
  errors, blank rows, header case-insensitivity); the demo dataset (exact
  counts, ancestry resolution, no real student data); scope isolation for both
  repositories (cluster-scoped and school-scoped reads, a teacher's
  grade-section narrowing, `getSchool`/`getStudent` denial outside scope); a
  2,000-student pagination test proving no page ever exceeds the default page
  size and the full roster is only reachable by walking every cursor; and
  widget smoke tests driving the real screens end to end (hierarchy
  drill-down, breadcrumb navigation, search, a single-school-scoped teacher
  landing with no picker, adding a student, duplicate rejection, CSV import).

## Phase 3 — what was built

Delivered in `natco_app/`:

- **Assessment domain**: `Assessment` (deliberately carries no school/
  cluster/district/state ancestry — the definition itself, its questions and
  its answer key are shared across the whole system; only
  `AssessmentAssignment` connects one to a school, and scope checks apply
  there, not to the definition), `AssessmentStatus` as a linear, forward-only
  state machine (`DRAFT → PUBLISHED → ACTIVE → SCORING_LOCKED → CLOSED →
  ARCHIVED`), `AssessmentQuestion`, `AnswerKey` + `AnswerKeyStatus`, and
  `AssessmentAssignment` + `AssignmentStatus`.
- **Answer-key immutability by construction, not convention**:
  `AssessmentsRepository` exposes no method that can edit a published key's
  answers — `publishAnswerKey` is the only write path. The first call
  publishes version 1 directly; every call after that is a correction,
  requires a `changeReason`, and atomically marks the previously published
  version `SUPERSEDED` (with `supersededBy` pointing at the new version)
  while the new version becomes `PUBLISHED`. An old version's answers are
  never overwritten, so a score against it always stays explainable.
- **A pure answer-key parser** (`AnswerKeyParser`): turns a comma-separated
  answer string into a `{questionNumber: option}` map with per-position parse
  errors (missing answer, invalid option, wrong count) before anything
  reaches the repository — the same "parse, then persist" split
  `StudentCsvImporter` uses.
- **In-memory implementation**: `InMemoryAssessmentsRepository`, covering
  assessment/question CRUD (questions editable only while the assessment is
  still a draft — once published, the paper is printed), the answer-key
  publish/correct/supersede flow above, and scope-aware assignment listing
  that resolves each assignment's school through `InMemorySchoolsRepository`
  for its ancestry, the same pattern `InMemoryStudentsRepository` uses and
  for the same reason: `AssessmentAssignment` itself only carries `schoolId`.
- **Firestore implementation**: `FirestoreAssessmentsRepository`, using the
  documented deterministic answer-key document id `{assessmentId}_v{version}`
  (docs/03-firestore-schema.md) so `publishAnswerKey` can find "the currently
  published version" with a single `transaction.get` by reference —
  `Assessment.activeAnswerKeyVersion` names which version that is — rather
  than a query, which the client SDK cannot run inside a transaction.
  Publishing and superseding happen atomically inside one transaction: a
  reader never sees two `PUBLISHED` versions.
- **Demo dataset** (`data/local/demo_assessment_data.dart`): one fresh `DRAFT`
  assessment with no key yet, and one `ACTIVE` assessment already carrying a
  `SUPERSEDED` v1 and a `PUBLISHED` v2 with a change reason, assigned to one
  of the schools `seedDemoMasterData` seeds — so the demo build shows the
  whole correction story without anyone driving it by hand first.
- **Screens**: a searchable, status-filterable assessments list; an
  assessment detail screen (status, questions, answer-key summary,
  assignments, and the single legal next status transition); and an answer
  key screen with full version history and the publish/correct entry dialog.
- **Tests**: unit tests for the answer-key parser; both status state machines
  (every transition pair checked, not just the happy path); the repository's
  creation validation (duplicate code, non-positive question count),
  draft-only question editing, the status state machine including the
  "cannot activate without a published key" rule, assignment scope isolation,
  and — the two Phase 3 exit criteria — a v1 key publishing directly and
  becoming immutable, and a correction producing v2 with a reason that
  supersedes v1 while leaving v1's own answers untouched; a demo-dataset test
  asserting the seeded correction story; and widget smoke tests driving the
  real screens end to end, including publishing a v1 key, correcting it to
  v2 through the actual dialog, and confirming a correction is refused
  without a reason.

## Phase 4 — what was built

Delivered in `natco_app/`:

- **Session domain**: `AssessmentSession` and a linear `SessionStatus` state
  machine (`DRAFT → STARTED → IN_PROGRESS → COMPLETED → SYNC_PENDING →
  SYNCED → CLOSED`). This phase only ever writes `STARTED`, `IN_PROGRESS` and
  `COMPLETED` — a session is created directly at `STARTED` (there is nothing
  to persist about a session that only exists as an unfilled form on
  screen), and the remaining three states are reserved for Phase 9's sync
  engine. The enum carries all seven now so that phase does not have to
  touch this file to insert a value in the middle of the sequence.
- **`SessionPrerequisites` and its downloader**: everything one assignment
  needs to run a session offline — the assessment, its questions, its
  published answer key (or `null`, captured as fact, not hidden, when none
  exists yet), and the student roster for each of the assignment's sections
  — fetched once by `SessionPrerequisitesDownloader` while online and cached
  locally. This is the one place in the whole feature that calls a
  network-backed repository (`AssessmentsRepository`/`SchoolsRepository`/
  `StudentsRepository`); `AssessmentSessionsRepository.startSession` reads
  only the cache, never those repositories directly — the split that makes
  "download while you still have signal, then work all day in airplane
  mode" an architectural property rather than a hope.
- **Sessions are always local-first, in every environment**: unlike
  Phases 2-3's schools/students/assessments (Firestore in real environments,
  in-memory in demo), `assessmentSessionsRepositoryProvider` and
  `sessionPrerequisitesRepositoryProvider` use a **Hive-backed**
  implementation in every Firebase-using environment and an in-memory one
  only in demo/tests — because a session has to be startable and runnable
  with no network at all, which is not a property Firestore can give it.
  Both Hive repositories store each entity as a JSON string keyed by its id
  (`Box<String>`, the same shape `SecureSessionStore` already uses for the
  cached auth session), so neither needs a generated `TypeAdapter` and
  neither adds to the `build_runner` surface.
- **The state machine is enforced identically on both backends**: illegal
  transitions (skipping `IN_PROGRESS`, moving backward) are rejected with
  `IllegalStateTransitionFailure` by the in-memory and the Hive repository
  alike, from the same one-line `index + 1` rule `AssessmentStatus` and
  `AssignmentStatus` already established in Phase 3.
- **Screens**: a sessions screen listing a teacher's existing sessions and
  every assignment they can start a new one from, with a "Download for
  offline" action per undownloaded assignment and a "Start Section X" action
  per section once downloaded; and a live session screen (deliberately
  outside the navigation shell, so a teacher cannot wander off mid-session)
  that auto-advances a freshly-started session into `IN_PROGRESS` — there is
  no separate "begin capturing" action until Phase 5 adds OMR capture — and
  ends it into `COMPLETED` on request.
- **Tests**: unit tests for the state machine; the downloader (builds a
  correct `SessionPrerequisites` from real seeded data, handles an
  assessment with no published key yet as a normal case, fails cleanly for
  a school that no longer exists); the in-memory repository (state machine
  enforcement, scope isolation by school and by teacher, refusing to start a
  session for a section outside the download); and — the two Phase 4 exit
  criteria proven directly rather than asserted by code inspection — a
  genuine Hive test that opens a real box on a temp directory, writes a
  session, fully closes Hive (the same call a killed process leaves
  undone), reopens against the same directory, and confirms the session
  and a downloaded `SessionPrerequisites` are both still there and fully
  usable; and a widget smoke test that downloads, starts, runs and completes
  a session with the app's connectivity service forced offline for the
  entire test.

## Phase 5 — what was built

Delivered in `natco_app/`, scoped to steps 1-2 of the eleven-step pipeline in
[07-omr-pipeline.md](07-omr-pipeline.md) — decode/downscale and quality
analysis. Marker detection, alignment, ID decode, bubble sampling,
classification and confidence all belong to Phase 6, which is why the
entities below carry no field for any of them: a field nothing yet computes
is left off rather than filled with a placeholder that looks computed.

- **`ImageQualityAnalyzer`**: a pure-Dart, synchronous analyser (package:image
  v4) that downscales a captured JPEG to a working size, then measures blur
  (a Laplacian-style variance proxy), brightness, contrast, and shadow/
  uneven-lighting deviation across a 4x4 luminance grid, against the
  `ImageQualityThresholds` Phase 1 already reserved for exactly this split.
  Each failing metric contributes its own plain-language reason — "the photo
  is blurred", "too dark", "too bright", "washed out", "part of the sheet is
  in shadow" — rather than one generic "quality check failed" message.
- **`OmrProcessingStatus`**: the full 14-state graph from
  [02-data-model.md](02-data-model.md) §47, of which this phase implements
  only three edges (`CAPTURED → QUALITY_CHECKED → QUALITY_FAILED`, and back
  to `QUALITY_CHECKED` on an explicit override) through `OmrStateMachine`,
  which rejects every other transition — including skipping straight to a
  later pipeline stage — the same "illegal transition" pattern Phase 3's
  `AssessmentStatus` and Phase 4's `SessionStatus` already use.
- **Durable image write, ordered before anything else**:
  `FileSystemOmrImageStore` writes the captured JPEG to disk the moment it is
  picked — before quality analysis runs and before any `OmrSubmission`
  record is created. A submission record is only ever created once the
  outcome is known (a pass, or an explicit "Use Anyway" override), so a
  `Retake` leaves an orphaned but harmless file rather than a half-finished
  record; proven directly by a durability test that writes a file, then
  opens a *second* store instance against the same directory with no
  submission ever created, and confirms the bytes are still there.
- **`OmrSubmission` and `OmrSubmissionsRepository`**: always local-first, in
  every environment — `HiveOmrSubmissionsRepository` outside demo/tests, the
  same posture Phase 4 gives sessions, because a capture has to succeed with
  no network at all. `overrideQualityGate` is the one path that can move a
  `QUALITY_FAILED` submission back to `QUALITY_CHECKED`, and only Supervisors
  and Super Admins can call it (docs/04-security-model.md: "the person under
  time pressure in the classroom is exactly the wrong person" to waive the
  gate) — a genuine gap in the current permission matrix means Super Admin is
  the only role today that holds both `captureOmr` and `overrideQualityGate`
  together, so it is the one account that can exercise the full override
  flow end to end.
- **Capture screen**: identify the student and printed OMR id, capture from
  camera or gallery, see the quality verdict immediately, then Retake or
  Save (or "Use Anyway" with a required reason, when permitted). Reachable
  with or without a session in context — with none, it asks the operator to
  start or resume one rather than guessing which session a sheet belongs to.
- **A real widget-test-only bug found and fixed**: the "Use Anyway" dialog's
  confirm button read `reasonController.text` once at dialog-build time and
  never rebuilt as the operator typed, so it stayed disabled regardless of
  what was entered. Wrapping the dialog body in a `ListenableBuilder` keyed
  to the controller fixed it — caught by the smoke test tapping the button
  after typing a reason and finding the tap silently did nothing.
- **Tests**: unit tests for the quality analyser (each metric, each failure
  message, a malformed file treated as a failed decode rather than a crash);
  the state machine (every legal edge, and that skipping a stage or a no-op
  transition is rejected); the in-memory submissions repository (creation,
  the override transition, refusing an override on a submission that is not
  quality-failed, scope isolation); genuine durability tests for both the
  image file (survives a fresh store instance with no submission ever
  created) and the Hive submission record (survives a real close-and-reopen
  of the box, the same proof Phase 4 uses for sessions); and a widget smoke
  test driving the real capture screen end to end for both a sharp photo
  that passes and saves, and a blurred, dark photo that fails with two named
  reasons and is then saved anyway through the Super Admin override path.

## Phase 6 — what was built

Delivered in `natco_app/`, implementing docs/07-omr-pipeline.md Steps 3-11 —
marker detection through the validation decision — as a pure-Dart
`OmrImageProcessor`-shaped pipeline, exactly the architecture §5 of that
document chose: an algorithm developed and regression-tested with no device
and no emulator, ready for a native accelerator to sit behind the same call
site later without the algorithm itself changing.

- **`OmrTemplate`** (`assets/omr_templates/natco_v1.json`): the NATCO v1
  sheet's marker rectangle and answer-grid geometry, stored as structural
  parameters (column origins, row pitch, option spacing) rather than one
  literal entry per bubble — the grid is perfectly regular, so a formula
  over these parameters is the same geometry a fully enumerated array would
  encode, with far less JSON to keep in sync by hand. Carries no header
  OMR-id bubble grid: Phase 5's manual entry already gives every submission
  a trusted id, so decoding it a second time from a bubble grid would only
  serve an accuracy metric, not a missing capability — deliberately deferred
  alongside the `omr_registry` duplicate-check infrastructure Step 7
  describes, which nothing in this phase needs yet.
- **`MarkerDetector`**: locates the four registration markers by
  thresholding each corner's own search box against *that box's* mean
  luminance (rather than a single sliding window over the whole frame) —
  simpler than the doc's literal adaptive-mean-C description, while still
  giving each corner a threshold that tracks its own local lighting, which
  is the actual property that defeats a sheet lit from one side. A blob
  must also clear a minimum-area floor relative to its search box, found
  necessary after a real bug: a rasterised circle's corner pixels can form
  a tiny, coincidentally-square 2-4 pixel artifact that shape checks alone
  (fill ratio, aspect ratio) cannot tell from a genuine small marker.
- **`SheetRectifier`**: perspective correction via `package:image`'s own
  `copyRectify` (a bilinear quad-to-rectangle mapping) rather than a
  hand-rolled projective-homography solver — for the near-rectangular quads
  a phone photo of a flat sheet produces, the two agree to well within a
  bubble's radius. Orientation is resolved *without* a post-hoc rotation of
  the rectified image (which would swap a non-square canvas's width and
  height): the four detected corners are instead fed into `copyRectify` in
  whichever order already produces the correct orientation directly, chosen
  from which corner the notched marker (identified by its lower fill ratio)
  was found in. This is the step that keeps a sheet photographed upside
  down — or rotated 90° or 270° — from aligning "successfully" and reading
  its answer grid silently wrong; proven directly by tests that rotate a
  synthetic sheet 90° and 180° and confirm it still reads correctly.
- **`BubbleSampler` and `AnswerClassifier`**: sample each bubble as a disc
  at a configurable fraction of its nominal diameter, with `meanInk` and
  `coverage` combined by the `BubbleThresholds` weights Phase 1 already
  defined; classify by the exact cascade in docs/07-omr-pipeline.md Step 9
  (blank → multiple-mark → high/medium/low confidence by margin), and
  compute `machineConfidence` separately via `ConfidenceWeights.score`
  (Step 10), which folds in image quality. The two are deliberately
  independent: three of the doc's four worked examples confirm the
  cascade's own margin thresholds decide the categorical status, not the
  blended confidence score, so `ConfidenceWeights`'s own
  `mediumConfidenceFloor`/`highConfidenceFloor` are left for a future
  presentation-facing bucketing of the continuous score rather than reused
  here.
- **`OmrProcessingPipeline`**: chains decode → downscale → marker detection
  → rectify → per-question sampling and classification → Step 11's
  validation decision into one pure function of its inputs, with no
  repository and no `Ref` — the same function the app calls, a worker
  isolate wraps, and the golden-dataset harness calls directly.
- **`OmrStateMachine` extended**: `QUALITY_CHECKED → PROCESSING →
  PROCESSING_FAILED/PROCESSED`, with `PROCESSING_FAILED` able to retry back
  into `PROCESSING`, and `PROCESSED → NEEDS_VALIDATION`/`READY_FOR_SCORING`
  decided by whether any question's status requires a human
  (`DetectionStatus.requiresValidation`) or the quality gate was overridden.
- **`OmrAnswer` and `OmrAnswersRepository`** (Hive + in-memory): one record
  per question per sheet, keyed by the sheet's `omrId` per the documented
  schema, scoped to the machine-written fields this phase actually produces
  — `finalAnswer`, `isCorrect`, `marks` and the validation fields wait for
  Phases 7-8, the same "omit until meaningful" pattern every prior phase's
  entities follow.
- **`OmrProcessingService`**: orchestrates one submission through the whole
  engine — loads it, transitions it into `PROCESSING`, reads its durable
  image, runs the pipeline via an injectable `OmrPipelineRunner`, persists
  the resulting answers, and drives the final state transition. Runs the
  pipeline through `IsolateOmrPipelineRunner` (`Isolate.run`) in the app, so
  Steps 3-10's pixel-level work never blocks the UI thread; deliberately
  without the doc's own progress stream, since a determinate progress bar
  is only honest once per-stage timings have actually been measured against
  the budget in docs/07-omr-pipeline.md §6, which nothing in this phase
  does yet — a plain busy indicator for the isolate call's duration is what
  today's real capability supports.
- **Review screen**: replaces the Phase 1 placeholder with a real screen —
  process a captured sheet and see its per-question detected answer,
  status and confidence — reachable from a new "Captured sheets" list on
  the session screen. Deliberately narrower than the placeholder's own
  description: no score preview (Phase 8 has not built scoring) and no
  duplicate-registry check (`omr_registry` does not exist yet).
- **Golden-dataset harness** (`dart run tool/omr_eval.dart`, per
  docs/10-omr-calibration-testing.md §2): runs the real
  `OmrProcessingPipeline` over a synthetic dataset (`tool/synthetic_omr_
  sheet.dart` renders sheets with known ground truth — no `omr_dataset/` of
  real scans or field photographs exists in this environment) covering
  clean sheets, rotation (1°/5°/15°/90°/180°/270°), gaussian blur, low
  light, and heavy JPEG compression, and writes `summary.json`,
  `per_sheet.csv`, `per_question.csv` and `confusion.csv`. The most recent
  run measured, over 13 synthetic sheets (130 questions): **93.8%
  per-question accuracy, 92.3% per-sheet accuracy, 0% silent error rate**
  (the release-gate metric — every wrong answer was a safe failure: routed
  to `BLANK`/`MULTIPLE` rather than a wrong high-confidence answer, never
  the reverse) and zero processing failures across every degradation
  category, including every rotation tested. Accuracy was lowest under
  rotation (86.7% per-question, still zero silent errors), which the report
  attributes honestly to the missing per-block local-refinement step
  (docs/07-omr-pipeline.md Step 6, not built this phase) rather than to a
  guessed cause. Per the harness's own honest-reporting rule, `summary.json`
  states plainly that every one of these numbers comes from synthetic
  renderings only — field accuracy is marked *unmeasured*, not
  interpolated, since no real photograph exists in this dataset to measure
  it from.
- **Golden tests**: pin the pipeline's exact per-question output (answer,
  status) on a small committed synthetic sheet, including upright, 90°- and
  180°-rotated renderings of the identical sheet all reading identically —
  so an algorithm change that alters any label fails CI rather than landing
  quietly.
- **Tests**: unit tests for the template's derived geometry; marker
  detection and rectification (including the upside-down and the
  missing-marker-fails-cleanly cases); bubble sampling and classification
  against the doc's own worked examples; the full pipeline end to end
  against real (JPEG-compressed) synthetic images, including a multiple-mark
  case and an undecodable file; the extended state machine's new edges; the
  `OmrAnswer` repositories including genuine Hive durability; the
  orchestration service against real in-memory repositories, including the
  processing-failure path leaving no answers written; and two widget smoke
  tests — the full engine run end to end from a saved submission through to
  displayed per-question results, and the golden-value regression tests
  above.
