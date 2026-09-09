# Project Status and Runbook

The single entry point: where the build is, how to run it, and what is left.
The numbered documents that follow this one carry the depth; this one carries
the state.

**Status: Phases 1–2 of 12 complete.** `flutter analyze` clean, 363 tests
passing, 26 routes all permission-guarded.

**Every screen for phases 3–11 now exists as a reviewable UI**, so the flows
can be walked through and critiqued before the engines behind them are built.
Those screens carry sample data, and each one says so in a band across the top
— see [§3a](#3a-ui-previews-for-phases-3-11).

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
| `superadmin@natco.demo` | Super Admin | Global — the only role that may create schools, students or imports |
| `assessmentadmin@natco.demo` | Assessment Admin | One state |
| `supervisor@natco.demo` | Supervisor | Two clusters |
| `teacher@natco.demo` | PST Teacher | One school, Grade 5 Section A only |
| `scanner@natco.demo` | Scanner Operator | Two schools, no student list |
| `viewer@natco.demo` | Viewer | Read-only |

Seeded demo data: 1 state, 2 districts, 3 clusters, 5 schools, 100 students —
sharing ids with the demo accounts' scopes, so the two cannot drift
(`features/schools/data/service/demo_master_data.dart`).

### Verifying

```bash
flutter analyze      # must be clean
flutter test         # 351 tests, no device and no backend required
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

   `dart analyze` still works from the unwritable SDK; only the `flutter` tool
   needs to write to its cache.

2. **A stale SDK shadows the right one.** `C:\flutter\flutter` ships Dart 3.7.2
   and currently wins on `PATH`; this project requires `^3.13.2`, so a bare
   `flutter` call fails version solving with a message that reads like a
   project fault. `Get-Command flutter -All` lists every match in order.

---

## 3. What is built

### Phase 1 — Foundation

- Composition root with four environments; every backend touchpoint is an
  interface with a Firebase and an in-memory implementation.
- 6 roles, a 38-permission compile-time matrix, `AccessScope` with
  hierarchy-aware membership, and `Authorization` as the single decision point.
- Auth: sign-in, offline session restore from an expiring encrypted cache,
  server-authoritative revalidation on reconnect.
- 26 routes each declaring a required permission, behind a fail-closed guard.
- Sealed `Failure` hierarchy, `Result<T>`, redacting logger, Material 3 theme.
- `firebase/firestore.rules` and `firebase/storage.rules`.

### Phase 2 — Master data

- State → District → Cluster → School → Student, behind
  `SchoolHierarchyRepository` and `StudentRepository`, each with an in-memory
  and a Firestore data source composed by one audit-logging repository.
- Hierarchy browser that starts at the caller's own scope level.
- Students: paginated, searchable, scope-filtered, with create and inline edit.
- CSV import previewing "N ready / M rejected", checking duplicates within the
  file and against registered students, attempting every row independently.
- `PagedListController` — debounced search, infinite scroll, stale-response
  dropping — shared by both lists.
- `SchoolPicker`, the cascading selector phases 3–4 reuse.

Full detail: [08-mvp-implementation-plan.md](08-mvp-implementation-plan.md).

### Three defects the Phase 2 verification pass caught

| Defect | Consequence had it shipped |
|---|---|
| Failures thrown out of a provider build | In this Riverpod version a failed build settles as `AsyncLoading` with `hasError` set and `when()` routes it to *loading* — every list and dropdown would spin forever on any network failure (§41). Failures are now carried as data. |
| `DateTime.tryParse('2015-04-02')` returns local time | The dedupe key hashes `.toUtc()`, so the same child imported in IST and UTC hashed differently and the duplicate would have been admitted (§11). Both the CSV parser and the date picker now normalise to midnight UTC. |
| `csv` 8.0.0 and `file_picker` 12.2.0 API rewrites | Would not compile. |

### 3a. UI previews for phases 3–11

Built ahead of their phases so the team can review the flows early. They are
UI only: no repository, no engine, no persistence.

| Screen | Route | Phase it belongs to |
|---|---|---|
| Assessments list, detail, answer-key editor | `/assessments`, `/assessments/:id`, `…/answer-key` | 3 |
| Live session with roster and capture progress | `/assessment-session/:id` | 4 |
| Camera framing and the image-quality gate | `/omr/capture` | 5 |
| Scan result with confidence breakdown | `/omr/review/:omrId` | 6 |
| Scanner calibration and accuracy harness | `/settings/calibration` | 6 |
| Validation queue and per-question validation | `/omr/validation`, `/omr/validation/:omrId` | 7 |
| Results list and per-student question table | `/results`, `/results/:studentId` | 8 |
| Sync queue, failures and conflict resolution | `/sync` | 9 |
| Analytics drill-down and question performance | `/analytics` | 10 |
| Report catalogue and CSV export | `/reports` | 11 |

**Every figure on these screens is invented**, which is a hazard in a product
whose Critical Rule 14 forbids showing a number it has not measured. Each
screen therefore carries an unmissable band saying so
(`core/widgets/preview_kit.dart`), and
`test/widget/preview_labelling_test.dart` fails if a preview screen loses its
band — or if a screen backed by real data wrongly carries one. As each phase
lands, its route moves between the two lists in that test.

Two deliberate exceptions to the mock data, both because faking them would
undermine the product's own rules:

- **Calibration** shows an empty state, not an accuracy figure. None has been
  measured, so none is shown even in a preview.
- **Scan result** labels its score a *preview* and states that it cannot be
  published while any answer still needs a human.

---

## 4. What is left

Ten phases. A phase starts only when the previous one's analyzer and test
suite are clean; each is gated on a check that says "this is done", not "this
compiles". Exit criteria are tabulated in
[08-mvp-implementation-plan.md](08-mvp-implementation-plan.md).

| # | Phase | The gate |
|---|---|---|
| 3 | Assessments | Key v1 publishes and becomes immutable; a correction produces v2 with a reason and supersedes v1 |
| 4 | Offline assessment | A session survives a force-stop; an airplane-mode run completes end to end |
| 5 | OMR capture | The image is on disk before any processing; each quality failure has its own message; a kill mid-capture loses nothing |
| 6 | OMR engine | Pipeline runs in a worker isolate; a golden-dataset harness reports measured accuracy; an upside-down sheet is detected, not silently inverted |
| 7 | Validation | Machine fields provably unchanged after validation; a submission needing validation cannot reach `SCORED` |
| 8 | Scoring | Client and server scores agree on the dataset; a re-score supersedes rather than mutates |
| 9 | Synchronization | A kill mid-upload produces exactly one server record; a conflict shows both versions and never auto-resolves |
| 10 | Analytics | Metrics reconcile against raw results; a Supervisor sees only their scope |
| 11 | Reports | Every export audited; no student name in any filename |
| 12 | Hardening | Rules pass a deny-by-default review; performance budgets met on the reference device |

Fourteen screens are guarded placeholders naming the phase that implements
them — a route that resolves and says so beats a 404 or a buried `TODO`.

---

## 5. Where the code lives

```
lib/
├── app/         composition root, router, guards, theme, shell
├── core/        Result, Failure, logger + redaction, pagination, widgets
├── features/    auth · schools · students · dashboard   (built)
│                assessments · assessment_sessions · omr_capture ·
│                omr_processing · omr_validation · results · sync ·
│                analytics · reports · settings           (phases 3–12)
└── data/        local (Hive) and remote (Firebase) implementations
```

Every feature carries `data/ · domain/ · presentation/`. The domain layer is
pure Dart with no Flutter and no Firebase imports — that is what makes scoring,
confidence classification and the permission matrix testable without a device.
Architecture in full: [01-architecture.md](01-architecture.md).

---

## 6. Rules the build does not bend

Enforced in code and in the security rules, not merely written down.

| Rule | Enforced by |
|---|---|
| The monitoring role is **Supervisor**; "Coordinator" appears nowhere | A test scans the source tree on every run |
| Machine readings are evidence, never overwritten by a human decision | `omr_answers` machine fields are write-once |
| Published answer keys are immutable; a correction is a new version | Firestore rules; publishing is Functions-only |
| No client of any role writes a score | `results`: `allow write: if false` |
| An OMR id is never reused, a duplicate never silently overwritten | `omr_registry` guard document in the same transaction |
| Student identities are never silently merged | `student_dedupe` guard document + Unicode-safe key |
| Audit logs are append-only, Super Admin included | Rules deny update and delete |
| Nobody reads outside their geographic scope | Every collection's read rule, plus scope-derived queries |
| The app shows no number it has not measured | The dashboard leaves assessment metrics blank until the phases that produce them exist |
