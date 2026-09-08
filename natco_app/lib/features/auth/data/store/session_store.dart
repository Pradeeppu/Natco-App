/// Persistence for the cached session that enables offline use.
///
/// What is stored is a session record, not a credential: profile, role, scope
/// and the last verification instant. No password and no token
/// (docs/04-security-model.md).
///
/// The Hive box is encrypted with a 256-bit key held in the platform keystore
/// through `flutter_secure_storage`. If the key is missing the box is treated
/// as unreadable and the user signs in again — the safe direction.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/auth_session.dart';

abstract interface class SessionStore {
  /// Reads the cached session, or `null` when there is none.
  Future<Result<AuthSession?>> read();

  /// Replaces the cached session.
  Future<Result<void>> write(AuthSession session);

  /// Removes the cached session. Called on sign-out and on any failure to
  /// interpret what was stored.
  Future<Result<void>> clear();
}

/// Encrypted Hive-backed store.
final class SecureSessionStore implements SessionStore {
  SecureSessionStore({
    required HiveInterface hive,
    required FlutterSecureStorage secureStorage,
    required AppLogger logger,
  }) : _hive = hive,
       _secureStorage = secureStorage,
       _logger = logger;

  static const String _sessionKey = 'session';
  static const String _encryptionKeyName = 'natco_session_key_v1';

  final HiveInterface _hive;
  final FlutterSecureStorage _secureStorage;
  final AppLogger _logger;

  @override
  Future<Result<AuthSession?>> read() => guardAsync(() async {
    final Box<String> box = await _openBox();
    final String? raw = box.get(_sessionKey);
    if (raw == null) {
      return null;
    }
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      // Unreadable rather than absent: drop it and make the user sign in.
      // Guessing at a malformed session record is how a stale role survives.
      _logger.warning('session_cache_malformed');
      await box.delete(_sessionKey);
      return null;
    }
    final AuthSession? session = AuthSession.tryFromJson(decoded);
    if (session == null) {
      _logger.warning('session_cache_unreadable');
      await box.delete(_sessionKey);
    }
    return session;
  }, onError: _mapStoreError);

  @override
  Future<Result<void>> write(AuthSession session) => guardAsync(() async {
    final Box<String> box = await _openBox();
    await box.put(_sessionKey, jsonEncode(session.toJson()));
  }, onError: _mapStoreError);

  @override
  Future<Result<void>> clear() => guardAsync(() async {
    final Box<String> box = await _openBox();
    await box.delete(_sessionKey);
  }, onError: _mapStoreError);

  Future<Box<String>> _openBox() async {
    if (_hive.isBoxOpen(LocalBoxes.session)) {
      return _hive.box<String>(LocalBoxes.session);
    }
    return _hive.openBox<String>(
      LocalBoxes.session,
      encryptionCipher: HiveAesCipher(await _encryptionKey()),
    );
  }

  /// Fetches the box key, generating it on first run.
  Future<List<int>> _encryptionKey() async {
    final String? existing = await _secureStorage.read(key: _encryptionKeyName);
    if (existing != null) {
      final List<int> decoded = base64Decode(existing);
      if (decoded.length == 32) {
        return decoded;
      }
      _logger.warning('session_key_invalid_length');
    }
    final List<int> key = _generateKey();
    await _secureStorage.write(
      key: _encryptionKeyName,
      value: base64Encode(key),
    );
    return key;
  }

  /// 256 bits from the platform CSPRNG. `Random.secure()` rather than
  /// `Random()`, because a predictable key is not a key.
  static List<int> _generateKey() {
    final Random random = Random.secure();
    return List<int>.generate(32, (int _) => random.nextInt(256));
  }

  Failure _mapStoreError(Object error, StackTrace stackTrace) =>
      StorageFailure.localWrite(
        diagnostic: 'session store: $error',
        cause: error,
      );
}

/// Non-persistent store. Used by tests and demo mode.
final class InMemorySessionStore implements SessionStore {
  AuthSession? _session;

  @override
  Future<Result<AuthSession?>> read() async => ok(_session);

  @override
  Future<Result<void>> write(AuthSession session) async {
    _session = session;
    return ok(null);
  }

  @override
  Future<Result<void>> clear() async {
    _session = null;
    return ok(null);
  }
}
