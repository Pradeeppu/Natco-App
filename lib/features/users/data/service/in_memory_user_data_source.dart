/// In-memory [UserDataSource]. Backs demo mode and tests.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/users/data/service/user_data_source.dart';

final class InMemoryUserDataSource implements UserDataSource {
  InMemoryUserDataSource({List<AppUser> users = const <AppUser>[]})
    : _users = <String, AppUser>{for (final AppUser u in users) u.userId: u},
      _emails = <String>{
        for (final AppUser u in users) u.email.trim().toLowerCase(),
      };

  final Map<String, AppUser> _users;

  /// Stands in for the `user_email/{normalisedEmail}` guard document.
  final Set<String> _emails;

  @override
  Future<Result<Page<AppUser>>> listUsers({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    final String needle = query.trim().toLowerCase();
    final List<AppUser> matching =
        _users.values
            .where((AppUser u) => u.scope.isWithin(scope))
            .where(
              (AppUser u) =>
                  needle.isEmpty ||
                  u.displayName.toLowerCase().contains(needle) ||
                  u.email.toLowerCase().contains(needle),
            )
            .toList()
          ..sort(
            (AppUser a, AppUser b) => a.displayName.compareTo(b.displayName),
          );

    final int offset = cursor is int ? cursor : 0;
    final int end = (offset + pageSize).clamp(0, matching.length);
    final List<AppUser> items = offset >= matching.length
        ? const <AppUser>[]
        : matching.sublist(offset, end);
    final bool hasMore = end < matching.length;
    return ok((
      items: items,
      nextCursor: hasMore ? end : null,
      hasMore: hasMore,
    ));
  }

  @override
  Future<Result<AppUser>> getUser(String userId) async {
    final AppUser? user = _users[userId];
    if (user == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That user could not be found.',
          entityType: 'user',
          entityId: userId,
        ),
      );
    }
    return ok(user);
  }

  @override
  Future<Result<AppUser>> createUser(AppUser user) async {
    final String email = user.email.trim().toLowerCase();
    if (_emails.contains(email)) {
      final AppUser existing = _users.values.firstWhere(
        (AppUser u) => u.email.trim().toLowerCase() == email,
      );
      return err(
        DuplicateFailure(
          userMessage:
              'An account already exists for this email address. Ask a Super '
              'Admin to change its role or schools instead of creating a '
              'second one.',
          entityType: 'user',
          entityId: existing.userId,
          details: <String, String>{'role': existing.role.displayName},
        ),
      );
    }
    _users[user.userId] = user;
    _emails.add(email);
    return ok(user);
  }

  @override
  Future<Result<AppUser>> updateUser(AppUser user) async {
    final AppUser? existing = _users[user.userId];
    if (existing == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That user could not be found.',
          entityType: 'user',
          entityId: user.userId,
        ),
      );
    }
    if (existing.email.trim().toLowerCase() !=
        user.email.trim().toLowerCase()) {
      // The email is the sign-in identity and the uniqueness guard's key.
      // Changing it here would leave the guard pointing at the old address
      // and let a second account claim it.
      return err(
        const ValidationFailure(
          userMessage:
              'An email address cannot be changed. Deactivate this account and '
              'create a new one.',
          diagnostic: 'attempted email change on update',
        ),
      );
    }
    _users[user.userId] = user;
    return ok(user);
  }
}
