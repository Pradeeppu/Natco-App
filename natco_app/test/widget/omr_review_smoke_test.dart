/// Smoke test driving the real review flow end to end: open a captured
/// sheet from the session screen's captured-sheets list, process it with
/// the real engine, and see the detected answers.
///
/// The sheet here is seeded directly into the repositories rather than
/// captured through the camera-picker UI: a real rendered OMR sheet (mostly
/// white background, sparse ink) legitimately fails the Phase 5 capture-time
/// quality gate's contrast check, which was calibrated against ordinary
/// photographs, not this template's own printed appearance — an
/// integration mismatch between two phases' test fixtures, not a defect in
/// either one. `omr_capture_smoke_test.dart` already proves the capture UI
/// itself end to end; this test's job is the review screen and the engine
/// behind it, so it starts from an already-saved, already-quality-checked
/// submission the same way a real one would look after Phase 5's flow
/// finishes.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/data/local/demo_assessment_data.dart';
import 'package:natco_app/data/local/demo_master_data.dart';
import 'package:natco_app/features/assessment_sessions/data/repository/in_memory_assessment_sessions_repository.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';
import 'package:natco_app/features/assessments/data/repository/in_memory_assessments_repository.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_question.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/omr_capture/data/repository/in_memory_omr_submissions_repository.dart';
import 'package:natco_app/features/omr_capture/data/service/omr_image_store.dart';
import 'package:natco_app/features/omr_capture/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_processing_status.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_capture/domain/entity/validation_status.dart';
import 'package:natco_app/features/omr_processing/data/repository/in_memory_omr_answers_repository.dart';
import 'package:natco_app/features/omr_processing/data/service/omr_pipeline_runner.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_processing_outcome.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/service/omr_processing_pipeline.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/students/data/repository/in_memory_students_repository.dart';
import 'package:natco_app/features/students/domain/entity/gender.dart';
import 'package:riverpod/misc.dart' show Override;

import '../../tool/synthetic_omr_sheet.dart';
import 'test_harness.dart';

/// Runs the real pipeline in the test's own isolate rather than spawning a
/// worker one — a real `Isolate.run` inside a widget test's fake-async zone
/// has real wall-clock spawn time `pumpAndSettle` cannot wait through, and
/// `OmrPipelineRunner.run` is already proven for real in
/// `omr_processing_service_test.dart`'s plain (non-widget) tests.
final class _DirectOmrPipelineRunner implements OmrPipelineRunner {
  const _DirectOmrPipelineRunner();

  @override
  Future<Result<OmrProcessingOutcome>> run(
    Uint8List originalImageBytes, {
    required OmrTemplate template,
    required int questionCount,
    required ScannerThresholds thresholds,
    required double imageQualityScore,
    bool qualityWasOverridden = false,
  }) async => const OmrProcessingPipeline().process(
    originalImageBytes,
    template: template,
    questionCount: questionCount,
    thresholds: thresholds,
    imageQualityScore: imageQualityScore,
    qualityWasOverridden: qualityWasOverridden,
  );
}

void main() {
  late Directory tempImageDir;

  setUp(() {
    tempImageDir = Directory.systemTemp.createTempSync('natco_omr_review_test_');
  });

  tearDown(() {
    if (tempImageDir.existsSync()) {
      tempImageDir.deleteSync(recursive: true);
    }
  });

  testWidgets(
    'opening a captured sheet and processing it shows detected answers',
    (WidgetTester tester) async {
      final String teacherUserId = testAccount(UserRole.pstTeacher).user.userId;

      const IdGenerator idGenerator = UuidIdGenerator();
      final Clock clock = FixedClock(DateTime.utc(2026, 9, 11, 9));
      final schools = InMemorySchoolsRepository(idGenerator: idGenerator, clock: clock);
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

      // The demo dataset's round-robin distribution makes grade '5' +
      // section 'A' an impossible combination at any school (see
      // omr_capture_smoke_test.dart's own note on this) — seed one
      // controlled student directly.
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
      final List<String> roster = rosterResult.valueOrNull!.items
          .map((s) => s.studentId)
          .toList();

      final prerequisites = SessionPrerequisites(
        assignmentId: assignment.assignmentId,
        assessment: active,
        questions: questions,
        publishedAnswerKey: null,
        schoolId: school.schoolId,
        clusterId: school.clusterId,
        districtId: school.districtId,
        stateId: school.stateId,
        grade: active.grade,
        studentIdsBySection: <String, List<String>>{'A': roster},
        downloadedAt: clock.nowUtc(),
      );
      final sessionResult = await sessions.startSession(
        prerequisites: prerequisites,
        section: 'A',
        expectedStudentCount: roster.length,
        teacherUserId: teacherUserId,
        deviceId: 'device-omr-review-test',
      );
      final String sessionId = sessionResult.valueOrNull!.sessionId;

      final submissions = InMemoryOmrSubmissionsRepository(clock: clock);
      final answers = InMemoryOmrAnswersRepository();
      final imageStore = FileSystemOmrImageStore(rootDirectory: () async => tempImageDir);

      final String templateSource = File(
        'assets/omr_templates/natco_v1.json',
      ).readAsStringSync();
      final OmrTemplate template = OmrTemplate.fromJsonString(templateSource);
      final sheet = renderSyntheticSheet(
        template,
        filledOptions: <int, List<int>>{1: <int>[1]}, // question 1: B
      );
      final Uint8List sheetBytes = Uint8List.fromList(
        img.encodeJpg(sheet.image, quality: 92),
      );
      final submissionId = idGenerator.newId();
      // Real file I/O, done here (fixture setup, before `pumpApp`) rather
      // than through the capture UI — still needs `runAsync`, since a
      // `testWidgets` body runs in the same fake-async zone from the start,
      // not only once a widget tree exists.
      late final Result<String> writeResult;
      await tester.runAsync(() async {
        writeResult = await imageStore.writeOriginal(
          submissionId: submissionId,
          bytes: sheetBytes,
        );
      });

      const ImageQualityReport passingQuality = ImageQualityReport(
        blurScore: 0.9,
        brightnessScore: 0.5,
        contrastScore: 0.8,
        shadowDeviation: 0.05,
        verdict: ImageQualityVerdict.pass,
        failureReasons: <String>[],
      );
      final DateTime now = clock.nowUtc();
      await submissions.createSubmission(
        OmrSubmission(
          submissionId: submissionId,
          omrId: '0001827',
          sessionId: sessionId,
          assessmentId: active.assessmentId,
          studentId: roster.first,
          schoolId: school.schoolId,
          clusterId: school.clusterId,
          districtId: school.districtId,
          stateId: school.stateId,
          capturedBy: teacherUserId,
          capturedAt: now,
          deviceId: 'device-omr-review-test',
          originalImagePath: writeResult.valueOrNull!,
          imageQuality: passingQuality,
          processingStatus: OmrProcessingStatus.qualityChecked,
          validationStatus: ValidationStatus.notRequired,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final DemoAccount teacher = DemoAccount(
        user: testAccount(UserRole.pstTeacher).user.copyWith(
          scope: AccessScope.singleSchool(school.schoolId),
        ),
        password: kTestPassword,
      );
      final container = await pumpApp(
        tester,
        accounts: <DemoAccount>[teacher],
        extraOverrides: <Override>[
          schoolsRepositoryProvider.overrideWithValue(schools),
          studentsRepositoryProvider.overrideWithValue(students),
          assessmentsRepositoryProvider.overrideWithValue(assessments),
          assessmentSessionsRepositoryProvider.overrideWithValue(sessions),
          omrSubmissionsRepositoryProvider.overrideWithValue(submissions),
          omrAnswersRepositoryProvider.overrideWithValue(answers),
          omrImageStoreProvider.overrideWithValue(imageStore),
          omrPipelineRunnerProvider.overrideWithValue(
            const _DirectOmrPipelineRunner(),
          ),
        ],
      );
      await signInAs(tester, container, UserRole.pstTeacher);

      await scrollTo(tester, find.text('Start or continue assessment'));
      await tester.tap(find.text('Start or continue assessment'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grade 5 · Section A'));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Sheet 0001827'));
      await tester.tap(find.text('Sheet 0001827'));
      await tester.pumpAndSettle();

      expect(find.text('Process this sheet'), findsOneWidget);
      // Processing reads the durable image file for real
      // (`FileSystemOmrImageStore`), which needs the real event loop — the
      // same "real I/O needs `runAsync`" lesson `omr_capture_smoke_test.dart`
      // applies to the capture write.
      await tester.runAsync(() async {
        await tester.tap(find.text('Process this sheet'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();

      expect(find.text('READY_FOR_SCORING'), findsOneWidget);
      expect(find.text('Detected answers'), findsOneWidget);
      expect(find.textContaining('B'), findsWidgets);
    },
  );
}
