# Handoff — NATCO Assessment App

Written to brief a new agent/developer picking this up cold. This document is
the **git/release/process** layer; [00-project-status.md](00-project-status.md)
is the living **feature-by-feature** status doc — read that one for
what-is-built detail, this one for where-things-are and what-to-do-next.

Last verified: **2026-09-11**, commit `56d2ee7`, branch `feat/phase-9-sync`.

---

## 1. Repository and branch

| | |
|---|---|
| Remote | `https://github.com/Pradeeppu/Natco-App.git` |
| Working branch | `feat/phase-9-sync` (all work so far is here — **not yet merged to `main`**) |
| Main branch | `main` |
| Local path (this machine) | `D:\natco_app` |
| Git user configured here | `Chinnu-7` |

### Commit history on `feat/phase-9-sync`, oldest to newest

| Commit | What it did |
|---|---|
| `6be2717` | Initial commit — phases 1-9 (partial), 351 files |
| `671386c` | Completed phases 9-11; fixed a `firestore.rules` security gap (users/user_email were deletable — now `allow delete: if false`); repo hygiene (gitignored build artifacts) |
| `cf9e125` | Fixed release build: `compileSdk 37` required by `flutter_secure_storage`/`permission_handler_android` |
| `b3e6a8f` | Phase 5 (partial): real image-quality gate (`ImageQualityAnalyzer`) and durable image write (`OmrImageWriter`) |
| `995a955` | Real release signing config (keystore + `key.properties` + `build.gradle.kts` signing block) |
| `7c02275` | `OmrValidationRepository.createSubmission`; sync-conflict authorization moved from hardcoded roles to `Permission.resolveSyncConflict`; `ScoringEngine` blank/multiple-mark bug fix; `SyncQueueEntry` fields turned into enums |
| `00a2ae5` | Phase 5 complete: real `OmrCaptureScreen` (camera/gallery via `image_picker`, student picker, quality gate, override flow), wired to `createSubmission` |
| `56d2ee7` | **Phase 6: real OMR engine** — `OmrTemplate`, `OmrProcessor` (marker detection, homography, rotation resolution, bubble sampling, classification, confidence), 9 tests against synthetic sheets |

Every commit above is pushed to `origin/feat/phase-9-sync`. Nothing is only
local. Commit messages themselves carry the detailed "why", not just "what" —
`git log -p <sha>` or `git show <sha>` is worth reading before touching a file
that commit touched.

**Not yet done**: no PR opened against `main`, no tag, no merge. That's a
deliberate next-step decision for whoever owns the release process, not an
oversight — say the word and a PR can be opened.

---

## 2. Version and release state

| | |
|---|---|
| App version (`pubspec.yaml`) | `0.1.0+1` — **never bumped this session**; bump it before any real release |
| Release APK | `build\app\outputs\flutter-apk\app-release.apk` (62.6 MB), built 2026-09-10, environment `demo` |
| Signing | **Real release key**, not debug. Verified with `apksigner verify --print-certs`: `CN=NATCO Assessment App, OU=Engineering, O=NATCO, L=Unknown, ST=Unknown, C=IN` |
| Signing key location | `android/keystore/natco-release.jks` (2.3 KB) — **exists only on this machine, gitignored, never committed** |
| Signing key alias | `natco_release` |
| Signing key/store password | `natco-release-2026` (also in `android/key.properties`, gitignored) |
| Play Store submission | **Not done.** The APK is installable/testable now; a Play Store listing, appbundle (`.aab`) build, and store metadata are all separate, un-started work |

### ⚠️ Backup the keystore before anything else

`android/keystore/natco-release.jks` + `android/key.properties` exist **only
on this machine's disk**. They are correctly gitignored (a keystore in git
history is a permanent leak — rotating it doesn't undo the exposure). If this
machine's disk is lost before these are backed up somewhere secure and
private, **no future release can ever be signed as an update to this same app
identity** — Android refuses an update whose new APK isn't signed by the same
key as the one already installed. This is the single highest-priority
non-code action item in this handoff.

### Rebuilding the release APK

```bash
cd D:\natco_app
flutter build apk --release --dart-define=NATCO_ENV=demo   # or prod, once Firebase is configured
```

Two machine-specific fixes are already applied and must travel with any new
checkout of this repo (they're in git, not machine-local):
- `android/gradle.properties` has `kotlin.incremental=false` — Kotlin's
  incremental compiler crashes when the pub cache and the project sit on
  different Windows drive letters (a plain relative-path bug in Kotlin's
  Gradle plugin, not a project bug).
- `android/app/build.gradle.kts` hardcodes `compileSdk = 37`.

Signature verification (needs `apksigner`, not `keytool` — `keytool
-printcert -jarfile` reports "Not a signed jar file" against a correctly v2/v3
-signed APK because it only understands the older JAR scheme):

```bash
export JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"
"C:\Users\<you>\AppData\Local\Android\Sdk\build-tools\<version>\apksigner.bat" \
  verify --print-certs build\app\outputs\flutter-apk\app-release.apk
```

---

## 3. Environment gotchas on this machine (read before running anything)

1. **`flutter` hangs at 100% CPU, prints nothing.** The SDK at
   `C:\Program Files\flutter` isn't writable by the current user;
   `flutter.bat`'s lock-acquire loop retries forever with no error message. Use
   the writable copy instead:
   ```powershell
   $env:FLUTTER_ROOT = "D:\flutter-sdk"
   & "D:\flutter-sdk\bin\flutter.bat" test
   ```
2. **A stale SDK can shadow the right one** — `Get-Command flutter -All` lists
   every match in PATH order if `flutter` resolves to the wrong install.

Full detail: [11-environment-setup.md](11-environment-setup.md#troubleshooting).

---

## 4. What's built vs. not — the short version

Full detail lives in [00-project-status.md](00-project-status.md) §3-4. Summary:

| Phase | Status |
|---|---|
| 1 Foundation | ✅ built, tested |
| 2 Master data | ✅ built, tested |
| Users (unnumbered, added mid-project) | ✅ built, tested |
| 3 Assessments | ✅ built, tested |
| 4 Offline sessions | ✅ built, tested |
| 5 OMR capture | ✅ code complete (camera/gallery capture, quality gate, durable write, `createSubmission`) — **never run on a real phone** |
| 6 OMR engine | ⚠️ built and tested against **synthetic** sheets only (marker detection, homography, rotation resolution, sampling, classification, confidence) — **not wired to a real capture** (no repository method calls it yet, so a captured sheet still just sits at `CAPTURED`); **no measured accuracy exists or is claimed anywhere** |
| 7 OMR Validation | ✅ built, tested |
| 8 Scoring | ✅ built, tested |
| 9 Sync | ✅ built, tested — with one caveat, see §5 below |
| 10 Analytics | ✅ built, tested |
| 11 Reports | ✅ built, tested |
| 12 Hardening | ⚠️ security rules re-checked (deny-by-default holds, no `if true` grant anywhere) — **performance budgets and device soak testing blocked on a physical device** |

**585 of 585 tests passing, `flutter analyze` clean**, as of commit `56d2ee7`.

---

## 5. Known gaps — in priority order for the next agent

These are the concrete, actionable items. Everything here is **device-independent** (buildable and testable without a phone) except where marked.

1. **Phase 6's engine has no caller — highest priority.** `OmrProcessor.process`
   (`lib/features/omr_processing/domain/service/omr_processor.dart`) is real
   and tested, but nothing invokes it against an actual `CAPTURED` submission.
   Needed: a repository method (likely on `OmrValidationRepositoryImpl`,
   following the precedent of its existing narrow phase-6 exceptions like
   `listSubmissionsForAssessment`) that: reads the submission, reads its image
   bytes back off disk (`FileSystemService` currently only has `writeBytes` —
   **a `readBytes` method needs adding first**), decodes via
   `package:image`, runs `OmrProcessor.process` **on a background isolate**
   (Critical Rule 13 — use `compute()` from `package:flutter/foundation.dart`;
   `OmrProcessingResult`/`OmrTemplate`/`ScannerThresholds` are all plain
   Dart — primitives, enums, `Map`/`List` of primitives, `dart:math`'s
   `Point<double>` — so they should cross the isolate boundary without extra
   serialization, but confirm this holds once written), writes the resulting
   `OmrAnswer` rows via the existing `saveAnswer`, and moves
   `processingStatus` `CAPTURED → PROCESSING → PROCESSED` (and, if any answer
   isn't `isAutoAcceptable`, on to `NEEDS_VALIDATION` with `validationStatus`
   set to `pending`) — matching `OmrProcessingStatus.allowedNext` exactly,
   two sequential writes rather than skipping a state. On marker/alignment
   failure, the existing `resetToCaptured`-style transition (already used by
   the sync reconciler) is the precedent to reuse rather than inventing a new
   status — `OmrProcessingStatus` has no "alignment failed" value, and adding
   one means also touching `firebase/firestore.rules`' fixed status-string
   set, which is a bigger, riskier change to make without real data to test
   against.
2. **No repository anywhere enqueues a sync-queue entry.** Checked directly,
   not assumed: `SyncQueueRepository.enqueue` has exactly one caller in the
   whole of `lib/` — itself. `SessionRepositoryImpl`, `OmrValidationRepositoryImpl`
   and every other write path persist locally but never write the matching
   sync-queue record, so nothing captured or created on a device would
   actually reach the sync engine's drain loop. This predates this session
   (already true of session/attendance writes before `createSubmission`
   existed) and is bigger than it sounds — it's a cross-cutting change
   touching several repositories' write paths, each needing its own test
   update. Do this **after** item 1, since item 1 changes what "a submission
   write" looks like.
3. **Calibration screen** (`/settings/calibration`) is still a static mockup —
   sliders don't read/write `ScannerThresholds`, the "upload test OMR" and
   "run the harness" buttons are no-ops. docs/10-omr-calibration-testing.md
   §50 describes a single-sheet ad-hoc flow (upload one image + type in
   ground truth + see a per-question comparison) that's buildable now,
   independent of having a real dataset — it would exercise `OmrProcessor`
   directly rather than needing `tool/omr_eval.dart`. **Do not** let this
   screen show a "measured accuracy" figure from anything less than a real,
   labelled batch — Critical Rule 14 is absolute here.
4. **`tool/omr_eval.dart` harness** (docs/10 §"Harness") does not exist. The
   harness's own logic (read a manifest + images, run `OmrProcessor` per
   image, diff against ground truth, write `summary.json`/`per_sheet.csv`/
   `confusion.csv`) is pure Dart and testable against a tiny synthetic
   "dataset" this repo could generate itself — proving the harness's own
   aggregation math is right. **This still produces no real accuracy number**
   — there is no `omr_dataset/` and no real scanned sheet anywhere in this
   environment. Building the harness ≠ measuring accuracy; keep those two
   claims separate in whatever gets written about it.
5. **Phase 5's camera path has never run on a real device** *(blocked on
   hardware, not code)*. `image_picker`'s camera source, the `CAMERA`
   manifest permission, and `permission_handler`'s request flow are wired but
   unverified end to end.
6. **Phase 12's performance budgets and offline soak test** *(blocked on
   hardware)* — docs/07-omr-pipeline.md's per-stage timing table
   (decode+downscale 150ms, markers 200ms, rectify 150ms, etc., ≤1.0s total)
   has never been measured against a real device.
7. **Play Store release path** *(not started)* — `.aab` build, store
   listing, versioning policy (bump `pubspec.yaml`'s `0.1.0+1`), and a
   decision on whether `feat/phase-9-sync` merges to `main` first.

---

## 6. Rules the next agent must not cross

These are enforced in code/tests already, listed here so nobody "fixes" them
away by accident:

- **Critical Rule 14 — never invent OMR accuracy.** No screen, doc, commit
  message, or comment may state a measured recognition rate without a real
  harness run against a real labelled dataset. The calibration screen's empty
  state and the complete absence of an accuracy figure anywhere in this repo
  are both deliberate and tested (`test/widget/preview_labelling_test.dart`).
- **"Supervisor," never "Coordinator."** A source-tree-scanning test enforces
  this on every run.
- **No student name in filenames, logs, or audit entries.** Report filenames
  are `{reportType}_{timestamp}.csv`; audit `newValue` payloads carry row
  counts/column names, never row values.
- **Users are deactivated, never deleted** — `UserRepository` has no delete
  method, and `firestore.rules` explicitly refuses deleting a `users` or
  `user_email` document.
- **Never commit `android/keystore/`, `android/key.properties`, or any
  Firebase config** (`google-services.json`, `GoogleService-Info.plist`,
  `firebase_options*.dart`, any service-account JSON). All gitignored
  already; don't force-add them.
- **Machine OMR evidence (`OmrAnswer.machineAnswer`/`machineConfidence`/
  `machineStatus`/`optionScores`) is never rewritten once written** —
  `withValidation`/`withScore` are the only mutation paths, and
  `firebase/firestore.rules` refuses a client update touching those fields.

---

## 7. Verifying before you start, and before you hand off again

```bash
cd D:\natco_app
flutter analyze      # must print "No issues found!"
flutter test          # must print "All tests passed!" — 585 tests, no device/backend needed
```

If either isn't clean, don't build on top of the failure — either it's a real
regression (fix it) or a genuine flake (this repo has had exactly one
observed flake all session: a `paged_list_controller_test.dart` timing test
that fails only under full-suite load and passes every time run alone — worth
re-running in isolation before treating a red run as real).

Before pushing: `flutter analyze` clean, `flutter test` clean, then commit
with a message that explains *why*, not just *what* (match the style of the
existing log — every commit above tells you why the change happened), push
to `feat/phase-9-sync`.
