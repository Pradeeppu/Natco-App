# Firestore Schema

## Collection layout

Top-level collections, flat rather than deeply nested. Nesting OMR answers
under submissions under sessions would force collection-group queries for
every analytics read and make security rules read three parent documents; flat
collections with denormalised ancestry fields (`stateId`, `districtId`,
`clusterId`, `schoolId`) let one indexed `where` clause answer both the
authorization question and the analytics question.

```
users/{userId}
roles/{roleId}                        # role → permission matrix, read-only mirror of code
states/{stateId}
districts/{districtId}
clusters/{clusterId}
schools/{schoolId}
students/{studentId}
student_dedupe/{dedupeKey}            # existence = "this student already exists"
student_enrollments/{enrollmentId}
assessments/{assessmentId}
assessment_questions/{questionId}
answer_keys/{answerKeyId}             # {assessmentId}_v{version}
assessment_assignments/{assignmentId}
assessment_sessions/{sessionId}
omr_submissions/{submissionId}
omr_registry/{omrId}                  # existence = "this OMR ID was used"
omr_answers/{omrAnswerId}             # {omrId}_q{questionNumber}
omr_validations/{validationId}
results/{resultId}
question_analytics/{analyticsId}      # {assessmentId}_{scopeLevel}_{scopeId}_q{n}
scope_analytics/{analyticsId}         # rollup metrics per scope
audit_logs/{auditId}
app_config/global                     # single document
sync_receipts/{idempotencyKey}        # server-side idempotency ledger
```

`sync_queue` is **local only** (Hive). It describes this device's pending work
and has no business being on the server.

## Deterministic document IDs

Where an ID can be derived, it is — this is the cheapest possible idempotency
and duplicate guard, because a create with an existing ID can be rejected by a
rule rather than detected by a query.

| Collection | ID formula |
|------------|-----------|
| `answer_keys` | `{assessmentId}_v{version}` |
| `omr_answers` | `{omrId}_q{questionNumber}` |
| `omr_registry` | `{omrId}` |
| `student_dedupe` | `sha256(schoolId|name|grade|section|dob)` |
| `question_analytics` | `{assessmentId}_{scopeLevel}_{scopeId}_q{n}` |
| `sync_receipts` | client-generated `idempotencyKey` |

## Uniqueness enforcement

Firestore has no unique constraints, so uniqueness is implemented as
**existence of a guard document created in the same transaction**:

```
Creating OMR submission 0001827:
  transaction:
    read  omr_registry/0001827
    if exists → abort with DUPLICATE_OMR (return the existing submission's
                school/date/time for the duplicate dialog, §22)
    create omr_registry/0001827 { submissionId, schoolId, capturedAt, capturedBy }
    create omr_submissions/{submissionId}
```

The same pattern guards `student_dedupe`. A transaction is used rather than a
`create`-only rule so the caller receives the *previous* submission's details
to show, not just a permission error.

## Indexes

`firebase/firestore.indexes.json` defines the composite indexes. The ones that
matter:

| Collection | Fields |
|------------|--------|
| `students` | `schoolId ASC, grade ASC, section ASC, studentName ASC` |
| `students` | `clusterId ASC, activeStatus ASC, studentName ASC` |
| `omr_submissions` | `schoolId ASC, assessmentId ASC, capturedAt DESC` |
| `omr_submissions` | `validationStatus ASC, clusterId ASC, capturedAt ASC` |
| `omr_submissions` | `sessionId ASC, processingStatus ASC` |
| `omr_answers` | `omrId ASC, questionNumber ASC` |
| `results` | `assessmentId ASC, schoolId ASC, percentage DESC` |
| `results` | `studentId ASC, assessmentId ASC, isPublished ASC` |
| `assessment_sessions` | `teacherUserId ASC, status ASC, assessmentDate DESC` |
| `assessment_assignments` | `schoolId ASC, status ASC, dueDate ASC` |
| `audit_logs` | `entityType ASC, entityId ASC, timestamp DESC` |
| `audit_logs` | `userId ASC, timestamp DESC` |

## Pagination

No screen loads an unbounded collection. Every list query carries
`.limit(pageSize)` with a cursor (`startAfterDocument`), default page size 25
for lists and 200 for background exports. A school with 2 000 students is
scrolled, not loaded (§42).

## Offline persistence

Firestore's own offline cache is enabled, but it is **not** the offline
strategy — it is a nicety for read-mostly admin screens. Field-critical writes
go through Hive + the sync queue, because Firestore's pending-write queue is
opaque, unbounded in failure modes, and cannot express "retry with backoff and
show me the failures". See [06-offline-sync-strategy.md](06-offline-sync-strategy.md).

## Storage layout

Deterministic, ancestry-derived paths; no student names anywhere in a key
(§33, Critical Rule 11):

```
omr/{academicYear}/{assessmentId}/{stateId}/{districtId}/{clusterId}/{schoolId}/{yyyy-MM-dd}/OMR_{omrId}.jpg
omr_processed/{...same...}/OMR_{omrId}_aligned.jpg
omr_crops/{...same...}/OMR_{omrId}_q{n}.jpg
reports/{academicYear}/{assessmentId}/{scopeLevel}/{scopeId}/{reportType}_{timestamp}.csv
```

Because the path itself encodes the ancestry, a Storage rule can authorize a
read by comparing path segments against the caller's scope without a database
lookup.

## Cloud Functions

Functions exist only where the client cannot be trusted or cannot be
efficient:

| Function | Trigger | Purpose |
|----------|---------|---------|
| `onUserWrite` | Firestore `users/{id}` | mirror `role` + `scope` into Auth custom claims so rules read them cheaply |
| `submitOmrBundle` | callable | idempotent write of submission + answers + registry guard in one transaction; returns duplicate details on conflict |
| `publishAnswerKey` | callable | validate completeness, freeze version *n*, supersede *n-1*, write audit entry |
| `scoreSubmission` | Firestore `omr_submissions` update → `READY_FOR_SCORING` | authoritative scoring against the published key; writes `results` + audit |
| `rescoreAssessment` | callable (Super Admin) | re-score after a key correction, superseding old results |
| `aggregateAnalytics` | Firestore `results` write | incremental rollups into `question_analytics` + `scope_analytics` |
| `enforceRetention` | scheduled | apply the configured retention policy to images and logs |

Scoring runs server-side as the authority even though the client also scores
locally: the phone's score gives the teacher an immediate preview, the
function's score is what analytics and reports use. When they disagree the
discrepancy is logged rather than silently reconciled.
