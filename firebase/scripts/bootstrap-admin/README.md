# Bootstrap Admin

Creates the first Super Admin account on a fresh Firebase project.

## Why this exists

`firebase/firestore.rules` authorises every request off Auth **custom
claims** (role + scope), which are meant to be written automatically by an
`onUserWrite` Cloud Function whenever a `users/{uid}` document changes. That
function has never been built, and Cloud Functions need the Blaze
(pay-as-you-go) plan besides — this project stays on Spark. Without those
claims, nobody can sign in: a Firebase Auth login can succeed and still hit
`permission-denied` reading its own profile.

The Admin SDK can set custom claims directly, from a service account key,
with no Cloud Function and no Blaze plan required. This script does by hand
what `onUserWrite` would otherwise automate.

## One-time setup

1. Firebase console → Project Settings → Service Accounts → **Generate new
   private key**. Save the downloaded JSON somewhere outside version control
   (this folder's `.gitignore` also covers `*service-account*.json` patterns
   from the repo root, but keep it out of the repo entirely to be safe).
2. `npm install` in this folder.

## Usage

```
node bootstrap-admin.js <path-to-service-account.json>
```

It prompts for an email, password (min 6 characters, not echoed) and
display name, then:

1. Creates the Firebase Auth user.
2. Sets custom claims `{ role: 'SUPER_ADMIN', lvl: 'GLOBAL', st: [], di: [],
   cl: [], sc: [] }` — the Super Admin / global-scope shape
   `AccessScope.toClaims()` produces.
3. Writes the matching `users/{uid}` Firestore document in the shape
   `AppUser.toJson()` / `AccessScope.toJson()` expect.

Sign in from the app with that email and password immediately after.

## Beyond the first account

Re-run this script (or adapt it) for further admin accounts until
`onUserWrite` is built and the project upgrades to Blaze, at which point
claims sync automatically on every `users/{uid}` write and this script is
only needed once, if ever again.
