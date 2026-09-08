/// The signed-in user.
library;

import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

final class AppUser {
  const AppUser({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.scope,
    required this.isActive,
    this.phone,
    this.lastLoginAt,
    this.claimsVersion = 0,
  });

  final String userId;
  final String email;
  final String displayName;
  final String? phone;
  final UserRole role;
  final AccessScope scope;

  /// A deactivated user cannot sign in, and an existing cached session for
  /// them is invalidated on the next connected check.
  final bool isActive;

  final DateTime? lastLoginAt;

  /// Bumped server-side whenever `role` or `scope` changes, so the client can
  /// tell that its ID token's claims are stale and force a refresh instead of
  /// waiting up to an hour for expiry (docs/04-security-model.md).
  final int claimsVersion;

  Set<Permission> get permissions => role.permissions;

  bool can(Permission permission) => role.can(permission);

  /// Whether this user may act on [target].
  ///
  /// Note that this is the scope half only. Callers should go through
  /// `Authorization`, which checks permission *and* scope together.
  bool covers(ScopeTarget target) => scope.covers(target);

  /// First name, for greetings. Falls back to the whole name.
  String get shortName {
    final String trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      return email;
    }
    final int space = trimmed.indexOf(' ');
    return space > 0 ? trimmed.substring(0, space) : trimmed;
  }

  /// Serialised form for the local session cache.
  ///
  /// This is written to an encrypted box on the device. It holds no password
  /// and no auth token — a session cache, not a credential cache.
  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'email': email,
    'displayName': displayName,
    'phone': phone,
    'role': role.wireName,
    'scope': scope.toJson(),
    'isActive': isActive,
    'lastLoginAt': lastLoginAt?.toUtc().toIso8601String(),
    'claimsVersion': claimsVersion,
  };

  /// Reads a user from stored JSON.
  ///
  /// Returns `null` when the role or scope cannot be resolved. Both are
  /// load-bearing for authorization, so a record this build cannot fully
  /// understand is refused rather than partially trusted.
  static AppUser? tryFromJson(Map<String, Object?> json) {
    final String? userId = json['userId'] as String?;
    final UserRole? role = UserRole.tryFromWireName(json['role'] as String?);
    final Object? rawScope = json['scope'];
    if (userId == null || userId.isEmpty || role == null) {
      return null;
    }
    final AccessScope? scope = rawScope is Map<String, Object?>
        ? AccessScope.tryFromJson(rawScope)
        : null;
    if (scope == null || !scope.isValid) {
      return null;
    }
    final Object? lastLoginAt = json['lastLoginAt'];
    return AppUser(
      userId: userId,
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      phone: json['phone'] as String?,
      role: role,
      scope: scope,
      isActive: json['isActive'] as bool? ?? false,
      lastLoginAt: lastLoginAt is String
          ? DateTime.tryParse(lastLoginAt)
          : null,
      claimsVersion: switch (json['claimsVersion']) {
        final num value => value.toInt(),
        _ => 0,
      },
    );
  }

  AppUser copyWith({
    String? email,
    String? displayName,
    String? phone,
    UserRole? role,
    AccessScope? scope,
    bool? isActive,
    DateTime? lastLoginAt,
    int? claimsVersion,
  }) => AppUser(
    userId: userId,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    phone: phone ?? this.phone,
    role: role ?? this.role,
    scope: scope ?? this.scope,
    isActive: isActive ?? this.isActive,
    lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    claimsVersion: claimsVersion ?? this.claimsVersion,
  );

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.userId == userId &&
      other.email == email &&
      other.displayName == displayName &&
      other.phone == phone &&
      other.role == role &&
      other.scope == scope &&
      other.isActive == isActive &&
      other.lastLoginAt == lastLoginAt &&
      other.claimsVersion == claimsVersion;

  @override
  int get hashCode => Object.hash(
    userId,
    email,
    displayName,
    phone,
    role,
    scope,
    isActive,
    lastLoginAt,
    claimsVersion,
  );

  /// Deliberately omits email and display name: this string ends up in logs.
  @override
  String toString() => 'AppUser($userId, ${role.wireName}, $scope)';
}
