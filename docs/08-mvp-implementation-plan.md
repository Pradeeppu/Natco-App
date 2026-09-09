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
| 5. OMR capture | camera, gallery, quality gate, durable image write, manual ID entry | image on disk before any processing; each quality failure gives its own message; kill-during-capture loses nothing | next |
| 6. OMR engine | template JSON, markers, homography, rotation, sampling, classification, confidence | pipeline runs in a worker isolate; golden dataset harness reports measured accuracy; upside-down sheet is detected, not silently inverted | |
| 7. Validation | review queue, per-question validation UI, audit trail | machine fields provably unchanged after validation; a submission needing validation cannot reach `SCORED` | |
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
