/// Hive-backed [SessionPrerequisitesRepository].
///
/// Stores each assignment's prerequisites as a JSON string keyed by
/// `assignmentId`, the same box-of-JSON-strings shape `SecureSessionStore`
/// uses for the session cache — `hive_ce` needs no generated `TypeAdapter`
/// for that, which keeps this feature out of the `build_runner` surface
/// (docs/09-dependencies.md). Unlike the session cache this box holds no
/// personal data beyond student ids already visible to the signed-in
/// teacher, so it is not encrypted.
library;

import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/session_prerequisites_repository.dart';

final class HiveSessionPrerequisitesRepository
    implements SessionPrerequisitesRepository {
  HiveSessionPrerequisitesRepository({
    required HiveInterface hive,
    required AppLogger logger,
  }) : _hive = hive,
       _logger = logger;

  final HiveInterface _hive;
  final AppLogger _logger;

  @override
  Future<Result<SessionPrerequisites?>> get(String assignmentId) =>
      guardAsync(() async {
        final Box<String> box = await _openBox();
        final String? raw = box.get(assignmentId);
        if (raw == null) {
          return null;
        }
        final Object? decoded = jsonDecode(raw);
        if (decoded is! Map<String, Object?>) {
          _logger.warning('session_prerequisites_malformed');
          await box.delete(assignmentId);
          return null;
        }
        final SessionPrerequisites? prerequisites =
            SessionPrerequisites.tryFromJson(decoded);
        if (prerequisites == null) {
          _logger.warning('session_prerequisites_unreadable');
          await box.delete(assignmentId);
        }
        return prerequisites;
      }, onError: _mapError);

  @override
  Future<Result<void>> save(SessionPrerequisites prerequisites) =>
      guardAsync(() async {
        final Box<String> box = await _openBox();
        await box.put(
          prerequisites.assignmentId,
          jsonEncode(prerequisites.toJson()),
        );
      }, onError: _mapError);

  @override
  Future<Result<List<SessionPrerequisites>>> listDownloaded() =>
      guardAsync(() async {
        final Box<String> box = await _openBox();
        return <SessionPrerequisites>[
          for (final String raw in box.values)
            if (jsonDecode(raw) case final Map<String, Object?> decoded)
              ?SessionPrerequisites.tryFromJson(decoded),
        ];
      }, onError: _mapError);

  Future<Box<String>> _openBox() async => _hive.isBoxOpen(LocalBoxes.sessionPrerequisites)
      ? _hive.box<String>(LocalBoxes.sessionPrerequisites)
      : _hive.openBox<String>(LocalBoxes.sessionPrerequisites);

  Failure _mapError(Object error, StackTrace stackTrace) =>
      StorageFailure.localWrite(
        diagnostic: 'session prerequisites cache: $error',
        cause: error,
      );
}
