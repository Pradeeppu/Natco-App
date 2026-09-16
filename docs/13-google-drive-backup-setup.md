# Google Drive backup setup

## What this is, and what it isn't

`OmrDriveBackupService`
(`lib/features/omr_capture/domain/service/omr_drive_backup_service.dart`)
backs up a copy of every captured OMR image to a shared Google Drive folder,
right after `OmrCaptureScreen` finishes writing it durably to local disk
(Critical Rule 12) and enqueuing the real submission. It is:

- **Server-side auth, deliberately.** Nobody signs into Google on a device.
  One Google credential — a service account — is provisioned once by a
  super admin and lives only in a Cloud Function's secrets
  (`firebase/functions/`). The app calls that function
  (`backupOmrCapture`) over the same authenticated session every other
  backend call already uses (Firebase Auth); the function is the only thing
  that ever talks to Drive. A per-user Google sign-in button was considered
  and rejected: any credential shipped to a phone — a saved OAuth token
  included — can be pulled out of the APK by anyone who has it, which a
  server-side secret cannot be.
- **Fire-and-forget.** The call runs unawaited from the capture screen
  (`omr_capture_screen.dart`, `_submit`) so a slow or failed backup never
  blocks capture. A visible snackbar confirms success; failure is silent by
  design, matching this being a convenience copy, not the system of record.
- **Not the sync pipeline.** The real submission still goes through
  `SyncQueueRepository` exactly as it did before this existed. Nothing about
  scoring, validation or offline sync depends on this backup succeeding.

None of the Google Cloud / Firebase configuration below exists in this
repository — it's per-deployment setup, the same category as the Firebase
project itself or the release keystore (`docs/HANDOFF.md` §2), not code.
**Also true as of this writing** (see `docs/00-project-status.md`): this app
has never been connected to a real Firebase project at all — no
`google-services.json`, no `GoogleService-Info.plist`, no `.firebaserc`.
Deploying this function is only possible once that connection exists.

## Architecture

```
OmrCaptureScreen
  -> OmrDriveBackupService.backup(file, folderName, fileName)   (Dart, client)
  -> Cloud Function `backupOmrCapture`                          (Node, server)
       - rejects unless the caller has a signed-in Firebase session
       - reads the DRIVE_SERVICE_ACCOUNT_KEY / DRIVE_ROOT_FOLDER_ID secrets
       - finds-or-creates a per-assessment subfolder under the root folder
       - uploads the image into it
  -> Google Drive, as the service account
```

The function's logic is split the same way every other testable piece of
this app is: `firebase/functions/src/driveBackup.ts` (`backupToFolder`) is
pure and unit-tested (`driveBackup.test.ts`, against a fake); `index.ts` and
`realDriveFilesApi.ts` wrap it with the real `googleapis` client and the
`onCall` trigger.

## 1. Create the service account

In the same Google Cloud project as this app's Firebase project (Cloud
Console → IAM & Admin → Service Accounts → Create Service Account). No IAM
role is required — Drive access comes from *sharing*, not IAM, per the next
step. Create a JSON key for it and keep the file private; it's the one
credential this whole feature depends on.

## 2. Create and share a root Drive folder

In a real Google account's Drive (a super admin's, or — better, if
available — a Google Workspace **Shared Drive** so the backup isn't tied to
one person's account):

1. Create a folder, e.g. "NCP Assessments — OMR Backups".
2. Share it with the service account's `client_email` (found in the JSON
   key), granting **Editor**.
3. Copy the folder's id from its URL
   (`https://drive.google.com/drive/folders/<this part>`).

The function only ever creates things *inside* this folder — never
Drive-wide — so this is the one place a human can actually open the backups
in Drive's own UI; a bare service account's own "My Drive" isn't
practically browsable.

## 3. Enable the Drive API

Cloud Console → APIs & Services → Library → search **Google Drive API** →
Enable, on the same project.

## 4. Store the two secrets

2nd-gen Cloud Functions secrets (Secret Manager), not the deprecated
`functions.config()`:

```bash
cd firebase
firebase functions:secrets:set DRIVE_SERVICE_ACCOUNT_KEY   # paste the JSON key's full contents
firebase functions:secrets:set DRIVE_ROOT_FOLDER_ID         # paste the folder id from step 2
```

Neither value is ever committed — `firebase/functions/.gitignore` also
excludes `node_modules/` and the compiled `lib/` output.

## 5. Build and deploy the function

```bash
cd firebase/functions
npm install
npm run build
firebase deploy --only functions:backupOmrCapture
```

`firebase/firebase.json`'s `functions` block points at this directory.

## 6. Nothing else is app-side configuration

The Flutter app only needs `cloud_functions` (already a dependency) and a
real Firebase connection to call `backupOmrCapture` — there is no client
ID, secret or service-account key to paste into the Dart code, and none
should ever be committed if one existed. `google_sign_in`, `googleapis` and
`googleapis_auth` were removed from `pubspec.yaml` entirely — the client no
longer talks to Google directly at all.

## 7. Verifying

**Without a real Google account or deployed function (already done, runs
locally):**

- Node side — the actual Drive folder-reuse / create-if-missing / upload
  logic:
  ```bash
  cd firebase/functions
  npm install
  npm run build   # tsc, full type-check
  npm test        # jest, against a fake DriveFilesApi
  ```
- Dart side — the client's encode-call-decode contract:
  ```bash
  flutter test test/features/omr_capture/omr_drive_backup_service_test.dart
  ```
  This exercises `FirebaseOmrDriveBackupService` against an injected fake
  invoker (`FirebaseFunctions.instance` itself isn't fakeable), proving the
  file is base64-encoded correctly, a `{success: true}` response returns
  `true`, and any thrown exception is swallowed to `false` rather than
  propagating into the capture flow.

**End to end (needs a real Firebase project connection, a deployed
function, and a real device, once everything above is provisioned):**

1. Sign in to the app as any role, capture an OMR sheet.
2. No Google sign-in prompt ever appears — only the app's own sign-in,
   already required for everything else.
3. On success, a snackbar reads "Image backed up to Google Drive
   (OMR_Captures_&lt;assessmentId&gt;)".
4. Confirm the per-assessment subfolder and file exist inside the root
   folder shared in step 2.
5. Turn off network before capturing: confirm the sheet still saves and the
   submission still enqueues — the snackbar simply never appears, and
   nothing else in the capture flow is affected.

This last, real-device-and-deployed-function pass has not been run in this
environment — there is no Firebase project connection, deployed function,
physical device, or Google Drive account available here. That is the one
item this document cannot close out by itself.
