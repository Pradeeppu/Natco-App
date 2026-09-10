/// Tests for [OmrImageWriter] — the durable-capture step (Critical Rule 12).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/services/file_system_service.dart';
import 'package:natco_app/features/omr_processing/domain/service/omr_image_writer.dart';

void main() {
  test('writes the exact bytes given, under the documented storage path shape', () async {
    final FakeFileSystemService fileSystem = FakeFileSystemService();
    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

    final result = await OmrImageWriter.writeCapturedImage(
      fileSystem: fileSystem,
      documentsRootPath: '/app/documents',
      imageBytes: bytes,
      academicYear: '2026-27',
      assessmentId: 'as_demo_midline_g5',
      stateId: 'st_demo',
      districtId: 'di_demo_1',
      clusterId: 'cl_demo_1',
      schoolId: 'sch_demo_1',
      capturedAt: DateTime.utc(2026, 9, 15, 10, 30),
      omrId: '0001827',
    );

    expect(result.isSuccess, isTrue);
    final String path = result.valueOrNull!;
    expect(path, contains('2026-27'));
    expect(path, contains('2026-09-15')); // date, not time
    expect(path, contains('OMR_0001827.jpg'));
    expect(fileSystem.fileExistsSync(path), isTrue);
    expect(fileSystem.bytesWrittenTo(path), bytes);
  });

  test(
    'a local capture just after UTC midnight still files under that UTC '
    'date, not a locally-shifted one',
    () async {
      final FakeFileSystemService fileSystem = FakeFileSystemService();
      final result = await OmrImageWriter.writeCapturedImage(
        fileSystem: fileSystem,
        documentsRootPath: '/app/documents',
        imageBytes: Uint8List(0),
        academicYear: '2026-27',
        assessmentId: 'as_1',
        stateId: 'st_1',
        districtId: 'di_1',
        clusterId: 'cl_1',
        schoolId: 'sch_1',
        capturedAt: DateTime.utc(2026, 9, 15, 0, 5),
        omrId: '0001900',
      );
      expect(result.valueOrNull!, contains('2026-09-15'));
    },
  );
}
