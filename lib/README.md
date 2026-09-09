# Code layout

```
Presentation  →  Domain  →  Data  →  Services / Infrastructure
```

Dependencies point one way. The **domain layer is pure Dart** — no
`package:flutter`, no `cloud_firestore`. That is not purism: it is what lets
scoring, confidence classification, duplicate detection and the permission
matrix be tested in milliseconds without a device or a backend, and it is what
makes the backend replaceable.

```
lib/
├── main.dart
├── app/
│   ├── app.dart              root widget
│   ├── router.dart           the route table — every route declares a permission
│   ├── route_guard.dart      fail-closed redirect logic
│   ├── navigation.dart       role-filtered navigation destinations
│   ├── shell.dart            bottom bar / rail around the primary screens
│   ├── theme.dart            Material 3 theme + semantic status colours
│   └── config/
│       ├── app_config.dart       the only reader of String.fromEnvironment
│       ├── app_environment.dart  demo · dev · staging · prod
│       ├── feature_flags.dart
│       ├── scanner_thresholds.dart
│       └── service_locator.dart   the composition root
├── core/
│   ├── constants/            collection names, route paths, storage paths
│   ├── errors/failure.dart   sealed Failure hierarchy
│   ├── utils/                Result, Clock, IdGenerator
│   ├── pagination/           PagedListController and Page<T>
│   ├── services/             logger + redaction, connectivity, audit, crash, device
│   └── widgets/              shared views, status chip, preview kit
├── features/                 one folder per feature
└── data/
    ├── local/                Hive bootstrap, platform device info
    └── remote/               Firebase implementations of core services
```

## Feature structure

Every feature folder carries the same three:

```
features/<feature>/
├── domain/
│   ├── entity/        immutable value types, pure Dart
│   ├── repository/    the interface the presentation layer calls
│   └── service/       domain logic (e.g. Authorization)
├── data/
│   ├── service/       the swappable backend: an interface + in-memory + Firestore
│   └── repository/    the single implementation, which adds audit and derived logic
└── presentation/
    ├── controller/    Riverpod notifiers and providers
    ├── screen/        one file per screen
    └── widget/        components specific to this feature
```

### Why data/ has both a "service" and a "repository"

`auth` set the pattern and `schools`/`students` follow it:

- **`XDataSource`** is the swappable half — raw CRUD and queries, with an
  in-memory implementation for demo and tests, and a Firestore one for real
  use. It knows nothing about auditing.
- **`XRepositoryImpl`** is a single implementation that composes a data source
  with the `AuditSink`, the `Clock`, the `IdGenerator` and any derived logic
  (dedupe keys, ancestry resolution).

The payoff is that audit logging and business rules are written **once** and
tested once, instead of being duplicated in — and drifting between — two
backend implementations.

## Rules that hold everywhere

**A route cannot exist without a permission.** `GuardedRoute` makes the field
mandatory and `RouteGuard` treats an unknown route as forbidden, so a screen
added without an access decision fails closed rather than leaking.

**Repositories return `Result<T>`, they do not throw.** Throwing is reserved
for programmer error. Every expected condition — offline, denied, duplicate,
conflict — is a `Failure` carrying two messages: a `userMessage` safe for the
screen, and a `diagnostic` that only ever reaches the log.

**Providers are the only place a Firebase object is constructed.**
`service_locator.dart` switches implementations on
`AppConfig.environment.usesFirebase`. Nothing else calls a Firebase
constructor; nothing else reads `String.fromEnvironment`.

**Scope filtering happens in the query, not after it.** A list method takes the
caller's own `AccessScope` and builds the filter from it. Filtering a
page of 25 rows *after* fetching would silently return fewer than 25 — or
zero — while more exist.

**Nothing shows a number it has not measured.** Screens for unbuilt phases use
`core/widgets/preview_kit.dart`, which bands every one of them as sample data.
A test enforces it.

## Adding a feature

1. Entities in `domain/entity/` — immutable, `toJson`/`tryFromJson`,
   `copyWith`, value equality. Follow `AppUser` or `School`; the project does
   not use `freezed` for these.
2. The repository **interface** in `domain/repository/`.
3. A data-source interface in `data/service/`, plus an in-memory
   implementation (demo and tests) and a Firestore one.
4. The repository implementation in `data/repository/`, composing the data
   source with audit logging.
5. Providers in `app/config/service_locator.dart` for anything that switches
   on the environment; feature-local providers live in the feature's
   `presentation/controller/`.
6. Screens in `presentation/screen/`, and the route in `app/router.dart` with
   its required permission.
7. Tests: entity round-trips, in-memory data-source behaviour, and a widget
   test proving the affordances are hidden from roles that lack the
   permission.

## Adding a route

```dart
GuardedRoute(
  path: RoutePaths.myScreen,
  rule: const RouteAccessRule.requires(Permission.myPermission),
  insideShell: true,          // false for full-screen tasks like capture
  builder: (_, GoRouterState state) =>
      MyScreen(id: state.pathParameters['id']!),
),
```

Add the path to `RoutePaths`, and to `_declaredPaths` in
`test/app/route_table_test.dart` — that test fails on a route registered
without being declared, which is the point.

Full navigation map: [../docs/05-navigation-map.md](../docs/05-navigation-map.md).
Architecture reasoning: [../docs/01-architecture.md](../docs/01-architecture.md).
