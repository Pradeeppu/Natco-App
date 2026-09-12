# Handoff — NATCO Assessment App

Written to brief a new agent/developer picking this up cold. This document is
the **git/release/process** layer; [00-project-status.md](00-project-status.md)
is the living **feature-by-feature** status doc — read that one for
what-is-built detail, this one for where-things-are and what-to-do-next.

Last verified: **2026-09-12**, commit `a8a05bd`, branch `feat/phase-9-sync`.

**If you are picking this up cold, read §0 first** — it's the delta since the
`56d2ee7` handoff below, including one real bug a second agent's otherwise-good
work introduced and how it was caught. Commit `a8a05bd` (after `1349ecd`)
closed known-gap items 3-4 below (calibration screen, `tool/omr_eval.dart`
harness) — `flutter analyze` clean, `flutter test` 601/601 passing.

---

## 0. What changed since the last handoff (commit `1349ecd`)

A second agent picked up known gaps #1 and #2 from §5 below (phase 6's engine
had no caller; no repository enqueued a sync-queue entry) and wired both,
closely following the plan this document laid out:

- `OmrValidationRepository.processSubmission` now reads a `CAPTURED`
  submission's image bytes (`FileSystemService.readBytes`, added), decodes
  them, and runs `OmrProcessor.process` on a background isolate via
  `compute()` (Critical Rule 13), then writes the resulting `OmrAnswer` rows
  and advances `processingStatus` to `PROCESSED`/`NEEDS_VALIDATION` — or
  resets to `CAPTURED` on alignment failure, reusing the reconciler's existing
  precedent rather than inventing a new status, exactly as suggested.
- `SessionRepositoryImpl` and `OmrValidationRepositoryImpl` now call
  `SyncQueueRepository.enqueue` on every write that previously persisted
  locally and stopped there (session create/status-change/attendance/omr
  attach; submission create/update; answer validation; validation record).

**This work was sound, but shipped one real, non-obvious bug**, found by
actually running the suite rather than trusting the diff: `flutter analyze`
was clean, but `flutter test` had exactly one failure —
`preview_labelling_test.dart`'s `/results?assessmentId=as_demo_midline_g5`
case — and it failed as a `pumpAndSettle` **timeout**, not a clean assertion
failure. That shape of failure is a symptom worth recognizing on sight: it
almost always means something is awaiting a resource that was never actually
initialized for the environment the test runs under, not a logic bug in the
test's own assertion.

Root cause: `syncQueueDataSourceProvider` in `service_locator.dart` built a
`HiveSyncQueueDataSource` unconditionally. Every *other* data-source provider
in this file branches on `config.environment.usesFirebase` — demo mode and
every widget test (which run under `AppEnvironment.demo`) get an in-memory
implementation, since Hive boxes are opened during real app init and never
during a widget test. `syncQueueDataSourceProvider` was the one provider that
didn't follow this convention — harmless for phases 1-8 because nothing ever
called `enqueue`, but the moment this pass wired real callers, demo mode and
every widget test started hitting a Hive box that was never opened, which
hangs rather than throwing a catchable error.

Fixed by adding `InMemorySyncQueueDataSource` (mirrors
`InMemoryResultDataSource`'s shape) and giving `syncQueueDataSourceProvider`
the same `usesFirebase` branch every sibling provider already has. Confirmed
by reverting to a stash of the pre-fix diff and re-running the single failing
test against the untouched baseline first — it passed clean there, proving
the failure was a real regression from the new diff, not a pre-existing flake
— then re-running it and the full suite against the fix.

**The lesson for whoever touches `service_locator.dart` next**: if you add a
new provider that reads from a Hive box, a real file, or anything else that
only exists once real app init has run, it needs the `if
(!config.environment.usesFirebase) { return InMemory... }` branch *before*
anything calls it for real — not after, when the failure mode is a hang deep
inside an unrelated screen's widget test rather than an obvious constructor
error.

`flutter analyze`: clean. `flutter test`: 585/585 passing, confirmed after
the fix, not assumed from the diff alone.

---

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
| `fdfc81f` | Add HANDOFF.md |
| `1349ecd` | Wire phase 6 engine to captures (`processSubmission`) and enqueue sync-queue entries on every write path (closes known gaps #1-#2 below); fixed a demo/test-mode regression this exposed in `syncQueueDataSourceProvider` (see §0) |
| `553bbb9` | Docs only — HANDOFF.md §0 and project-status.md updated for `1349ecd` |
| `a8a05bd` | Wire calibration screen to real thresholds + single-sheet test flow, and build `tool/omr_eval.dart` (closes known gaps #3-#4 below) |

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
| 6 OMR engine | ⚠️ built and tested against **synthetic** sheets only (marker detection, homography, rotation resolution, sampling, classification, confidence) — **now wired to a real capture** (`OmrValidationRepository.processSubmission`, commit `1349ecd`) but still **no measured accuracy exists or is claimed anywhere**, and still no calibration harness or real dataset |
| 7 OMR Validation | ✅ built, tested |
| 8 Scoring | ✅ built, tested |
| 9 Sync | ✅ built, tested — every repository write path now enqueues a sync-queue entry (commit `1349ecd`); one caveat remains, see §5 below |
| 10 Analytics | ✅ built, tested |
| 11 Reports | ✅ built, tested |
| 12 Hardening | ⚠️ security rules re-checked (deny-by-default holds, no `if true` grant anywhere) — **performance budgets and device soak testing blocked on a physical device** |

**585 of 585 tests passing, `flutter analyze` clean**, as of commit `56d2ee7`.

---

## 5. Known gaps — in priority order for the next agent

These are the concrete, actionable items. Everything here is **device-independent** (buildable and testable without a phone) except where marked.

1. ~~Phase 6's engine has no caller~~ — **done, commit `1349ecd`.**
   `OmrValidationRepository.processSubmission` reads the submission, reads its
   image bytes off disk (`FileSystemService.readBytes`, added), decodes via
   `package:image`, runs `OmrProcessor.process` on a background isolate via
   `compute()`, writes the resulting `OmrAnswer` rows, and moves
   `processingStatus` accordingly (or resets to `CAPTURED` on alignment
   failure, reusing the reconciler's precedent). See §0 above.
2. ~~No repository anywhere enqueues a sync-queue entry~~ — **done, commit
   `1349ecd`.** `SessionRepositoryImpl` and `OmrValidationRepositoryImpl` now
   call `SyncQueueRepository.enqueue` on every write path. Fixing this
   surfaced a real demo/test-mode regression, described in §0 — worth reading
   before touching `service_locator.dart` again.
3. ~~Calibration screen is a static mockup~~ — **done, commit
   `a8a05bd`.** Sliders now build a real `ScannerThresholds` draft; "Upload
   test OMR" picks a real image (gallery), a ground-truth text field takes
   one label per question (`A`/`B`/`C`/`D`/`BLANK`/`MULTIPLE`, comma- or
   newline-separated), and "Run" actually decodes the image and calls
   `OmrProcessor.process` on a background isolate with the slider-derived
   thresholds, then shows a real per-question comparison (match/mismatch,
   machine status, confidence). The screen moved from `_previewRoutes` to
   `_realRoutes` in `preview_labelling_test.dart` accordingly. **Still not
   built, deliberately**: there is no `app_config`/Firestore
   threshold-persistence layer anywhere in this app yet, so "Save
   thresholds" (docs/10 §50's last step) doesn't exist — the sliders' values
   are used for the single-sheet test only, not persisted. The "measured
   accuracy across a dataset" section still shows an honest empty state,
   because a single sheet is not a golden dataset (Critical Rule 14).
4. ~~`tool/omr_eval.dart` harness does not exist~~ — **done, commit
   `a8a05bd`.** Reads `<dataset>/manifest.json` (a JSON array of `{id,
   image, omrId, answers}`), runs the real `OmrProcessor` over every listed
   image, and writes `summary.json`/`per_sheet.csv`/`per_question.csv`/
   `confusion.csv` to `<dataset>/reports/<timestamp>/`. Its aggregation math
   (`summarize()` in `tool/omr_eval.dart`) is proven by
   `test/tool/omr_eval_test.dart` against a 3-sheet synthetic dataset drawn
   in-memory (reusing `test/support/synthetic_omr_sheet.dart`, extracted
   from `omr_processor_test.dart` so both share one drawing), with ground
   truth chosen to deliberately disagree with what was actually drawn on two
   of the three sheets — proving the harness *notices* disagreement, not
   just that it runs. The CLI path itself (arg parsing, manifest/image file
   I/O, report writing) was also smoke-tested by hand against a real
   on-disk tiny dataset (`dart run tool/omr_eval.dart --dataset <dir>`),
   not only through the pure-function unit test. **This still produces no
   real accuracy number for the scanner** — there is no `omr_dataset/` and
   no real scanned sheet anywhere in this environment; running the harness
   here finds no manifest and reports nothing. Not built: per-stage timings
   (only total per-sheet wall-clock is measured — `OmrProcessor` exposes no
   per-stage instrumentation) and rendered failure overlays (docs/10 §2) —
   both noted honestly in the harness's own doc comment rather than faked.
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
