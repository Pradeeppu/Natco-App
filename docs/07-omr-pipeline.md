# OMR Pipeline Design

> No accuracy number appears in this document. Accuracy is produced by the
> harness in [10-omr-calibration-testing.md](10-omr-calibration-testing.md)
> against a labelled dataset, and nowhere else (Critical Rule 14).

## 1. Scope for v1

Arbitrary OMR sheets are **not** supported (§15). The app reads one controlled
template, the *NATCO v1 sheet*, whose geometry is known at build time. This is
the single most important reliability decision in the product: a known template
turns "find the bubbles" into "sample known positions after alignment", which is
a solvable problem on a low-end phone, offline, with measurable error rates.

### NATCO v1 sheet specification

- A4 portrait, printed at 300 dpi, black on white.
- **Four solid square registration markers**, 12 mm, at the four corners,
  inset 10 mm from each edge. The bottom-left marker carries a 4 mm notch on
  its inner edge — this asymmetry is what lets rotation be resolved absolutely
  rather than to a multiple of 90°.
- A quiet zone of 8 mm inside the marker rectangle.
- **Header block**: assessment name, `assessmentCode`, and the `omrId` printed
  both as human-readable digits and as a 7-digit bubble grid (7 columns × 10
  rows, 0–9). The bubble grid is what the app reads; the printed digits are for
  humans and for manual entry fallback.
- **Answer grid**: `questionCount` rows × 4 option bubbles (A B C D), bubble
  diameter 5 mm, pitch 9 mm, arranged in columns of 25 questions.
- Every bubble position is defined in **normalised template coordinates**
  (0.0–1.0 relative to the marker rectangle), stored in
  `assets/omr_templates/natco_v1.json`. Nothing in the pipeline contains a
  pixel constant.

Storing geometry as data rather than code means a v2 sheet (5 options, 100
questions) is a new JSON file plus a `templateVersion` on the assessment — not
a rewrite. Each submission records the `templateVersion` it was read with.

## 2. Pipeline

```
       Camera / Gallery image
                 │
                 ▼
   ┌─────────────────────────────┐
   │ 1. Decode + downscale       │  work at a fixed long-edge (1600 px);
   │    orientation from EXIF    │  keeps memory flat across devices
   └─────────────────────────────┘
                 │
                 ▼
   ┌─────────────────────────────┐
   │ 2. Image quality analysis   │──► FAIL ─► Retake / Use Anyway* / Cancel
   └─────────────────────────────┘
                 │ PASS or WARN
                 ▼
   ┌─────────────────────────────┐
   │ 3. Sheet + marker detection │──► markers < 4 ─► FAIL (cannot align)
   └─────────────────────────────┘
                 │
                 ▼
   ┌─────────────────────────────┐
   │ 4. Perspective correction   │  homography from 4 markers → rectified sheet
   │ 5. Rotation resolution      │  notch marker fixes absolute orientation
   └─────────────────────────────┘
                 │
                 ▼
   ┌─────────────────────────────┐
   │ 6. Template alignment       │  normalised coords → pixel coords
   │    + local refinement       │  per-block nudge for print/scale drift
   └─────────────────────────────┘
                 │
                 ▼
   ┌─────────────────────────────┐
   │ 7. OMR ID decode            │──► unreadable ─► manual entry, flagged
   └─────────────────────────────┘
                 │
                 ▼
   ┌─────────────────────────────┐
   │ 8. Bubble sampling          │  per-bubble fill ratio, local background
   │ 9. Answer classification    │  → detectedAnswer + status
   │10. Confidence calculation   │  → confidenceScore
   └─────────────────────────────┘
                 │
                 ▼
   ┌─────────────────────────────┐
   │11. Validation decision      │  any non-auto status ⇒ NEEDS_VALIDATION
   └─────────────────────────────┘
                 │
                 ▼
        Scoring (after validation)
```

`*` "Use Anyway" requires `overrideQualityGate`, which teachers and scanner
operators do not have; see [04-security-model.md](04-security-model.md).

Steps 1–10 run in a worker isolate. The UI thread only ever sees a progress
stream and a final result object (§42, Critical Rule 13).

## 3. Step detail

### Step 2 — Image quality analysis

Six independent metrics, each with a configurable threshold in
`app_config.scannerThresholds`. Each returns a 0.0–1.0 score plus a verdict;
the report keeps all six so a rejection can say *why* in one sentence.

| Metric | Method | Failure message |
|--------|--------|-----------------|
| Blur | variance of Laplacian, normalised by image area | "The photo is blurred. Hold the phone steady and retake." |
| Brightness | mean luminance of the sheet region | "The photo is too dark." / "too bright" |
| Contrast | 5th–95th percentile luminance spread | "The sheet is washed out. Avoid direct glare." |
| Shadow/uneven lighting | max deviation of block means across a 4×4 grid | "Part of the sheet is in shadow." |
| Resolution | rectified sheet pixels per template mm | "Move closer to the sheet." |
| Sheet coverage | rectified quad area ÷ frame area | "Fit the whole sheet inside the frame." |

Blur uses variance-of-Laplacian rather than an FFT because it is a single pass
over a downscaled greyscale buffer, which is what a ₹7 000 phone can afford,
and because the threshold is calibratable against real photographs from the
field rather than derived from theory.

### Step 3 — Marker detection

1. Greyscale, then **adaptive** thresholding (mean-C over a window sized from
   the template's marker size). A global Otsu threshold fails on the normal
   field case: a sheet lit from one side.
2. Connected-component labelling; keep components whose area, aspect ratio
   (≈1.0), fill ratio (≈1.0 for a solid square) and position (within the outer
   15% of the frame) match the template's marker spec.
3. Expect exactly four, one per corner quadrant. Fewer → fail with
   "Keep all four corners visible". More → keep the best-scoring candidate per
   quadrant.

### Steps 4–5 — Perspective and rotation

The four marker centroids give a homography onto the template's marker
rectangle; the image is warped to a canonical rectified sheet at a fixed
resolution. Orientation is then resolved by locating the notched marker: the
warp is applied in the one of four rotations that puts the notch bottom-left.
This is why the notch exists — without an asymmetric fiducial, a sheet
photographed upside down aligns perfectly and reads the answer grid inverted,
which is the worst possible failure because it is silent.

### Step 6 — Template alignment refinement

Print scaling, paper stretch and photocopier drift move bubbles by a few pixels
even after a correct homography. For each 25-question block the pipeline
searches a small offset window (±3 px) for the offset that maximises contrast
between expected-bubble and expected-background regions, then applies that
per-block offset. Cheap, and it removes the dominant residual misalignment.

### Step 7 — OMR ID decode

The 7×10 bubble grid is read with the same sampling and classification as the
answer grid. Each digit column must produce exactly one filled bubble at high
confidence; anything else makes the ID `UNREADABLE`, and the app asks the
operator to type the printed ID, recording `omrIdSource = MANUAL`. A guessed ID
would attach a sheet to the wrong student, so guessing is not an option.

The decoded ID is checked against `omr_registry` for duplicates **before**
scoring (§22).

### Step 8 — Bubble sampling

For each bubble position, in the rectified image:

- Sample a disc at 80% of the nominal bubble diameter (avoids the printed ring).
- Compute `meanInk` = 1 − (mean luminance ÷ local background luminance), where
  local background is the median of an annulus around the bubble. Local
  normalisation is what makes a shadowed corner readable.
- Compute `coverage` = fraction of disc pixels below the local threshold.
- `fillScore = clamp01(0.5 * meanInk + 0.5 * coverage)`

Two measures are combined because they fail differently: `meanInk` catches a
faint but complete pencil fill, `coverage` catches a dark but partial tick.
Weights live in `scannerThresholds` and are calibratable.

### Step 9 — Answer classification

Given per-option fill scores, sorted descending as `top1`, `top2`:

```
if top1 < blankThreshold                     → BLANK
else if top2 >= multipleMarkThreshold        → MULTIPLE_MARK
else if (top1 - top2) >= clearMargin
         and top1 >= filledThreshold         → answer = argmax, HIGH_CONFIDENCE
else if (top1 - top2) >= ambiguousMargin     → answer = argmax, MEDIUM_CONFIDENCE
else                                          → answer = argmax, LOW_CONFIDENCE
```

Default thresholds (starting points to be calibrated, **not** validated
values): `blankThreshold 0.25`, `filledThreshold 0.45`,
`multipleMarkThreshold 0.55`, `clearMargin 0.30`, `ambiguousMargin 0.15`.

`UNREADABLE` is produced upstream — when the bubble region could not be sampled
at all (occlusion, tear, missing region).

Worked examples from §18:

| A | B | C | D | Result |
|---|---|---|---|--------|
| 0.10 | 0.91 | 0.12 | 0.09 | `B`, HIGH_CONFIDENCE (margin 0.79) |
| 0.72 | 0.69 | 0.10 | 0.08 | `A`, LOW_CONFIDENCE → validation (margin 0.03) |
| 0.08 | 0.09 | 0.07 | 0.06 | `BLANK` |
| 0.84 | 0.81 | 0.10 | 0.08 | `MULTIPLE_MARK` |

Note the third row of §18's spec: a low-confidence detection still records
`argmax` as the *machine* answer, because the machine's reading is evidence and
must be preserved — but it is never promoted to a `finalAnswer` without a human
(§20, Critical Rule 4). Nothing in this classifier assigns a correct answer on
its own.

### Step 10 — Confidence score

```
confidence = clamp01( w_margin * normalisedMargin
                    + w_fill   * top1
                    + w_image  * imageQualityScore )
```

with `normalisedMargin = (top1 - top2) / max(top1, ε)`. Image quality is folded
in deliberately: an identical bubble pattern read off a shadowed, blurry photo
deserves less confidence than one read off a clean scan, and pretending
otherwise is how a bad photo produces confident nonsense.

### Step 11 — Validation decision

```
needsValidation = answers.any(status ∈ {LOW_CONFIDENCE, MULTIPLE_MARK, UNREADABLE})
                  or omrIdStatus == UNREADABLE
                  or imageQuality.verdict == FAIL   // i.e. was overridden
```

`MEDIUM_CONFIDENCE` does not block publication by default but is surfaced in
the review summary and counted; the threshold set that decides this is
configurable, because whether medium-confidence answers need human eyes is an
empirical question for the calibration dataset to answer, not one to guess.

A submission with `needsValidation == true` **cannot reach `SCORED`**. The state
machine has no transition for it (§39, Critical Rule 4).

## 4. State machine (§47)

```
CAPTURED
   │ quality analysed
   ▼
QUALITY_CHECKED ──► QUALITY_FAILED (terminal unless overridden or retaken)
   │
   ▼
PROCESSING ──► PROCESSING_FAILED ──► (retry) ──► PROCESSING
   │
   ▼
PROCESSED
   │
   ├── needsValidation ──► NEEDS_VALIDATION ──► VALIDATED ──┐
   │                                                        │
   └── no validation needed ─────────────────────────────► READY_FOR_SCORING
                                                            │
                                                            ▼
                                                          SCORED
                                                            │
                                                            ▼
                                                       SYNC_PENDING
                                                            │
                                                            ▼
                                                          SYNCED
```

Also terminal: `DUPLICATE_BLOCKED` (an existing `omrId`, awaiting a resolution
decision) and `UNREADABLE_EVIDENCE_MISSING` (image lost, raised as an
exception).

Transitions go through a single `OmrStateMachine.transition(from, to)` that
returns a `Result`. An illegal transition is rejected, logged as
`unexpected_state_transition`, and never applied — the entity keeps its
previous state rather than entering an invented one.

## 5. Implementation choice: where the pixels are processed

Three options were considered.

| Option | Pros | Cons |
|--------|------|------|
| Pure Dart (`package:image`) | no native code, one codebase, trivially testable, works in `flutter test` on CI | slowest; a full pipeline on a 1600 px buffer is hundreds of ms per sheet |
| Flutter OpenCV wrapper package | fast, rich operators | the ecosystem's wrappers vary in maintenance, add 20–40 MB per ABI, and pin NDK versions; a stale wrapper becomes a blocker at exactly the wrong time |
| Thin native OpenCV layer over a platform channel | fast, we control the surface (5–6 methods), no dependency on a third party's release cadence | native build complexity, needs an Android device/emulator to test |

**Chosen: pure Dart first, behind an interface, with a native accelerator
behind the same interface.**

```dart
abstract interface class OmrImageProcessor {
  Future<QualityMetrics> analyseQuality(Uint8List jpeg);
  Future<MarkerDetection> detectMarkers(Uint8List jpeg);
  Future<RectifiedSheet> rectify(Uint8List jpeg, MarkerDetection markers);
  Future<List<BubbleSample>> sampleBubbles(RectifiedSheet sheet, OmrTemplate t);
}
```

The reasoning: the *algorithm* is the risky part, not the arithmetic. A Dart
implementation lets the whole pipeline be developed and regression-tested
against the labelled dataset on CI, with no device and no emulator — which is
what makes measured accuracy achievable at all. Once the algorithm is
calibrated and its outputs are pinned by golden tests,
`NativeOmrImageProcessor` can replace the arithmetic and be verified against
the *same* golden outputs. Speed is a fixable problem; an uncalibrated,
untestable pipeline is not.

Selection is a feature flag (`omrProcessor: dart | native`), so a device that
regresses can be moved back without a rebuild.

## 6. Performance budget

Per sheet, on a 2 GB / 4-core reference device, measured by the harness — these
are budgets to hold the implementation to, not results:

| Stage | Budget |
|-------|--------|
| decode + downscale | 150 ms |
| quality analysis | 100 ms |
| marker detection | 200 ms |
| rectify | 150 ms |
| ID + bubble sampling (50 q) | 300 ms |
| classification + confidence | 20 ms |
| **total** | **≤ 1.0 s** |

The UI shows a determinate progress indicator driven by the isolate's stage
stream, so a slower device degrades into a visibly working screen rather than a
frozen one. If the budget is missed on the reference device, the native
processor is the remedy — not a lowered threshold.
