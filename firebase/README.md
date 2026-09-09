# Firebase configuration

The **enforcement boundary** for the whole product. Client-side permission
checks hide what a user cannot use; these files decide what a user can
actually do. A rooted phone running a patched APK gets exactly as far as
these rules allow it and no further.

```
firebase/
├── firebase.json            deploy targets
├── firestore.rules          collection access + the invariants below
├── firestore.indexes.json   composite indexes the app's queries need
└── storage.rules            object access; originals are write-once
```

## Deploying

Deploy rules **before** the first client build reaches a project. A Firestore
database created without rules is open, and an open database containing
children's data is an incident, not a bug.

```bash
cd firebase
firebase use <project-alias>
firebase deploy --only firestore:rules,firestore:indexes,storage:rules
```

Test against the emulator first:

```bash
firebase emulators:start --only firestore,storage,auth
```

Deploying indexes is not optional: several screens issue compound queries
(scope filter + ordering, prefix search + ordering) that fail at runtime
without them.

## What the rules enforce

Every one of these exists because the corresponding client-side check is not
trustworthy on its own.

| Invariant | Rule |
|---|---|
| Published answer keys are immutable | `answer_keys` updatable only while `status == 'DRAFT'`; publishing is Functions-only |
| Machine detection is write-once | `omr_answers`: `machineAnswer`, `machineConfidence`, `machineStatus`, `optionScores` must be unchanged on every update |
| Scores are not client-writable | `results`: `allow write: if false` — only `scoreSubmission` writes them |
| OMR ids are never reused | `omr_registry`: create only when the document does not exist; update and delete denied |
| Student identities are not merged | `student_dedupe`: create only when absent; update denied; delete requires `manageStudents` |
| A student's identity cannot be edited into someone else's | `students`: update requires `dedupeKey` unchanged |
| Audit logs are append-only | `audit_logs`: create if authenticated; update and delete denied to everyone, Super Admin included |
| Nobody reads outside their scope | every collection's read rule checks the caller's scope claims against the document's denormalised ancestry |
| A user cannot promote themselves | `users`: a user may update only `displayName` and `phone` on their own document; `role` and `scope` require `manageUsers` |
| Config is admin-only | `app_config/global`: readable by any authenticated user, writable only with `manageSystemConfig` |
| Original captures cannot be altered | Storage: `allow update, delete: if false` on `omr/**` |

## How authorisation is decided

Two questions, both of which must pass:

1. **Permission** — does this role hold it? Read from
   `request.auth.token.role` against the mirrored permission matrix, not from
   a document, because a rule that reads `users/{uid}` costs a document read
   per operation and cannot be used inside a `list` rule at all.
2. **Scope** — is the target inside the caller's geographic reach? Every
   document carries denormalised ancestry (`stateId`, `districtId`,
   `clusterId`, `schoolId`), so this is a single set-membership test against
   the claims array with no extra reads.

Custom claims are minted by `onUserWrite`, which also bumps
`users/{uid}.claimsVersion`. The client compares that against its ID token and
forces a refresh, so a role revocation takes effect on the next request rather
than up to an hour later.

Claims are capped at roughly 40 explicit ids. A user needing more is modelled
one level up — a district instead of ten clusters. The function **rejects** a
write that would exceed the cap rather than truncating the scope: a truncated
scope is a privilege reduction, but a silent one, and silent is the problem.

## Storage layout

```
omr/{academicYear}/{assessmentId}/{stateId}/{districtId}/{clusterId}/{schoolId}/{date}/OMR_{omrId}.jpg
```

The path encodes the ancestry, so a Storage rule authorises by comparing path
segments with no database lookup. **No student name appears in any object
key** — metadata belongs in the database, behind an access check, not in a
filename that ends up in someone's downloads folder.

Uploads are capped at 8 MB and must be `image/jpeg`. Retention deletion runs
server-side under `enforceRetention` using admin credentials, driven by policy
in `app_config`, and every deletion is audited.

## Changing a rule

1. Change it here, never only in the client.
2. Add or update the corresponding assertion in the emulator suite.
3. Check the matching client-side check still agrees — a rule and a UI that
   disagree produce a permission error that looks like an authorisation bug
   and is really a drift bug.
4. Deploy to `dev` first and confirm the app still works end to end. A rule
   that is too strict fails as loudly as one that is too loose is quiet.

Model and reasoning: [../docs/04-security-model.md](../docs/04-security-model.md).
Schema, ids and guard documents: [../docs/03-firestore-schema.md](../docs/03-firestore-schema.md).
