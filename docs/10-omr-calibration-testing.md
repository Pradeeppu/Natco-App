# OMR Calibration and Accuracy Testing

The goal is **not** maximum automatic recognition (§49). It is:

> Automatically process clear sheets, and safely route uncertain sheets to
> human validation.

A pipeline that reads 99% of sheets and silently misreads 1% is worse than one
that reads 90% and flags the other 10%, because the first one puts wrong scores
on children's records with no signal that anything went wrong.

## 1. The dataset

`omr_dataset/` (kept outside the app bundle; large binaries via Git LFS or an
internal bucket, never in the APK).

```
omr_dataset/
├── manifest.json          # one entry per image, with its ground truth
├── images/
│   ├── clean/             # flatbed-scanned reference sheets
│   ├── synthetic/         # generated: known truth, controlled degradation
│   └── field/             # real photographs from schools
└── reports/               # harness output, one directory per run
```

Every image carries ground truth: the true `omrId` and, per question, the true
label — one of `A|B|C|D|BLANK|MULTIPLE|DAMAGED`. Ground truth for field images
is entered by two independent people; disagreements are adjudicated and the
disagreement rate is itself reported, because it bounds how well any scanner
can be said to do.

### Required cases (§48)

Synthetic generation covers, at graded severities: rotation (±1°, ±5°, ±15°,
90°, 180°), perspective (mild/severe), low light, over-exposure, one-sided
shadow, gaussian and motion blur, JPEG compression, print scale drift,
faint marks, partial fills, erased marks, multiple marks, blanks, and torn or
folded corners. Physical cases — real pencil pressure, real erasures, real
photocopier drift, sheets photographed on a desk in a classroom — come only
from `field/`. Synthetic data calibrates; field data decides.

**No student data is used.** Field sheets are collected with consent using
placeholder identities, and the dataset holds no real student's answers
(§53, §35).

## 2. The harness

```
dart run tool/omr_eval.dart --dataset omr_dataset --thresholds config/thresholds.json
```

Runs the real pipeline — the same `OmrImageProcessor` implementation the app
uses, at the same `templateVersion` — over every image and writes
`reports/<timestamp>/`:

```
summary.json      metrics below
per_sheet.csv     one row per image: id, decoded id, agreement, timings
per_question.csv  one row per question: truth, machine, status, confidence
confusion.csv     truth × machine label matrix
failures/         rendered overlays for every disagreement
```

Rendered overlays matter: when the harness says a sheet disagreed, the
overlay shows exactly which bubble was sampled where, which is the difference
between fixing the cause and adjusting a threshold until the number improves.

## 3. Metrics reported

Per run, overall and sliced by degradation category and by severity:

| Metric | Definition |
|--------|------------|
| Per-question accuracy | correct machine labels ÷ all questions |
| Per-sheet accuracy | sheets with **all** questions correct ÷ all sheets |
| OMR ID decode rate | IDs decoded ÷ sheets; and ID decode error rate |
| False positive rate | truth `BLANK` but machine returned an option |
| False negative rate | truth an option but machine returned `BLANK` |
| Blank detection accuracy | recall and precision on `BLANK` |
| Multiple-mark detection accuracy | recall and precision on `MULTIPLE` |
| Low-confidence detection rate | share routed to validation |
| **Silent error rate** | high-confidence answers that are wrong |
| Validation efficiency | share of routed answers that a human actually changed |
| Stage timings | p50 / p95 per pipeline stage |

**Silent error rate is the release gate.** A high-confidence wrong answer is
the only failure mode with no human in front of it, so it is the number that
governs the thresholds. Low-confidence detection rate is a *cost* metric — it
measures how much human work the scanner asks for — and it is traded against
silent errors deliberately, with both numbers on the table.

Validation efficiency guards the other direction: if humans almost never
change what was routed to them, the thresholds are too timid and are wasting
the field's time.

## 4. Calibration loop

```
label dataset → run harness → read confusion matrix + overlays
    → adjust thresholds (or fix the algorithm) → re-run
    → accept only if silent error rate does not regress
```

Thresholds are a JSON document, versioned in git, published to
`app_config/global.scannerThresholds`. A calibration run records which
threshold set produced which metrics, so any number in a report can be traced
to the configuration that produced it.

Golden tests pin the pipeline's output on a small committed subset, so an
algorithm change that alters any label fails CI and has to be justified
against a fresh harness run rather than landing quietly.

## 5. Calibration screen (§50, admin-only)

`/settings/calibration`, gated on `calibrateScanner` (Super Admin only —
teachers cannot change scanner thresholds):

```
Upload test OMR (or pick a bundled sample)
        ↓
Run scanner with current or draft thresholds
        ↓
Enter / load ground truth
        ↓
Show per-question comparison + overlay
        ↓
Show accuracy for this batch
        ↓
[Save thresholds]  → writes app_config + SCANNER_THRESHOLDS_CHANGED audit entry
```

The screen shows the *previous* and *proposed* metrics side by side. A
threshold change that improves per-question accuracy while increasing the
silent error rate is rejected by the screen, not merely warned about.

## 6. Honest reporting

- No accuracy claim is made anywhere in this repository unless a harness run
  produced it, and the claim carries the run id, the dataset revision, the
  threshold version and the `templateVersion`.
- Accuracy is reported per degradation category. A single headline number
  hides the case that matters — the badly lit photograph.
- When accuracy on a category is unknown because the dataset lacks that case,
  the report says *unmeasured*. It does not interpolate.
