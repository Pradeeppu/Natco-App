# NATCO Data Model

All models are immutable Dart classes. IDs are stable, opaque, and generated
client-side (UUID v4) so that a record created offline keeps its identity
forever — the server never renames it. That property is what makes sync
idempotent.

Conventions:

- `*Id` fields are strings, never sequential integers.
- Timestamps are UTC ISO-8601 on the wire, `DateTime` (UTC) in memory.
- `createdAt` / `updatedAt` on every mutable entity.
- Enums are persisted as `SCREAMING_SNAKE_CASE` strings, and unknown values
  decode to an explicit `unknown` member rather than throwing — a phone running
  an old build must not crash on a value added by the server later.

---

## 1. Identity and access

### AppUser

| Field | Type | Notes |
|-------|------|-------|
| `userId` | String | Firebase Auth UID |
| `email` | String | login identifier |
| `displayName` | String | |
| `phone` | String? | |
| `role` | `UserRole` | exactly one role per user |
| `scope` | `AccessScope` | geographic restriction, below |
| `isActive` | bool | disabled users cannot log in even with a cached session |
| `lastLoginAt` | DateTime? | |
| `createdAt` / `updatedAt` | DateTime | |

### UserRole

```
SUPER_ADMIN | ASSESSMENT_ADMIN | SUPERVISOR | PST_TEACHER | SCANNER_OPERATOR | VIEWER
```

### AccessScope

The scope answers "*which* schools", the permission answers "*what* actions".
Both are checked, on the client for UX and on the server for enforcement.

| Field | Type | Notes |
|-------|------|-------|
| `level` | `ScopeLevel` | `GLOBAL, STATE, DISTRICT, CLUSTER, SCHOOL` |
| `stateIds` | `Set<String>` | |
| `districtIds` | `Set<String>` | |
| `clusterIds` | `Set<String>` | |
| `schoolIds` | `Set<String>` | |
| `gradeSections` | `Set<GradeSection>` | teachers only; grade + section pairs |

`GLOBAL` matches everything. Any other level matches only when the target
entity's ancestry intersects the corresponding id set. A Supervisor with two
cluster ids sees those clusters' schools and nothing else (§31).

### Permission

Fine-grained action tokens, mapped to roles by a single constant matrix
(`lib/features/auth/domain/entity/permission.dart`). See
[04-security-model.md](04-security-model.md) for the full matrix.

---

## 2. Geographic hierarchy

`State → District → Cluster → School → Grade → Section → Student`

Each level stores its parent id **and** a denormalised ancestry, because
security rules and analytics queries both need to filter by any ancestor in a
single indexed comparison.

### StateEntity
`stateId, stateName, stateCode, isActive, createdAt, updatedAt`

### District
`districtId, districtName, districtCode, stateId, isActive, createdAt, updatedAt`

### Cluster
`clusterId, clusterName, clusterCode, districtId, stateId, isActive, createdAt, updatedAt`

### School

| Field | Type |
|-------|------|
| `schoolId` | String |
| `schoolName` | String |
| `schoolCode` | String (unique, enforced server-side) |
| `clusterId`, `districtId`, `stateId` | String (ancestry) |
| `address`, `pincode` | String? |
| `grades` | `List<String>` — grades actually taught |
| `mediumsOfInstruction` | `List<String>` |
| `isActive` | bool |
| `createdAt` / `updatedAt` | DateTime |

Grade and Section are **not** separate collections; they are controlled
vocabularies in `app_config` plus the `grades` list on each school. This avoids
four extra collections for values that never carry their own attributes.

---

## 3. Student master data

### Student

| Field | Type | Notes |
|-------|------|-------|
| `studentId` | String | stable internal id; never reused |
| `externalStudentCode` | String? | state/UDISE code if available |
| `studentName` | String | |
| `gender` | `Gender` | `MALE, FEMALE, OTHER, NOT_SPECIFIED` |
| `dateOfBirth` | DateTime? | |
| `grade` | String | |
| `section` | String | |
| `mediumOfInstruction` | String | |
| `language` | String | |
| `electiveSubject` | String? | |
| `schoolId` | String | |
| `clusterId`, `districtId`, `stateId` | String | ancestry, denormalised |
| `activeStatus` | bool | |
| `dedupeKey` | String | see below |
| `createdAt` / `updatedAt` | DateTime | |

**Duplicate prevention.** `dedupeKey` is a deterministic hash of
`schoolId + normalised(studentName) + grade + section + dateOfBirth`. It is
stored in a uniqueness-enforcing collection so a second write fails rather
than creating a twin. Normalisation lowercases, collapses whitespace and
strips punctuation. Imports report rejected rows instead of merging them —
merging student identities silently is a data-integrity failure, so a human
decides.

### StudentEnrollment

A student's grade/section changes across academic years, and results must stay
attached to the year they were earned.

`enrollmentId, studentId, schoolId, academicYear, grade, section, rollNumber?, isActive, createdAt, updatedAt`

---

## 4. Assessment definition

### Assessment

| Field | Type | Notes |
|-------|------|-------|
| `assessmentId` | String | |
| `assessmentName` | String | |
| `assessmentCode` | String | unique; printed on the OMR sheet |
| `academicYear` | String | e.g. `2026-27` |
| `grade` | String | |
| `subject` | String | |
| `questionCount` | int | |
| `questionType` | `QuestionType` | `MCQ_SINGLE` in v1 |
| `options` | `List<String>` | `[A, B, C, D]` in v1 |
| `durationMinutes` | int | |
| `instructions` | String | |
| `marksPerQuestion` | double | default 1 |
| `negativeMarksPerWrong` | double | default 0 |
| `activeAnswerKeyVersion` | int? | null until a key is published |
| `status` | `AssessmentStatus` | `DRAFT, PUBLISHED, ACTIVE, SCORING_LOCKED, CLOSED, ARCHIVED` |
| `createdAt` / `updatedAt` | DateTime | |

`questionType` and `options` are stored per assessment rather than assumed
globally, which is what allows a future `MCQ_MULTI` or 5-option format without
rewriting scoring: the scorer reads the option set from the assessment.

### AssessmentQuestion
`questionId, assessmentId, questionNumber, options, marks, topic?, difficulty?, createdAt, updatedAt`

Question *text* is deliberately not stored — the paper is printed separately and
v1 analytics only needs per-number performance. The field exists as `topic` for
grouping.

### AnswerKey — versioned, immutable

| Field | Type | Notes |
|-------|------|-------|
| `answerKeyId` | String | |
| `assessmentId` | String | |
| `version` | int | monotonic from 1 |
| `answers` | `Map<int, String>` | question number → correct option |
| `status` | `AnswerKeyStatus` | `DRAFT, PUBLISHED, SUPERSEDED` |
| `publishedBy`, `publishedAt` | String?, DateTime? | |
| `supersededBy` | String? | id of the version that replaced it |
| `changeReason` | String? | mandatory when version > 1 |
| `createdAt` | DateTime | |

Once `status == PUBLISHED`, the document is immutable (enforced by security
rules). A correction creates version *n+1* with a `changeReason`, marks *n*
`SUPERSEDED`, and requires an explicit re-score action that writes
`SCORE_CORRECTED` audit entries. Results record the
`answerKeyVersion` they were scored against, so an old score always remains
explainable (§13, Critical Rules 5–6).

### AssessmentAssignment
`assignmentId, assessmentId, schoolId, grade, sections, assignedTeacherIds, expectedStudentCount, dueDate?, status, createdAt, updatedAt`

Drives "OMRs Expected" in analytics and restricts which assessments a teacher
sees.

---

## 5. Session

### AssessmentSession

| Field | Type |
|-------|------|
| `sessionId` | String |
| `assessmentId`, `schoolId`, `clusterId`, `districtId`, `stateId` | String |
| `grade`, `section`, `subject` | String |
| `academicYear` | String |
| `assessmentDate` | DateTime |
| `teacherUserId` | String |
| `studentIds` | `List<String>` |
| `expectedStudentCount` | int |
| `startedAt`, `endedAt` | DateTime? |
| `status` | `SessionStatus` |
| `syncStatus` | `SyncStatus` |
| `deviceId` | String |
| `createdAt` / `updatedAt` | DateTime |

`SessionStatus`: `DRAFT → STARTED → IN_PROGRESS → COMPLETED → SYNC_PENDING → SYNCED → CLOSED`.
Transitions are validated by a state machine; illegal transitions are rejected
and logged (§47).

---

## 6. OMR

### OmrSubmission

| Field | Type | Notes |
|-------|------|-------|
| `omrId` | String | printed on the sheet; **globally unique** |
| `submissionId` | String | internal id (an omrId may have a superseded replacement) |
| `sessionId`, `assessmentId`, `studentId` | String | `studentId` nullable until identified |
| `schoolId`, `clusterId`, `districtId`, `stateId` | String | |
| `capturedBy` | String | userId |
| `capturedAt` | DateTime | |
| `deviceId` | String | |
| `originalImagePath` | String | local path, then storage path |
| `processedImagePath` | String? | |
| `imageQuality` | `ImageQualityReport` | embedded value object |
| `qualityOverride` | `QualityOverride?` | who forced "Use Anyway", and why |
| `processingStatus` | `OmrProcessingStatus` | state machine, §47 |
| `validationStatus` | `ValidationStatus` | `NOT_REQUIRED, PENDING, IN_PROGRESS, COMPLETED` |
| `duplicateResolution` | `DuplicateResolution?` | `DUPLICATE, REPLACEMENT, INVALID` + resolver + reason |
| `answerKeyVersion` | int? | version used for `machineScore`/`finalScore` |
| `machineScore` | double? | score from machine answers only |
| `finalScore` | double? | score after validation |
| `syncStatus` | `SyncStatus` | |
| `createdAt` / `updatedAt` | DateTime | |

`ImageQualityReport`: `blurScore, brightnessScore, contrastScore, resolutionPx, sheetDetected, markersDetected (0–4), rotationDegrees, perspectiveSkew, verdict (PASS/WARN/FAIL), failureReasons`.

### OmrAnswer

One document per question per submission. **Machine fields are written once
and never updated** (§20, Critical Rule 3).

| Field | Type | Notes |
|-------|------|-------|
| `omrAnswerId` | String | |
| `omrId` | String | |
| `questionNumber` | int | |
| `optionScores` | `Map<String, double>` | per-option darkness 0.0–1.0, kept as evidence |
| `machineAnswer` | String? | |
| `machineConfidence` | double | 0.0–1.0 |
| `machineStatus` | `DetectionStatus` | `HIGH_CONFIDENCE, MEDIUM_CONFIDENCE, LOW_CONFIDENCE, BLANK, MULTIPLE_MARK, UNREADABLE` |
| `finalAnswer` | String? | machine answer, or the validator's decision |
| `finalAnswerSource` | `AnswerSource` | `MACHINE, HUMAN_VALIDATION` |
| `isCorrect` | bool? | null while unscored |
| `marks` | double? | |
| `validatedBy`, `validatedAt` | String?, DateTime? | |
| `validationReason` | String? | |
| `bubbleCropPath` | String? | cropped image shown to the validator |

### OmrValidation

An append-only log of validation decisions, separate from `OmrAnswer` so that
a re-validation does not erase the first one.

`validationId, omrId, questionNumber, machineAnswer, machineConfidence, machineStatus, chosenAnswer, validatorUserId, validatedAt, reason, deviceId`

---

## 7. Results

### Result (per student per assessment)

`resultId, studentId, assessmentId, omrId, sessionId, schoolId, clusterId, districtId, stateId, academicYear, grade, section, answerKeyVersion, totalMarks, marksObtained, percentage, correctCount, incorrectCount, blankCount, multipleMarkCount, scoredAt, scoredBy, isPublished, supersededBy?, createdAt, updatedAt`

Re-scoring writes a **new** result and marks the old one `supersededBy`; scores
are never mutated in place (Critical Rule 5).

### QuestionAnalytics (aggregate, per assessment + scope)

`analyticsId, assessmentId, scopeLevel, scopeId, questionNumber, totalResponses, correctCount, incorrectCount, blankCount, multipleMarkCount, correctPercentage, updatedAt`

Written by a Cloud Function on result publication so that a district dashboard
never fans out over a hundred thousand answer documents from a phone.

---

## 8. Operations

### SyncQueueEntry (local only)

`syncId, entityType, entityId, operation (CREATE/UPDATE/DELETE/UPLOAD_FILE), payloadRef, idempotencyKey, createdAt, attemptCount, lastAttemptAt, nextAttemptAt, status (PENDING/UPLOADING/SYNCED/FAILED/CONFLICT), errorMessage, errorCode`

### AuditLog (append-only, server-written where possible)

`auditId, userId, role, action, entityType, entityId, oldValue, newValue, timestamp, deviceId, appVersion`

Actions: `OMR_CAPTURED, OMR_SCANNED, OMR_VALIDATED, OMR_QUALITY_OVERRIDDEN, OMR_DUPLICATE_RESOLVED, SCORE_GENERATED, SCORE_CORRECTED, ANSWER_KEY_PUBLISHED, ANSWER_KEY_UPDATED, STUDENT_CREATED, STUDENT_UPDATED, ASSESSMENT_STARTED, ASSESSMENT_COMPLETED, SYNC_CONFLICT_RESOLVED, USER_ROLE_CHANGED, SCANNER_THRESHOLDS_CHANGED, LOGIN_SUCCEEDED, LOGIN_FAILED`.

`oldValue` / `newValue` hold redacted JSON — field names and non-personal
values only, never a student's name or date of birth.

### AppConfig (single document, read by all clients)

`configId, scannerThresholds, featureFlags, controlledVocabularies (grades, sections, subjects, mediums, languages), minimumSupportedAppVersion, updatedBy, updatedAt`

Scanner thresholds live here, not in code, so they can be calibrated without
shipping a release (§19, §50). Only Super Admin may write them.
