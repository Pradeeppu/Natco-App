# Tests

363 tests. They need **no device, no emulator and no Firebase project** — the
whole suite runs in the same in-memory wiring the app uses for
`NATCO_ENV=demo`, which is why demo mode is treated as a real environment
rather than a toy.

```bash
flutter test                      # everything
flutter test test/features/       # domain and data logic
flutter test test/widget/         # widget, navigation and permission tests
flutter test test/core/           # Result, Failure, logger, pagination, ids
flutter test --coverage
```

## Layout

```
test/
├── app/          route table, route guard, navigation destinations
├── core/         Result, Failure, logger + redaction, id generator,
│                 scanner thresholds, PagedListController
├── features/
│   ├── auth/     permission matrix, scope membership, session lifecycle
│   ├── schools/  hierarchy entities, in-memory data source
│   └── students/ student entity, dedupe, CSV parser
├── integration/  end-to-end flows through the real wiring
├── widget/       screens driven through the real router
└── terminology_test.dart
```

## What each group is actually protecting

**`app/`** — that a screen cannot exist without an access decision.
`route_table_test.dart` fails if a route is registered but not declared, or
declared but not registered, and asserts that only splash and login are
public. The guard fails closed, so an undeclared route is forbidden rather
than open.

**`core/`** — the primitives everything else trusts. Notably
`log_redactor_test.dart` (a careless `log.info(user.toJson())` must not leak a
name) and `id_generator_test.dart` (the dedupe key must survive Indic vowel
signs — a normaliser that strips them collapses two different children onto
one key).

**`features/auth/`** — the permission matrix for all six roles, and scope
membership including the grade-section narrowing that stops a teacher
assigned to 5-A opening 5-B in their own school.

**`features/schools`, `features/students`** — pagination cursors, scope
filtering, and the two rejections that matter: a duplicate student is refused
with a named reason rather than merged, and a student's `dedupeKey` cannot be
changed on update.

**`widget/`** — the real router, the real guards, the real controllers. A
widget test that stubs the router proves nothing about whether a teacher can
reach the validation queue.

**`terminology_test.dart`** — scans the entire source tree for the word
"Coordinator". The product uses **Supervisor**, and a rule that only lives in
a document eventually gets broken.

**`preview_labelling_test.dart`** — every screen showing invented figures
carries a sample-data band, and every screen backed by real data does not.
As each phase lands, its route moves between the two lists in that file. This
is Critical Rule 14 made executable.

## Conventions

- `package:flutter_test` everywhere, including for pure-Dart tests, so there
  is one runner.
- **Fakes over mocks.** A scriptable `_FakeAuthService` beats a mock with
  expectations; `mocktail` is available but rarely needed.
- **Time is injected.** `FixedClock(DateTime.utc(2026, 9, 8, 9))` — never
  `DateTime.now()` in a test, or a greeting test fails at 3 a.m.
- Widget tests use `pumpApp` / `signInAs` from
  [`widget/test_harness.dart`](widget/test_harness.dart), which pins the
  surface size *and* the device pixel ratio — setting the size alone lets a
  "phone-sized" surface render the tablet rail.
- A test name states the behaviour, not the method: *"a cluster-scoped user
  cannot see a neighbouring cluster"*, not *"testListSchools"*.
- Where a test pins a **trade-off** rather than a fact, the reasoning goes in
  the file's doc comment — see `features/auth/auth_repository_test.dart` on
  why a reachable server always wins over a valid cache.

## Adding tests with a feature

The minimum for a new feature:

1. Entity round-trip: `toJson` → `tryFromJson` → equal, and a malformed
   document returns `null` rather than a half-built object.
2. In-memory data source: pagination, scope filtering, and every rejection
   path with the failure type it produces.
3. Widget: the mutation affordances are **absent** for roles without the
   permission — not merely disabled.
4. If you added a route, update `_declaredPaths` in
   `app/route_table_test.dart`.
