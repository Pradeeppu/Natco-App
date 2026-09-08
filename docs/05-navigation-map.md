# Navigation Map

Declarative routing with `go_router`. Every route declares the permission it
requires; the router refuses to build a screen the current user may not see,
and the shell's navigation bar only renders destinations the user can reach
(§36 "Only show screens allowed for the user's role").

Client-side guards are a usability feature. They are **not** the security
boundary — that is Firestore/Storage rules plus Cloud Functions
([04-security-model.md](04-security-model.md)).

## Route table

| Path | Screen | Required permission |
|------|--------|---------------------|
| `/splash` | bootstrap / session restore | — |
| `/login` | login | — (unauthenticated only) |
| `/dashboard` | role-specific dashboard | `viewDashboard` |
| `/schools` | school list + hierarchy browse | `viewSchools` |
| `/schools/:schoolId` | school detail | `viewSchools` |
| `/students` | student list, search, import | `viewStudents` |
| `/students/:studentId` | student detail | `viewStudents` |
| `/assessments` | assessment list | `viewAssessments` |
| `/assessments/:assessmentId` | assessment detail, questions, keys | `viewAssessments` |
| `/assessments/:assessmentId/answer-key` | answer-key editor / versions | `manageAnswerKey` |
| `/assessment-session/:sessionId` | live session | `conductAssessment` |
| `/omr/capture` | camera + gallery capture | `captureOmr` |
| `/omr/review/:omrId` | scan result, score preview | `reviewScanQuality` |
| `/omr/validation` | validation queue | `validateOmr` |
| `/omr/validation/:omrId` | per-question human validation | `validateOmr` |
| `/results` | result list | `viewResults` |
| `/results/:studentId` | student result detail | `viewResults` |
| `/analytics` | drill-down analytics | `viewAnalytics` |
| `/reports` | report generation / export | `exportReports` |
| `/sync` | sync queue, failures, conflicts | `syncSubmissions` |
| `/settings` | profile, diagnostics | — (authenticated) |
| `/settings/calibration` | scanner calibration | `calibrateScanner` |
| `/unauthorized` | "you don't have access" | — |

## Redirect logic

Resolved in one place (`app/router.dart`), in this order:

```
1. session still restoring        → /splash
2. no session                     → /login          (remember intended location)
3. session exists, on /login      → intended location, else /dashboard
4. user inactive or role revoked  → /login with a message
5. route needs permission P and
   user lacks P                   → /unauthorized
6. otherwise                      → allow
```

Rule 5 fails **closed**: a route whose permission is unknown to the guard is
treated as forbidden, so adding a route without declaring its permission
cannot accidentally expose it.

## Shell navigation per role

Primary destinations (§36), filtered by permission:

| Destination | Super Admin | Assessment Admin | Supervisor | PST Teacher | Scanner Operator | Viewer |
|-------------|:-:|:-:|:-:|:-:|:-:|:-:|
| Dashboard | ● | ● | ● | ● | ● | ● |
| Schools | ● | ● | ● | ○ own | — | ● |
| Students | ● | ● | ● | ○ own | — | ● |
| Assessments | ● | ● | ● | ○ assigned | ○ scanning | ● |
| OMR | ● | — | ● | ● | ● | — |
| Validation | ● | — | ● | — | ○ submit only | — |
| Results | ● | ● | ● | ○ own school | — | ● |
| Analytics | ● | ● | ● | — | — | ● |
| Reports | ● | ● | ● | — | — | ● |
| Sync | ● | — | ● | ● | ● | — |
| Settings | ● | ● | ● | ● | ● | ● |

● full within scope ○ restricted — hidden

Destinations are filtered by permission alone — there is no per-role special
case in the navigation code. That is what keeps the bar and the route guard from
being able to disagree, and the test suite asserts the two against each other:
no destination a role can see may lead to `/unauthorized`. A Scanner Operator
therefore does see *Assessments*, because they hold `viewAssessments` — they
have to know which assessment the sheet in their hand belongs to.

A teacher's bottom navigation shows seven destinations, of which five fit the
bar and the rest move into a "More" sheet. On a 5-inch screen that is the
difference between a usable bar and a scroll.

## Deep links and offline

Route state is restorable: `/omr/review/:omrId` resolves from the local Hive
store first, so a teacher who kills the app mid-review returns to the same
screen with no network.
