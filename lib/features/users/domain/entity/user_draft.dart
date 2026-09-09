/// What a person fills in to create a user account.
///
/// Separate from [AppUser] because a draft has no id, no `claimsVersion` and
/// no login history — those are the server's to assign, and a form that could
/// set them would be a form that could forge a session.
library;

import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

final class UserDraft {
  const UserDraft({
    required this.email,
    required this.displayName,
    required this.role,
    required this.scope,
    this.phone,
  });

  final String email;
  final String displayName;
  final String? phone;
  final UserRole role;
  final AccessScope scope;

  /// Normalised address, used both for the account and for the uniqueness
  /// guard. Case and surrounding whitespace are not part of an identity, and
  /// treating them as such is how the same person ends up with two accounts.
  String get normalisedEmail => email.trim().toLowerCase();

  UserDraft copyWith({
    String? email,
    String? displayName,
    String? phone,
    UserRole? role,
    AccessScope? scope,
  }) => UserDraft(
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    phone: phone ?? this.phone,
    role: role ?? this.role,
    scope: scope ?? this.scope,
  );

  /// Deliberately omits email and display name: this string can reach logs,
  /// and a user's contact details are personal data (requirement §35).
  @override
  String toString() => 'UserDraft(${role.wireName}, $scope)';
}
