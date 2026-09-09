# Environment Setup

## Toolchain

| Tool | Version used | Notes |
|------|--------------|-------|
| Flutter | 3.47.2 (stable) | `pubspec.yaml` pins `sdk: ^3.13.2` |
| Dart | 3.13.2 | bundled with Flutter |
| Android SDK | API 34+ (compile), API 23+ (min) | Android-first (requirement section 4) |
| JDK | 17 | required by the Android Gradle plugin |
| Firebase CLI | latest | for rules and Functions deployment |

Verify with `flutter doctor -v`. A red mark against *Android toolchain* or
*Android Studio* will stop `flutter build apk` but not `flutter test` or
`flutter analyze`, both of which run on a bare Dart/Flutter install.

## Four environments

Selected at build time; nothing is hard-coded (requirement section 54).

| `NATCO_ENV` | Backend | Log level | Purpose |
|-------------|---------|-----------|---------|
| `demo` | none — in-memory services | debug | Run and test the whole app with no Firebase project. The default when `NATCO_ENV` is unset or unrecognised. |
| `dev` | development Firebase project | debug | Day-to-day development. |
| `staging` | staging Firebase project | info | Pre-release verification against production-shaped data. |
| `prod` | production Firebase project | warning | Release. |

```bash
flutter run --dart-define=NATCO_ENV=demo      # no backend needed
flutter run --dart-define=NATCO_ENV=dev
flutter build apk --release --dart-define=NATCO_ENV=prod
```

An unrecognised value resolves to `demo`, not to `prod`. Defaulting a
misconfigured build to production would be the most dangerous possible guess;
`demo` cannot touch real data.

### Why `demo` exists

It is not a toy. It runs the real router, the real permission matrix, the real
session controller and the real repository over in-memory services, so:

- a new developer can run the app before anyone gives them Firebase access;
- the widget and end-to-end tests exercise the same wiring the app uses;
- all six roles can be demonstrated without provisioning six accounts.

It contains no real student data (requirement section 53), and its demo
passwords are visible in source on purpose — they unlock nothing outside a
build that has no backend.

## Configuration sources, in precedence order

1. **Compile-time**: `--dart-define=NATCO_ENV`. Chooses the environment and
   its defaults (`lib/app/config/app_config.dart`).
2. **Server-side**: `app_config/global` in Firestore. Overrides feature flags,
   scanner thresholds and controlled vocabularies at runtime, so a threshold
   can be recalibrated or a feature disabled without shipping a release.
3. **Per-device**: user settings (for example, uploading images on mobile
   data).

Nothing reads `String.fromEnvironment` outside `app_config.dart`, and nothing
constructs a Firebase object outside `service_locator.dart`.

## Firebase project setup

Do this once per environment (`dev`, `staging`, `prod`).

1. **Create the project** in the Firebase console.
2. **Add an Android app** with the applicationId
   `org.natco.natco_app` (or a per-environment suffix such as
   `org.natco.natco_app.dev`).
3. **Download `google-services.json`** into `android/app/`. It is
   `.gitignore`d — each environment supplies its own, from a CI secret or a
   developer's local copy.
4. **Enable Authentication → Email/Password.** No other provider is used in
   v1.
5. **Create Firestore** in Native mode, in the region closest to the
   deployment (`asia-south1` for India).
6. **Create a Storage bucket.**
7. **Enable Crashlytics.** Analytics is deliberately left off — see
   [09-dependencies.md](09-dependencies.md).
8. **Deploy the rules and indexes** (below).
9. **Seed the role mirror**: write `roles/{roleId}` documents matching
   `kRolePermissions` in
   `lib/features/auth/domain/entity/user_role.dart`.
10. **Create the first Super Admin**: create the Auth user, then a
    `users/{uid}` document with `role: "SUPER_ADMIN"`,
    `scope: {level: "GLOBAL"}`, `isActive: true`. Every other user is created
    from inside the app.

### Deploying rules and indexes

```bash
cd firebase
firebase use <project-alias>
firebase deploy --only firestore:rules,firestore:indexes,storage:rules
```

Rules are the enforcement boundary, so deploy them **before** the first
client build reaches a project. A Firestore database created without rules is
open, and an open database with student data in it is an incident.

Test rules against the emulator before deploying:

```bash
firebase emulators:start --only firestore,storage,auth
```

### A user's profile document

```json
{
  "email": "supervisor@example.org",
  "displayName": "Fatima Sheikh",
  "phone": null,
  "role": "SUPERVISOR",
  "scope": {
    "level": "CLUSTER",
    "stateIds": ["st_1"],
    "districtIds": ["di_3"],
    "clusterIds": ["cl_7", "cl_9"],
    "schoolIds": [],
    "gradeSections": []
  },
  "isActive": true,
  "claimsVersion": 1,
  "createdAt": "2026-09-01T00:00:00Z",
  "updatedAt": "2026-09-01T00:00:00Z"
}
```

`role` must be one of the six wire names, and `scope.level` one of
`GLOBAL, STATE, DISTRICT, CLUSTER, SCHOOL`. A profile the client cannot
resolve is refused rather than partially trusted — the user sees "Your account
settings could not be read", and the failure is logged.

## Running

```bash
cd natco_app
flutter pub get
flutter run --dart-define=NATCO_ENV=demo
```

Demo sign-in: any of the role addresses shown on the login screen, with the
password `natco1234`. Tapping a role chip fills the form.

## Testing

```bash
flutter analyze                 # must be clean before any commit
flutter test                    # unit + widget + end-to-end
flutter test test/features/     # domain logic only
flutter test --coverage
```

`flutter test` needs no device and no Firebase project: the suite runs in the
`demo` wiring.

## Building

```bash
# Debug APK
flutter build apk --debug --dart-define=NATCO_ENV=dev

# Release APK, split per ABI to keep the download small on cheap devices
flutter build apk --release --split-per-abi --dart-define=NATCO_ENV=prod

# Play Store bundle
flutter build appbundle --release --dart-define=NATCO_ENV=prod
```

Release signing: put the keystore outside the repository and reference it from
`android/key.properties` (itself `.gitignore`d). Never commit a keystore or a
password.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| App opens on the login screen with "Demo accounts" in a `dev` build | `NATCO_ENV` was not passed, so it fell back to `demo` | add `--dart-define=NATCO_ENV=dev` |
| "Your account is not fully set up" | Auth user exists, `users/{uid}` does not | create the profile document |
| "Your account settings could not be read" | `role` or `scope` unresolvable | check the wire names against `UserRole` and `ScopeLevel` |
| Everything returns permission-denied | rules not deployed, or custom claims not yet minted | deploy rules; check `onUserWrite` ran and force a token refresh by signing out and in |
| A Supervisor sees no schools | scope ids do not match the school ancestry | compare `clusterIds` against the schools' `clusterId` |
| Role change has no effect | ID token still carries the old claims | the app refreshes on reconnect and on resume; signing out and in is the manual path |
| `flutter build apk` fails on `google-services.json` | file missing | it is `.gitignore`d by design; copy the environment's own |
| Gradle fails with a JDK error | wrong JDK | use JDK 17 |
| Any `flutter` command hangs forever at 100% CPU, printing nothing and spawning no `dart` process | The SDK is installed somewhere the current user cannot write — typically `C:\Program Files\flutter`. `flutter.bat` acquires a lock by opening `bin\cache\flutter.bat.lock` for writing, and on failure loops straight back to `:acquire_lock` with no delay, so a permissions error becomes an unkillable-looking spin rather than an error message. | Install the SDK somewhere the user owns (`C:\src\flutter`, or a copy on another drive) and point `PATH` at it. `dart analyze` still works from the unwritable SDK — only the `flutter` tool needs write access to its own cache. |
| `flutter pub get` fails with "The current Dart SDK version is 3.7.2 ... requires ^3.13.2" | A second, older Flutter install shadows the right one on `PATH` | `Get-Command flutter -All` lists every match in order; remove the stale entry from `PATH`, or invoke the intended SDK by full path |
