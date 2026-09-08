# Security Model

Two independent questions are answered on every access:

1. **Permission** — may this *role* perform this *action*?
2. **Scope** — may this *user* touch this *school / cluster / district / state*?

Both must pass. Both are checked on the client (for UX: hide what cannot be
used) **and** on the server (for enforcement). The client check is advisory
only; a rooted phone with a patched APK gets exactly as far as the Firestore
rules allow it (§9 "Enforce permissions on the backend, not only in the UI").

## Roles

Exactly six, and the monitoring role is **Supervisor** — the word
"Coordinator" appears nowhere in this system:

`SUPER_ADMIN`, `ASSESSMENT_ADMIN`, `SUPERVISOR`, `PST_TEACHER`,
`SCANNER_OPERATOR`, `VIEWER`.

One role per user. Multi-role users are deliberately unsupported in v1: a
union-of-permissions model makes "why can this person see that school?"
unanswerable, and that question has to stay answerable.

## Permission matrix

Single source of truth: `lib/features/auth/domain/entity/permission.dart`.
Mirrored (read-only) into `roles/{roleId}` for the security rules.

| Permission | Super Admin | Assessment Admin | Supervisor | PST Teacher | Scanner Operator | Viewer |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| `viewDashboard` | ● | ● | ● | ● | ● | ● |
| `viewSchools` | ● | ● | ● | ● | — | ● |
| `manageStates` | ● | — | — | — | — | — |
| `manageDistricts` | ● | — | — | — | — | — |
| `manageClusters` | ● | — | — | — | — | — |
| `manageSchools` | ● | — | — | — | — | — |
| `viewStudents` | ● | ● | ● | ● | — | ● |
| `manageStudents` | ● | — | — | — | — | — |
| `importStudents` | ● | — | — | — | — | — |
| `viewUsers` | ● | — | — | — | — | — |
| `manageUsers` | ● | — | — | — | — | — |
| `manageSystemConfig` | ● | — | — | — | — | — |
| `viewAssessments` | ● | ● | ● | ● | ● | ● |
| `manageAssessments` | ● | ● | — | — | — | — |
| `manageQuestions` | ● | ● | — | — | — | — |
| `manageAnswerKey` | ● | ● | — | — | — | — |
| `manageAssessmentStatus` | ● | ● | — | — | — | — |
| `manageAssignments` | ● | ● | — | — | — | — |
| `conductAssessment` | ● | — | — | ● | — | — |
| `captureOmr` | ● | — | — | ● | ● | — |
| `processOmr` | ● | — | — | ● | ● | — |
| `reviewScanQuality` | ● | — | ● | ● | ● | — |
| `overrideQualityGate` | ● | — | ● | — | — | — |
| `viewOmrImage` | ● | — | ● | ● | ● | — |
| `resolveDuplicateOmr` | ● | — | ● | — | — | — |
| `validateOmr` | ● | — | ● | — | — | — |
| `reviewExceptions` | ● | — | ● | — | — | — |
| `viewResults` | ● | ● | ● | ● | — | ● |
| `viewOwnSubmissions` | ● | — | — | ● | ● | — |
| `correctScore` | ● | — | — | — | — | — |
| `viewAnalytics` | ● | ● | ● | — | — | ● |
| `viewQuestionAnalytics` | ● | ● | ● | — | — | ● |
| `exportReports` | ● | ● | ● | — | — | ● |
| `syncSubmissions` | ● | — | ● | ● | ● | — |
| `resolveSyncConflict` | ● | — | ● | — | — | — |
| `calibrateScanner` | ● | — | — | — | — | — |
| `viewAuditLog` | ● | — | — | — | — | — |

Notes on the judgement calls, so they are choices rather than accidents:

- **`overrideQualityGate` ("Use Anyway", §16) is withheld from teachers and
  scanner operators.** They retake the photograph instead. Letting the person
  under time pressure waive the quality gate is exactly how unreadable
  evidence enters the system, and Critical Rule 15 says the original image has
  to remain usable for audit. A Supervisor can waive it, and the waiver is
  recorded with the user and reason (`OMR_QUALITY_OVERRIDDEN`).
- **`exportReports` is granted to Assessment Admin and Viewer**, beyond the
  literal wording of §9, because both roles are defined by reading assessment
  analytics and §32 lists "assessment summary" and "question analysis" as
  report types. Exports are reads, and every export is audited.
- **`viewAuditLog` is Super Admin only.** A Supervisor investigates through
  `reviewExceptions`, which surfaces the same events filtered to their scope,
  without exposing user-level activity across the whole state.
- **`correctScore` is Super Admin only** and always writes a new superseding
  result plus a `SCORE_CORRECTED` audit entry. There is no code path that
  mutates a score in place (Critical Rule 5).

## Scope model

`AccessScope { level, stateIds, districtIds, clusterIds, schoolIds, gradeSections }`

| Level | Typical role | Matches |
|-------|--------------|---------|
| `GLOBAL` | Super Admin | everything |
| `STATE` | state-level Assessment Admin, Viewer | entities whose `stateId` ∈ `stateIds` |
| `DISTRICT` | Supervisor | `districtId` ∈ `districtIds` |
| `CLUSTER` | Supervisor | `clusterId` ∈ `clusterIds` |
| `SCHOOL` | PST Teacher, Scanner Operator | `schoolId` ∈ `schoolIds` |

Because every entity carries denormalised ancestry (`stateId`, `districtId`,
`clusterId`, `schoolId`), a scope check is a single set-membership test with no
extra reads — on the client and inside a security rule alike.

A teacher additionally carries `gradeSections`; a teacher assigned to
Grade 5-A cannot open Grade 5-B's session even in their own school. This is
what makes Critical Rule 10 ("teachers cannot access unauthorized schools")
enforceable one level deeper than the school.

**Supervisors get no implicit reach.** A Supervisor scoped to two clusters
sees those clusters only; there is no "and everything above/beside it" fallback
(§31).

## Custom claims

`onUserWrite` mirrors the user's `role` and a compact scope descriptor into
Firebase Auth custom claims:

```json
{
  "role": "SUPERVISOR",
  "lvl": "CLUSTER",
  "st": ["st_1"],
  "di": ["di_3"],
  "cl": ["cl_7", "cl_9"],
  "sc": []
}
```

Claims are used because a rule that reads `users/{uid}` on every request costs
a document read per operation and cannot be used inside a `list` rule.
Claims are capped: a user needing more than ~40 explicit ids is modelled one
level up (district instead of ten clusters). The function enforces that cap and
rejects the write with a clear error rather than silently truncating a scope —
a truncated scope is a privilege *reduction*, but a silent one, and silent is
the problem.

Claim propagation is not instant. `onUserWrite` also bumps
`users/{uid}.claimsVersion`; the client compares it against its ID token and
forces a token refresh, so a role revocation takes effect on the next request
rather than in up to an hour.

## Firestore rules — shape

Full rules in `firebase/firestore.rules`. The structure:

```
function claims()        → request.auth.token
function hasPerm(p)      → p in rolePermissions[claims().role]
function inScope(doc)    → GLOBAL, or doc.stateId/districtId/clusterId/schoolId
                            ∈ the matching claim array
function unchanged(f)    → request.resource.data[f] == resource.data[f]
```

The invariants the rules enforce, which no client can bypass:

| Invariant | Rule |
|-----------|------|
| Published answer keys are immutable | `answer_keys`: update allowed only while `status == 'DRAFT'`; publishing is Functions-only |
| Machine detection is write-once | `omr_answers`: `machineAnswer`, `machineConfidence`, `machineStatus`, `optionScores` must be `unchanged()` on every update |
| Scores are not client-writable | `results`: `allow write: if false` — only the `scoreSubmission` function writes them |
| OMR IDs are never reused | `omr_registry`: `create` only when `!exists()`, `update`/`delete` denied |
| Student identities are not merged | `student_dedupe`: `create` only when `!exists()`, `delete` requires `manageStudents` |
| Audit logs are append-only | `audit_logs`: `create` if authenticated; `update`/`delete` denied to everyone |
| Config is admin-only | `app_config/global`: read by any authenticated user, write requires `manageSystemConfig` |
| Nobody reads outside their scope | every collection's `read` requires `inScope(resource.data)` |
| A user cannot promote themselves | `users`: a user may update only `displayName`/`phone` on their own document; `role` and `scope` require `manageUsers` |

## Storage rules — shape

Full rules in `firebase/storage.rules`. Because the object path encodes the
ancestry, authorization is a path comparison:

```
match /omr/{year}/{assessmentId}/{stateId}/{districtId}/{clusterId}/{schoolId}/{date}/{file} {
  allow read:  if hasPerm('viewOmrImage') && inScopePath(stateId, districtId, clusterId, schoolId);
  allow create: if hasPerm('captureOmr')  && inScopePath(...)
                && request.resource.size < 8 * 1024 * 1024
                && request.resource.contentType.matches('image/jpe?g');
  allow update, delete: if false;   // originals are evidence
}
```

`allow update, delete: if false` on originals is Critical Rule 15 expressed as
a rule: a captured sheet cannot be replaced or removed by any client, ever.
Retention deletion happens through the `enforceRetention` scheduled function
using admin credentials.

## Secrets and configuration

- No service-account JSON in the Flutter project, ever. `.gitignore` blocks
  `*-service-account*.json`, `google-services.json`, `firebase_options*.dart`.
- `google-services.json` is supplied per environment at build time (CI secret
  or local developer file), never committed.
- Runtime configuration comes from `--dart-define` (`NATCO_ENV`) plus the
  server-side `app_config/global` document. No endpoint, key, or threshold is
  hard-coded for production.
- The mobile app holds only the public Firebase client config, which is not a
  secret — the security boundary is the rules, not config obscurity.

## Privacy posture

- No student name, date of birth, or external code in any Storage path, log
  line, analytics event, or crash report.
- The structured logger runs a redaction pass that drops known-sensitive keys
  (`studentName`, `dateOfBirth`, `email`, `phone`, `password`, `token`,
  `idToken`, `refreshToken`) before anything is emitted, so a careless
  `log.info(user.toJson())` cannot leak.
- Crashlytics receives `userId` (opaque) and never PII.
- Student data is not sent to any external AI service.
- Retention and controlled deletion run server-side under
  `enforceRetention`, driven by policy in `app_config`, and every deletion is
  audited.

## Authentication

- Firebase Authentication, email + password for v1.
- Offline login works from a **cached session record** (user profile, role,
  scope, claims version, and an expiry) stored in an encrypted Hive box, keyed
  by a device-bound key from `flutter_secure_storage`. It permits app *use*
  offline for a configurable window (default 7 days, `app_config`), never a
  fresh credential check — it is a session cache, not a password cache. No
  password or token is ever written to plain storage or to a log.
- On reconnect the cached session is revalidated; a disabled user or a changed
  role invalidates it immediately.
