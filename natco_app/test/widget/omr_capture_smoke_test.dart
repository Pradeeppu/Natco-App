/// Smoke test driving the real capture flow end to end: identify a sheet,
/// capture it, see the quality verdict, and save it against a live session.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/data/local/demo_assessment_data.dart';
import 'package:natco_app/data/local/demo_master_data.dart';
import 'package:natco_app/features/assessment_sessions/data/repository/in_memory_assessment_sessions_repository.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';
import 'package:natco_app/features/assessments/data/repository/in_memory_assessments_repository.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_question.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/omr_capture/data/service/image_picker_service.dart';
import 'package:natco_app/features/omr_capture/data/service/omr_image_store.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/students/data/repository/in_memory_students_repository.dart';
import 'package:natco_app/features/students/domain/entity/gender.dart';
import 'package:riverpod/misc.dart' show Override;

import 'test_harness.dart';

Uint8List _sharpJpeg({int size = 64, int cell = 4}) {
  final img.Image image = img.Image(width: size, height: size);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final bool isLight = ((x ~/ cell) + (y ~/ cell)).isEven;
      final int gray = isLight ? 245 : 10;
      image.setPixel(x, y, img.ColorRgb8(gray, gray, gray));
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List _flatDarkJpeg({int size = 64}) {
  final img.Image image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(5, 5, 5));
  return Uint8List.fromList(img.encodeJpg(image));
}

/// Always returns the same canned bytes — no platform channel involved.
final class _FakeImagePickerService implements ImagePickerService {
  _FakeImagePickerService(this.bytes);

  Uint8List? bytes;

  @override
  Future<Uint8List?> captureFromCamera() async => bytes;

  @override
  Future<Uint8List?> pickFromGallery() async => bytes;
}

void main() {
  late Directory tempImageDir;

  setUp(() {
    tempImageDir = Directory.systemTemp.createTempSync('natco_omr_capture_test_');
  });

  tearDown(() {
    if (tempImageDir.existsSync()) {
      tempImageDir.deleteSync(recursive: true);
    }
  });

  Future<
    ({
      InMemorySchoolsRepository schools,
      InMemoryStudentsRepository students,
      InMemoryAssessmentsRepository assessments,
      InMemoryAssessmentSessionsRepository sessions,
      AssessmentSession session,
      String teacherUserId,
    })
  >
  seedFixtures({required String teacherUserId}) async {
    const IdGenerator idGenerator = UuidIdGenerator();
    final Clock clock = FixedClock(DateTime.utc(2026, 9, 11, 9));
    final schools = InMemorySchoolsRepository(
      idGenerator: idGenerator,
      clock: clock,
    );
    final students = InMemoryStudentsRepository(
      idGenerator: idGenerator,
      clock: clock,
      schools: schools,
    );
    final assessments = InMemoryAssessmentsRepository(
      idGenerator: idGenerator,
      clock: clock,
      schools: schools,
    );
    final sessions = InMemoryAssessmentSessionsRepository(
      idGenerator: idGenerator,
      clock: clock,
    );
    final List<School> seededSchools = seedDemoMasterData(
      schools: schools,
      students: students,
      idGenerator: idGenerator,
      clock: clock,
    );
    seedDemoAssessmentData(
      assessments: assessments,
      seededSchools: seededSchools,
      idGenerator: idGenerator,
      clock: clock,
    );
    final School school = seededSchools.first;

    final activeAssessments = await assessments.listAssessments();
    final Assessment active = activeAssessments.valueOrNull!.items.firstWhere(
      (Assessment a) => a.assessmentName == 'Term 1 English Assessment',
    );
    final questionsResult = await assessments.listQuestions(active.assessmentId);
    final List<AssessmentQuestion> questions = questionsResult.valueOrNull!;

    final assignmentsResult = await assessments.listAssignments(
      scope: const AccessScope.global(),
      assessmentId: active.assessmentId,
    );
    final AssessmentAssignment assignment = assignmentsResult.valueOrNull!.items.single;

    // The demo dataset's round-robin distribution (grade index g = i % 6,
    // section index s = i % 3 = g % 3) makes grade '5' + section 'A' an
    // impossible combination at any school — grade '5' always lands on
    // section 'C'. Seed one controlled student directly rather than relying
    // on incidental demo data to happen to cover this grade/section.
    students.seedStudent(
      schoolId: school.schoolId,
      studentName: 'Aarav Kumar',
      gender: Gender.male,
      grade: active.grade,
      section: 'A',
      mediumOfInstruction: school.mediumsOfInstruction.first,
      language: 'English',
      dateOfBirth: DateTime.utc(2015, 1, 1),
    );

    final rosterResult = await students.listStudents(
      scope: const AccessScope.global(),
      schoolId: school.schoolId,
      grade: active.grade,
      section: 'A',
    );
    final List<String> sectionARoster = rosterResult.valueOrNull!.items
        .map((s) => s.studentId)
        .toList();

    final SessionPrerequisites prerequisites = SessionPrerequisites(
      assignmentId: assignment.assignmentId,
      assessment: active,
      questions: questions,
      publishedAnswerKey: null,
      schoolId: school.schoolId,
      clusterId: school.clusterId,
      districtId: school.districtId,
      stateId: school.stateId,
      grade: active.grade,
      studentIdsBySection: <String, List<String>>{'A': sectionARoster},
      downloadedAt: clock.nowUtc(),
    );

    final sessionResult = await sessions.startSession(
      prerequisites: prerequisites,
      section: 'A',
      expectedStudentCount: sectionARoster.length,
      teacherUserId: teacherUserId,
      deviceId: 'device-omr-test',
    );

    return (
      schools: schools,
      students: students,
      assessments: assessments,
      sessions: sessions,
      session: sessionResult.valueOrNull!,
      teacherUserId: teacherUserId,
    );
  }

  testWidgets('capturing a sharp photo passes quality and saves the sheet', (
    WidgetTester tester,
  ) async {
    final String teacherUserId = testAccount(UserRole.pstTeacher).user.userId;
    final fixtures = await seedFixtures(teacherUserId: teacherUserId);
    final _FakeImagePickerService picker = _FakeImagePickerService(_sharpJpeg());

    final DemoAccount teacher = DemoAccount(
      user: testAccount(UserRole.pstTeacher).user.copyWith(
        scope: AccessScope.singleSchool(fixtures.session.schoolId),
      ),
      password: kTestPassword,
    );
    final container = await pumpApp(
      tester,
      accounts: <DemoAccount>[teacher],
      extraOverrides: <Override>[
        schoolsRepositoryProvider.overrideWithValue(fixtures.schools),
        studentsRepositoryProvider.overrideWithValue(fixtures.students),
        assessmentsRepositoryProvider.overrideWithValue(fixtures.assessments),
        assessmentSessionsRepositoryProvider.overrideWithValue(fixtures.sessions),
        imagePickerServiceProvider.overrideWithValue(picker),
        omrImageStoreProvider.overrideWithValue(
          FileSystemOmrImageStore(rootDirectory: () async => tempImageDir),
        ),
      ],
    );
    await signInAs(tester, container, UserRole.pstTeacher);

    await scrollTo(tester, find.text('Start or continue assessment'));
    await tester.tap(find.text('Start or continue assessment'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Grade 5 · Section A'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Capture OMR'));
    await tester.pumpAndSettle();

    // The capture buttons are disabled until both fields are filled.
    await tester.tap(find.widgetWithText(FilledButton, 'Capture from camera'));
    await tester.pumpAndSettle();
    expect(find.text('Quality check passed'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aarav Kumar').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Printed OMR ID'), '0001827');
    await tester.pumpAndSettle();

    // The capture writes a real file to disk (proving the durability
    // invariant, not a fake), which needs to run inside `runAsync`'s real
    // zone — triggered from the fake-async zone `pumpAndSettle` otherwise
    // drives, the write's Future would never resolve and the busy
    // indicator's animation would spin forever.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Capture from camera'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Quality check passed'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Capture OMR (1 saved)'), findsOneWidget);

    final submissions = await fixtures.sessions.getSession(fixtures.session.sessionId);
    expect(submissions.valueOrNull, isNotNull);
  });

  testWidgets(
    'a blurred, dark photo fails quality and a Super Admin can use it anyway',
    (WidgetTester tester) async {
      // Only Super Admin holds both `captureOmr` and `overrideQualityGate`
      // (docs/04-security-model.md: "Only Supervisors and Super Admins may
      // waive the image-quality gate" — a Supervisor alone cannot open this
      // screen at all, since it also requires `captureOmr`), so this is the
      // one real account that can exercise the override path end to end.
      final DemoAccount superAdmin = testAccount(UserRole.superAdmin);
      final fixtures = await seedFixtures(
        teacherUserId: superAdmin.user.userId,
      );
      final _FakeImagePickerService picker = _FakeImagePickerService(
        _flatDarkJpeg(),
      );
      final container = await pumpApp(
        tester,
        accounts: <DemoAccount>[superAdmin],
        extraOverrides: <Override>[
          schoolsRepositoryProvider.overrideWithValue(fixtures.schools),
          studentsRepositoryProvider.overrideWithValue(fixtures.students),
          assessmentsRepositoryProvider.overrideWithValue(fixtures.assessments),
          assessmentSessionsRepositoryProvider.overrideWithValue(fixtures.sessions),
          imagePickerServiceProvider.overrideWithValue(picker),
          omrImageStoreProvider.overrideWithValue(
            FileSystemOmrImageStore(rootDirectory: () async => tempImageDir),
          ),
        ],
      );
      await signInAs(tester, container, UserRole.superAdmin);

      await scrollTo(tester, find.text('Sessions'));
      await tester.tap(find.text('Sessions'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grade 5 · Section A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Capture OMR'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aarav Kumar').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Printed OMR ID'),
        '0001827',
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Capture from camera'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(find.text('Quality check failed'), findsOneWidget);
      expect(
        find.textContaining('The photo is blurred'),
        findsOneWidget,
      );
      expect(
        find.textContaining('The photo is too dark'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Retake'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Use Anyway'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Only copy available; original sheet was damaged in transit.',
      );
      await tester.pumpAndSettle();
      // Once the dialog is open, both the screen's own "Use Anyway" button
      // (behind the dialog) and the dialog's confirm button match — the
      // dialog's is the one added last.
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Use Anyway').last);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(find.text('Capture OMR (1 saved)'), findsOneWidget);
    },
  );
}
