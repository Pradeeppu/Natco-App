# Manual user provisioning

Creates real user accounts by hand: Auth user + Firestore profile + custom
claims, all in one step, from a service account.

## Why this exists

`firebase/firestore.rules` authorises every request off Auth **custom
claims** (role + scope), meant to be written automatically by an
`onUserWrite` Cloud Function whenever a `users/{uid}` document changes. That
function has never been built, and Cloud Functions need the Blaze
(pay-as-you-go) plan besides — this project stays on Spark. Without those
claims, nobody can sign in: a Firebase Auth login can succeed and still hit
`permission-denied` reading its own profile.

The in-app "Add user" screen is guarded against this
(`lib/features/users/data/service/manual_provisioning_user_data_source.dart`)
so it fails loudly with a clear message instead of quietly creating a
Firestore document nobody can ever sign in as. These scripts are the real
onboarding path until `onUserWrite` is built and the project moves to Blaze.

The Admin SDK can set custom claims directly from a service account key —
Cloud Functions aren't the only way to set them — so these scripts do by
hand what `onUserWrite` would otherwise automate.

## One-time setup

1. Firebase console → Project Settings → Service Accounts → **Generate new
   private key**. Save the downloaded JSON somewhere outside version control
   (this folder's `.gitignore` also covers `*service-account*.json` patterns
   from the repo root, but keep it out of the repo entirely to be safe).
2. `npm install` in this folder.

## Creating the first Super Admin

```
node bootstrap-admin.js <path-to-service-account.json>
```

Prompts for email, password (min 6 characters, not echoed) and display
name, then creates a `SUPER_ADMIN` account with global scope. Use this once,
for the very first account on a fresh project.

## Creating any other account

```
node create-user.js <path-to-service-account.json>
```

Prompts for email, password, display name, phone (optional), role (any of
the six roles), and scope:

- `GLOBAL` — no further input (Super Admin only, in practice).
- `STATE` / `DISTRICT` / `CLUSTER` — a comma-separated list of ids at that
  level.
- `SCHOOL` — a comma-separated list of school ids. The script looks each one
  up in the `schools` collection and denormalises its state/district/cluster
  ancestry onto the new user's scope, exactly like
  `UserRepositoryImpl._resolveScope` does for accounts created through the
  app in demo mode. You'll then be asked for an optional grade-section
  narrowing (e.g. `5-A,5-B`) — leave blank for every class in those schools.

It refuses to run if an account already exists for that email (checked via
the same `user_email/{email}` guard document `FirestoreUserDataSource` uses),
and writes the Firestore profile in the exact shape `AppUser.toJson()` /
`AccessScope.toJson()` expect, and custom claims in the exact shape
`AccessScope.toClaims()` produces.

Sign in from the app with the given email and password immediately after.

## Changing an existing user's role or scope

Not yet scripted — editing through the app's "Edit user" screen updates the
Firestore document (and bumps `claimsVersion` so the session knows it's
stale) but **not** the actual Auth custom claims, since only a service
account can set those. Until `onUserWrite` exists, a role/scope change needs
a manual claims update to take effect; ask before relying on an edited
account's new permissions.

## Beyond onboarding by hand

Once `onUserWrite` is built and the project upgrades to Blaze, claims sync
automatically on every `users/{uid}` write, the in-app "Add user" screen's
guard (`ManualProvisioningUserDataSource`) can be removed, and these scripts
are only needed again if Blaze is ever turned off.
