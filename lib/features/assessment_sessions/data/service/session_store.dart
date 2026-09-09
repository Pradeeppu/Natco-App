/// Local-first storage for sessions.
///
/// This is the layer Critical Rule 12 rests on: a session written here has
/// survived the write before the caller is told it succeeded, so a force-stop
/// or a battery death loses nothing. The sync engine (phase 9) uploads from
/// here; nothing in the capture flow ever waits on a server.
///
/// Two implementations, and the split is not the usual demo-versus-real one:
/// [InMemoryAssessmentSessionStore] backs tests and demo mode, while
/// [HiveAssessmentSessionStore]
/// is what runs on a device in both `dev` and `prod` — because a teacher in a
/// classroom needs durability regardless of which backend the app talks to.
library;

import 'package:hive_ce/hive.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';

abstract interface class AssessmentSessionStore {
  Future<Result<List<AssessmentSession>>> all();

  Future<Result<AssessmentSession?>> read(String sessionId);

  /// Writes [session], replacing any existing record with the same id.
  ///
  /// Must not return until the write is durable.
  Future<Result<AssessmentSession>> write(AssessmentSession session);

  Future<Result<void>> delete(String sessionId);
}

final class InMemoryAssessmentSessionStore implements AssessmentSessionStore {
  InMemoryAssessmentSessionStore({List<AssessmentSession> sessions = const []})
    : _sessions = <String, AssessmentSession>{
        for (final AssessmentSession s in sessions) s.sessionId: s,
      };

  final Map<String, AssessmentSession> _sessions;

  @override
  Future<Result<List<AssessmentSession>>> all() async => ok(
    _sessions.values.toList()
      ..sort(
        (AssessmentSession a, AssessmentSession b) =>
            b.createdAt.compareTo(a.createdAt),
      ),
  );

  @override
  Future<Result<AssessmentSession?>> read(String sessionId) async =>
      ok(_sessions[sessionId]);

  @override
  Future<Result<AssessmentSession>> write(AssessmentSession session) async {
    _sessions[session.sessionId] = session;
    return ok(session);
  }

  @override
  Future<Result<void>> delete(String sessionId) async {
    _sessions.remove(sessionId);
    return ok(null);
  }
}

/// Hive-backed store. One box, keyed by session id, values as JSON maps.
///
/// JSON rather than a generated `TypeAdapter` on purpose: a session's shape
/// will keep changing through phases 5-9, and a typed adapter turns every one
/// of those changes into an on-device schema migration. The same JSON already
/// crosses the wire, so there is exactly one shape to keep working.
final class HiveAssessmentSessionStore implements AssessmentSessionStore {
  HiveAssessmentSessionStore(this._box);

  final Box<dynamic> _box;

  /// Opens the box. Call once during startup.
  static Future<Result<HiveAssessmentSessionStore>> open(HiveInterface hive) async {
    final Result<Box<dynamic>> box = await guardAsync(
      () => hive.openBox<dynamic>(LocalBoxes.sessions),
      onError: (Object error, StackTrace stackTrace) =>
          StorageFailure.localWrite(
            diagnostic: 'could not open ${LocalBoxes.sessions}',
            cause: error,
          ),
    );
    return box.map(HiveAssessmentSessionStore.new);
  }

  @override
  Future<Result<List<AssessmentSession>>> all() async => guard(
    () =>
        _box.values
            .map(_decode)
            // A record this build cannot read is skipped rather than
            // crashing the list. Losing one session's *display* is bad;
            // making the whole screen unopenable, with every other session
            // behind it, is worse — and the record itself is untouched.
            .whereType<AssessmentSession>()
            .toList()
          ..sort(
            (AssessmentSession a, AssessmentSession b) =>
                b.createdAt.compareTo(a.createdAt),
          ),
    onError: (Object error, StackTrace stackTrace) => StorageFailure(
      userMessage:
          'Unable to read saved sessions from this device. Your captured '
          'sheets are still safe.',
      diagnostic: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    ),
  );

  @override
  Future<Result<AssessmentSession?>> read(String sessionId) async =>
      guard(() => _decode(_box.get(sessionId)));

  @override
  Future<Result<AssessmentSession>> write(AssessmentSession session) async {
    final Result<void> put = await guardAsync(
      // `put` completes when the write has been flushed, which is what makes
      // "durable before we return" true rather than hopeful.
      () => _box.put(session.sessionId, session.toJson()),
      onError: (Object error, StackTrace stackTrace) =>
          StorageFailure.localWrite(
            diagnostic: 'session write failed',
            cause: error,
          ),
    );
    return put.map((_) => session);
  }

  @override
  Future<Result<void>> delete(String sessionId) => guardAsync(
    () => _box.delete(sessionId),
    onError: (Object error, StackTrace stackTrace) => StorageFailure.localWrite(
      diagnostic: 'session delete failed',
      cause: error,
    ),
  );

  /// Hive returns `Map<dynamic, dynamic>` for a nested map, so the cast has to
  /// be explicit at every level rather than a single `as Map<String, Object?>`.
  static AssessmentSession? _decode(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    return AssessmentSession.tryFromJson(_deepCast(raw));
  }

  static Map<String, Object?> _deepCast(Map<dynamic, dynamic> map) =>
      <String, Object?>{
        for (final MapEntry<dynamic, dynamic> entry in map.entries)
          entry.key.toString(): switch (entry.value) {
            final Map<dynamic, dynamic> nested => _deepCast(nested),
            final List<dynamic> list => list
                .map(
                  (Object? item) => item is Map<dynamic, dynamic>
                      ? _deepCast(item)
                      : item,
                )
                .toList(growable: false),
            final Object? value => value,
          },
      };
}
