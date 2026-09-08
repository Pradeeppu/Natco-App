# Offline-First and Sync Strategy

The hard requirement (§51, Critical Rule 9): if the app is killed, the battery
dies, the upload fails, or processing crashes, **the OMR and its metadata
remain recoverable**. Everything below exists to make that true.

## 1. Local-first write path

There is exactly one way a field write happens:

```
user action
    ↓
domain validation (pure, synchronous)
    ↓
┌──────────────────── local commit ────────────────────┐
│ 1. write entity to its Hive box                      │
│ 2. write SyncQueueEntry(PENDING) with idempotencyKey │
└──────────────────────────────────────────────────────┘
    ↓
UI updates from local state (never waits for network)
    ↓
SyncEngine picks the entry up when connectivity allows
```

Steps 1 and 2 are ordered **entity first, queue second**, and both are
idempotent on replay. A crash between them leaves an un-queued entity, which
the reconciler finds on next launch (§4 below) and enqueues. The reverse order
would leave a queue entry pointing at nothing — a lost record that looks like a
sync failure. Losing the *intent* is recoverable; losing the *data* is not.

Hive is used rather than SQLite because the access patterns are
key-lookup and small scans over bounded per-device data, and because
`hive_ce` gives typed boxes without a schema-migration story on device. Where a
query genuinely needs joins (analytics), that runs server-side.

### Image durability

The captured JPEG is written to application documents storage **before** any
processing, under a path derived from the `omrId`, and the file path is recorded
on the submission in the same local commit. Processing failures, crashes, and
low-memory kills therefore never destroy the evidence — the worst case is a
submission stuck in `CAPTURED` with its image on disk, which the recovery scan
picks up.

Images are deleted from the device only after the server confirms the upload
**and** the confirmation is persisted. Confirm-then-delete, in that order.

## 2. What works with no network

| Capability | Offline | How |
|-----------|:-------:|-----|
| Login | ● | cached session record, encrypted, expiring (default 7 days) |
| Assigned school / students | ● | pre-downloaded on last sync, per assignment |
| Assessment + questions | ● | pre-downloaded |
| Answer key (published version) | ● | pre-downloaded with its version number |
| Start / run a session | ● | local write |
| Camera + gallery capture | ● | local file |
| Image quality check | ● | on-device |
| OMR detection | ● | on-device, worker isolate |
| Human validation | ● | local write, appended |
| Score preview | ● | local scoring against the cached key version |
| Sync queue inspection + retry | ● | local |
| Analytics dashboards | — | server aggregates; last-known values shown with an "as of" timestamp |
| Master-data administration | — | requires server authority |
| Report export | — | server-generated |

Pre-download is driven by `AssessmentAssignment`: a teacher's device holds
their assigned schools, their students, their assessments and those
assessments' published answer keys — not the district.

## 3. Sync queue

```
SyncQueueEntry {
  syncId, entityType, entityId, operation,
  payloadRef,            // Hive key, not an inline blob
  idempotencyKey,        // stable across every retry
  createdAt, attemptCount, lastAttemptAt, nextAttemptAt,
  status, errorMessage, errorCode
}
```

Statuses: `PENDING → UPLOADING → SYNCED`, with `FAILED` and `CONFLICT` as
terminal-until-acted-on states (§24).

### Ordering

Entries are drained in dependency order, not insertion order, because a child
uploaded before its parent is a guaranteed server rejection:

```
session → omr_submission → omr_answers → omr_validations → file uploads
```

A dependency map declares the order; within a tier, oldest first.

### Retry policy

Exponential backoff with jitter, computed into `nextAttemptAt`:

```
delay = min(2^attemptCount * 5s, 30min) ± 20% jitter
```

Jitter matters here: thirty teachers in one school reconnecting to the same
weak hotspot at the same moment will otherwise retry in lockstep and
repeatedly collapse the connection.

Errors are classified before retrying:

| Class | Examples | Behaviour |
|-------|----------|-----------|
| Transient | timeout, 5xx, DNS, socket | retry with backoff |
| Auth | expired token | refresh once, then retry |
| Permission | `permission-denied` | stop, `FAILED`, surface to the user — retrying is pointless and looks like a bug |
| Validation | server rejected the payload | stop, `FAILED`, keep the payload for inspection |
| Conflict | server version differs | `CONFLICT`, hand to conflict resolution |

`attemptCount` is never capped into a drop. After a configurable number of
attempts (default 8) an entry stops auto-retrying and appears under
"Retry Failed Uploads" — it is not deleted. **The queue has no eviction
policy.** Nothing is ever removed except on confirmed success or an explicit,
audited human decision.

### Idempotency

Every entry carries a client-generated `idempotencyKey`. The server keeps
`sync_receipts/{idempotencyKey}`; a replay finds the receipt and returns the
original result instead of writing twice. This is what makes "crashed during
upload" safe: the retry either completes the first write or discovers it
already completed.

Combined with client-generated entity IDs and deterministic document IDs
(`{omrId}_q{n}`), a duplicate upload is a no-op rather than a duplicate row.

## 4. Crash recovery

On every launch, before the UI is interactive, a reconciler runs:

1. Any entity in a non-terminal state with no queue entry → enqueue it.
2. Any entry stuck in `UPLOADING` (the app died mid-upload) → reset to
   `PENDING`; the idempotency receipt makes the re-attempt safe.
3. Any submission in `CAPTURED`/`PROCESSING` with an image on disk →
   re-run processing.
4. Any submission whose image file is missing → mark
   `UNREADABLE_EVIDENCE_MISSING`, raise it as an exception for a Supervisor.
   It is never silently dropped.

Step 4 is the one that admits failure honestly instead of hiding it.

## 5. Conflict handling (§52)

Conflicts are detected by version, not by timestamp — clocks on field devices
are not trustworthy. Every syncable entity carries a monotonic `revision`; the
server rejects a write whose `baseRevision` is not current.

On `CONFLICT`, nothing is overwritten. The entry moves to the sync screen and
the user is shown both versions field by field:

```
SYNC CONFLICT — Session 12 Mar, Grade 5-A

Field              Local              Server
Student count      32                 30
Status             COMPLETED          IN_PROGRESS

  [Keep Server]   [Keep Local]   [Create Review Case]
```

- **Keep Server** discards the local change — recorded in the audit log with
  the discarded payload preserved.
- **Keep Local** re-bases the local change onto the server revision and
  retries.
- **Create Review Case** escalates to a Supervisor and leaves both versions
  intact.

`resolveSyncConflict` gates who may choose: teachers and scanner operators can
only create a review case for anything touching scores, validations, or
answers. A field user under pressure should not be the one deciding which
version of a score survives.

## 6. Sync dashboard

`/sync` shows, per state: pending count, uploading, synced today, failed with
their user-facing reason, and conflicts awaiting a decision. Actions:
*Sync Now*, *Retry Failed Uploads*, *Export Diagnostics*. Every failed entry
names what it is (`OMR 0001827, Grade 5-A, captured 10:42`) rather than an
opaque id, because the person looking at the screen has to decide what to do
about it.

## 7. Connectivity detection

`connectivity_plus` reports the interface; `internet_connection_checker_plus`
confirms reachability. Both are needed — a school Wi-Fi that hands out a lease
but has no upstream is the normal case, and treating "connected" as "reachable"
produces a sync engine that hammers a dead link and reports success it never
had.

The engine syncs on: reachability regained, app resumed, a periodic timer while
foregrounded and reachable, and explicit user action. Uploads are metered:
image uploads default to Wi-Fi-only, overridable per device in settings for
teachers on mobile data.
