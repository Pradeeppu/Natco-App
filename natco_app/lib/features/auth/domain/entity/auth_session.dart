/// The cached session record that makes offline use possible.
///
/// Requirement section 23 asks for offline login "where securely possible".
/// What is stored is a *session*, never a credential: the user's profile, role
/// and scope, plus the instant the session was last verified against the
/// server. No password, no ID token, no refresh token.
///
/// The record lives in an encrypted Hive box whose key is held in the platform
/// keystore via `flutter_secure_storage`, and it expires. A stolen phone
/// therefore yields at most a read-only window that closes, not an account.
library;

import 'package:natco_app/features/auth/domain/entity/app_user.dart';

/// How the current session was established.
enum SessionOrigin {
  /// Verified against the server during this sign-in.
  online('ONLINE'),

  /// Restored from the local cache without contacting the server.
  offlineCache('OFFLINE_CACHE');

  const SessionOrigin(this.wireName);

  final String wireName;

  static SessionOrigin fromWireName(String? name) =>
      name == SessionOrigin.offlineCache.wireName
      ? SessionOrigin.offlineCache
      : SessionOrigin.online;
}

final class AuthSession {
  const AuthSession({
    required this.user,
    required this.establishedAt,
    required this.lastVerifiedAt,
    required this.origin,
    required this.deviceId,
  });

  final AppUser user;

  /// When the user signed in.
  final DateTime establishedAt;

  /// When the server last confirmed this user's role, scope and active state.
  /// Offline expiry is measured from here, not from [establishedAt] — a
  /// session that keeps reconnecting stays valid indefinitely, while one that
  /// never reconnects expires on schedule.
  final DateTime lastVerifiedAt;

  final SessionOrigin origin;
  final String deviceId;

  /// Whether the session is still usable at [now], given [validity].
  bool isValidAt(DateTime now, Duration validity) {
    if (!user.isActive) {
      return false;
    }
    return now.toUtc().difference(lastVerifiedAt.toUtc()) < validity;
  }

  /// Time left before offline use is refused. Zero once expired.
  Duration remainingValidity(DateTime now, Duration validity) {
    final Duration elapsed = now.toUtc().difference(lastVerifiedAt.toUtc());
    final Duration remaining = validity - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  AuthSession copyWith({
    AppUser? user,
    DateTime? lastVerifiedAt,
    SessionOrigin? origin,
  }) => AuthSession(
    user: user ?? this.user,
    establishedAt: establishedAt,
    lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
    origin: origin ?? this.origin,
    deviceId: deviceId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'user': user.toJson(),
    'establishedAt': establishedAt.toUtc().toIso8601String(),
    'lastVerifiedAt': lastVerifiedAt.toUtc().toIso8601String(),
    'origin': origin.wireName,
    'deviceId': deviceId,
  };

  /// Reads a cached session. Returns `null` if anything essential is missing
  /// or unparseable, in which case the user signs in again — the safe default.
  static AuthSession? tryFromJson(Map<String, Object?> json) {
    final Object? rawUser = json['user'];
    if (rawUser is! Map<String, Object?>) {
      return null;
    }
    final AppUser? user = AppUser.tryFromJson(rawUser);
    final DateTime? establishedAt = _parseUtc(json['establishedAt']);
    final DateTime? lastVerifiedAt = _parseUtc(json['lastVerifiedAt']);
    if (user == null || establishedAt == null || lastVerifiedAt == null) {
      return null;
    }
    return AuthSession(
      user: user,
      establishedAt: establishedAt,
      lastVerifiedAt: lastVerifiedAt,
      origin: SessionOrigin.fromWireName(json['origin'] as String?),
      deviceId: json['deviceId'] as String? ?? 'unknown',
    );
  }

  static DateTime? _parseUtc(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  @override
  bool operator ==(Object other) =>
      other is AuthSession &&
      other.user == user &&
      other.establishedAt == establishedAt &&
      other.lastVerifiedAt == lastVerifiedAt &&
      other.origin == origin &&
      other.deviceId == deviceId;

  @override
  int get hashCode =>
      Object.hash(user, establishedAt, lastVerifiedAt, origin, deviceId);

  @override
  String toString() =>
      'AuthSession(${user.userId}, ${origin.wireName}, '
      'verified=$lastVerifiedAt)';
}
