# MVP Implementation Plan

Twelve phases (§58). A phase starts only when the previous one's analyzer and
test suite are clean. Each phase lists its **exit criteria** — the check that
says "this is done", not "this compiles".

| Phase | Scope | Exit criteria | Status |
|-------|-------|---------------|--------|
| **1. Foundation** | project, architecture, theme, routing, config, auth, role + scope system, security rules, logging, error model | login works against Firebase and in demo mode; every route guarded; permission matrix unit-tested for all 6 roles; `flutter analyze` clean; test suite green | **complete** |
| **2. Master data** | states, districts, clusters, schools, students, CSV import, search, pagination | hierarchy CRUD within scope; duplicate student rejected with a named reason; 2 000-student school scrolls without loading all rows | **complete** |
| 3. Assessments | assessments, questions, answer keys (versioned), assignments | key v1 publishes and becomes immutable; a correction produces v2 with a reason and supersedes v1 | next |
| 4. Offline assessment | Hive boxes, pre-download, session lifecycle, reconciler | session survives force-stop; airplane-mode run completes end to end | |
| 5. OMR capture | camera, gallery, quality gate, durable image write, manual ID entry | image on disk before any processing; each quality failure gives its own message; kill-during-capture loses nothing | |
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
