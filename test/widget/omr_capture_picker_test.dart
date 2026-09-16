/// Widget tests for the capture screen's session picker.
///
/// `/omr/capture` is reachable from the bottom bar with no session attached —
/// it used to dead-end there on an empty state telling the operator to go find
/// a session somewhere else. It now lists the open sessions in the operator's
/// own scope, so the one screen a scanner operator lives on is not also the one
/// screen that cannot start work.
///
/// What these tests pin down is the *scope* boundary and the navigation, not
/// the cosmetics: a session outside the signed-in user's reach must not be
/// offered, because offering it would be a Critical Rule 10 leak in the one
/// place an operator is most likely to tap without reading.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/app/router.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/features/assessment_sessions/data/service/demo_session_data.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/presentation/controller/session_controllers.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/schools/data/service/demo_master_data.dart';
import 'package:riverpod/misc.dart' show Override;

import 'role_navigation_test.dart' show goTo;
import 'test_harness.dart';

/// Two open sessions at two different schools/grades/sections, so the
/// filter dropdowns have something real to narrow between. `demo_session_data`
/// seeds only one session, which is enough to prove the dropdowns don't add
/// friction to the common case (see the tests above) but not enough to prove
/// they actually narrow anything.
List<AssessmentSession> _twoSchoolSessions() {
  final DateTime createdAt = DateTime.utc(2026, 9, 15, 9);
  return <AssessmentSession>[
    AssessmentSession(
      sessionId: 'ses_filter_a',
      assessmentId: 'as_filter_a',
      answerKeyVersion: 1,
      schoolId: DemoHierarchyIds.schoolId1,
      clusterId: DemoHierarchyIds.clusterId1,
      districtId: DemoHierarchyIds.districtId1,
      stateId: DemoHierarchyIds.stateId,
      grade: '5',
      section: 'A',
      status: SessionStatus.inProgress,
      conductedBy: 'demo_teacher',
      createdAt: createdAt,
      updatedAt: createdAt,
      roster: const <SessionRosterEntry>[
        SessionRosterEntry(
          studentId: 'stu_filter_a',
          studentName: 'Filter Test A',
          grade: '5',
          section: 'A',
        ),
      ],
    ),
    AssessmentSession(
      sessionId: 'ses_filter_b',
      assessmentId: 'as_filter_b',
      answerKeyVersion: 1,
      schoolId: DemoHierarchyIds.schoolId2,
      clusterId: DemoHierarchyIds.clusterId1,
      districtId: DemoHierarchyIds.districtId1,
      stateId: DemoHierarchyIds.stateId,
      grade: '6',
      section: 'B',
      status: SessionStatus.inProgress,
      conductedBy: 'demo_teacher',
      createdAt: createdAt,
      updatedAt: createdAt,
      roster: const <SessionRosterEntry>[
        SessionRosterEntry(
          studentId: 'stu_filter_b',
          studentName: 'Filter Test B',
          grade: '6',
          section: 'B',
        ),
      ],
    ),
  ];
}

void main() {
  group('capture with no session attached', () {
    testWidgets('lists the open sessions in scope instead of dead-ending', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
      );
      await signInAs(tester, container, UserRole.superAdmin);
      await goTo(tester, container, RoutePaths.omrCapture);

      // Demo mode seeds exactly one session: Grade 5 Section A, in progress,
      // 2 captured and 2 pending (`demo_session_data.dart`).
      expect(find.text('Grade 5 • Section A'), findsOneWidget);
      expect(find.textContaining('2 pending'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start capture'), findsOneWidget);
    });

    testWidgets('start capture opens that session on the capture screen', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
      );
      await signInAs(tester, container, UserRole.superAdmin);
      await goTo(tester, container, RoutePaths.omrCapture);

      await tester.tap(find.widgetWithText(FilledButton, 'Start capture'));
      await tester.pumpAndSettle();

      final Uri location = container
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri;
      expect(location.path, RoutePaths.omrCapture);
      expect(
        location.queryParameters['sessionId'],
        DemoSessionIds.inProgress,
        reason: 'the picked session must travel with the route, or the sheet '
            'is captured against nothing',
      );
      // The picker is gone and the real capture screen is showing.
      expect(find.text('Start capture'), findsNothing);
    });

    testWidgets('offers nothing when no open session is in the user scope', (
      WidgetTester tester,
    ) async {
      // A scanner operator posted to a *different* school. The seeded session
      // lives at `schoolId1`; this one may not see it, let alone capture into
      // it.
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: <DemoAccount>[
          testAccount(
            UserRole.scannerOperator,
            scope: AccessScope.singleSchool(DemoHierarchyIds.schoolId2),
          ),
        ],
      );
      await signInAs(tester, container, UserRole.scannerOperator);
      await goTo(tester, container, RoutePaths.omrCapture);

      expect(find.text('Grade 5 • Section A'), findsNothing);
      expect(find.text('No active assessment sessions'), findsOneWidget);
    });
  });

  group('school / grade / section filters', () {
    testWidgets(
      'default to "All" and show every open session, unfiltered',
      (WidgetTester tester) async {
        final ProviderContainer container = await pumpApp(
          tester,
          accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
          overrides: <Override>[
            openSessionsProvider.overrideWith(
              (Ref ref) async => _twoSchoolSessions(),
            ),
          ],
        );
        await signInAs(tester, container, UserRole.superAdmin);
        await goTo(tester, container, RoutePaths.omrCapture);

        expect(
          find.widgetWithText(DropdownButtonFormField<String?>, 'All schools'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(DropdownButtonFormField<String?>, 'All grades'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(DropdownButtonFormField<String?>, 'All sections'),
          findsOneWidget,
        );
        // Both sessions render, exactly as the unfiltered list did before
        // these dropdowns existed.
        expect(find.text('Grade 5 • Section A'), findsOneWidget);
        expect(find.text('Grade 6 • Section B'), findsOneWidget);
      },
    );

    testWidgets(
      'picking a school narrows the list to that school\'s sessions',
      (WidgetTester tester) async {
        final ProviderContainer container = await pumpApp(
          tester,
          accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
          overrides: <Override>[
            openSessionsProvider.overrideWith(
              (Ref ref) async => _twoSchoolSessions(),
            ),
          ],
        );
        await signInAs(tester, container, UserRole.superAdmin);
        await goTo(tester, container, RoutePaths.omrCapture);

        await tester.tap(
          find.widgetWithText(DropdownButtonFormField<String?>, 'All schools'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Riverside Upper Primary School').last);
        await tester.pumpAndSettle();

        expect(find.text('Grade 6 • Section B'), findsOneWidget);
        expect(find.text('Grade 5 • Section A'), findsNothing);
      },
    );
  });
}
