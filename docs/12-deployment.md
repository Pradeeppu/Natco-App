# Deployment

## What gets deployed, and in what order

Order matters. Rules first, then Functions, then the app — a client build that
reaches a project whose rules are not yet in place is a client with more access
than it should ever have had.

```
1. Firestore rules + indexes
2. Storage rules
3. Cloud Functions
4. Role mirror + app_config documents
5. Mobile app
```

## 1–2. Rules

```bash
cd firebase
firebase use natco-<env>
firebase deploy --only firestore:rules,firestore:indexes,storage:rules
```

Indexes take minutes to build on a large collection. Deploy them ahead of the
release that needs them, or the first query fails with
`FAILED_PRECONDITION`.

**Before deploying, review against the invariant table** in
[04-security-model.md](04-security-model.md). The specific checks:

- `results` is not client-writable.
- `omr_answers` machine fields are `unchanged()` on every update path.
- `audit_logs` denies update and delete to every role.
- `omr` originals in Storage deny update and delete.
- `omr_registry` and `student_dedupe` deny update.
- Every collection's read requires `inScope`.

## 3. Cloud Functions

The functions listed in [03-firestore-schema.md](03-firestore-schema.md)
belong to phases 3, 8, 9 and 10 and are deployed with them. Two of them are
load-bearing for security and are deployed with the rules that assume them:

- `onUserWrite` — mints the role and scope custom claims the rules read.
  Without it, every rule evaluates against an empty token and nothing works.
- `publishAnswerKey` — the only writer that can freeze a key version, because
  the rules deny clients that transition.

```bash
cd functions
npm ci
npm test
firebase deploy --only functions
```

## 4. Seed documents

```
roles/{roleId}        mirror of kRolePermissions
app_config/global     thresholds, feature flags, vocabularies
states/, districts/, clusters/, schools/   master data
```

The role mirror must match `lib/features/auth/domain/entity/user_role.dart`
exactly. Drift between the Dart matrix, the rules and this mirror is a
security bug; the Dart test suite pins the matrix, and the rules and mirror are
reviewed against it.

## 5. Mobile app

```bash
cd natco_app
flutter analyze                     # must be clean
flutter test                        # must be green
flutter build appbundle --release --dart-define=NATCO_ENV=prod
```

Release checklist:

- [ ] `flutter analyze` clean, `flutter test` green
- [ ] `NATCO_ENV=prod` passed (check the environment label on the login screen
      of the built APK — it is shown there deliberately)
- [ ] `google-services.json` is the production one
- [ ] version and build number bumped in `pubspec.yaml`
- [ ] rules and indexes deployed and verified against the emulator suite
- [ ] `minimumSupportedAppVersion` in `app_config` not above this build
- [ ] Crashlytics receiving from a test install
- [ ] OMR accuracy report from the current threshold version attached to the
      release notes (from phase 6 onward — see
      [10-omr-calibration-testing.md](10-omr-calibration-testing.md))
- [ ] offline soak: airplane-mode capture, force-stop, relaunch, reconnect,
      sync (from phase 9 onward)

## Rollback

- **App**: Play Store staged rollout, halt and roll back the release. Because
  every offline write is local-first and idempotent, a rollback loses no
  captured data.
- **Rules**: `firebase deploy` the previous revision from git. Rules are in
  version control precisely so this is a revert, not a rewrite.
- **Config**: `app_config/global` changes are audited
  (`SCANNER_THRESHOLDS_CHANGED`), so the previous values are recoverable from
  the audit trail.
- **Scanner thresholds**: revert the threshold version in `app_config`. No app
  release is required, which is the point of keeping them in configuration.

## Data migration

Two invariants constrain any migration:

1. **Dedupe keys are stored as document ids.** Changing the hash or the
   normaliser orphans every guard document and silently re-admits duplicates.
   The digest is pinned by a test for exactly this reason; if that test fails,
   the change needs a migration that rewrites the guard collection, not a new
   expected value.
2. **Published answer keys and scored results are immutable.** A migration
   adds new versions and supersedes old ones; it never edits them in place.

## Monitoring

| Signal | Where | Why it matters |
|--------|-------|----------------|
| Crash-free sessions | Crashlytics | field devices are low-end and varied |
| `sync_upload_failed` rate | structured logs | data sitting on devices is data at risk |
| Submissions in `NEEDS_VALIDATION` | analytics rollup | validation backlog is human cost |
| Submissions in `UNREADABLE_EVIDENCE_MISSING` | analytics rollup | the one place data loss would show |
| `permission-denied` rate | logs | a spike means the rules and the client disagree |
| Silent error rate | calibration harness | the release gate for the scanner |
