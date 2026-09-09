/// Tests for the cached session record and its expiry.
///
/// Expiry is measured from the last *verification*, not from sign-in, so a
/// device that reconnects daily stays usable while one that never reconnects
/// stops on schedule (docs/04-security-model.md).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/auth_session.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

final DateTime _t0 = DateTime.utc(2026, 9, 1, 8);
const Duration _validity = Duration(days: 7);

AppUser _user({bool isActive = true}) => AppUser(
  userId: 'u1',
  email: 'teacher@natco.test',
  displayName: 'Suresh Babu',
  role: UserRole.pstTeacher,
  scope: AccessScope.singleSchool('sch1'),
  isActive: isActive,
  claimsVersion: 3,
);

AuthSession _session({
  DateTime? lastVerifiedAt,
  bool isActive = true,
  SessionOrigin origin = SessionOrigin.online,
}) => AuthSession(
  user: _user(isActive: isActive),
  establishedAt: _t0,
  lastVerifiedAt: lastVerifiedAt ?? _t0,
  origin: origin,
  deviceId: 'device-1',
);

void main() {
  group('AppUser', () {
    test('round-trips through JSON', () {
      final AppUser user = _user();
      expect(AppUser.tryFromJson(user.toJson()), user);
    });

    test('refuses a record whose role cannot be resolved', () {
      // Role is load-bearing for authorization, so a record this build cannot
      // fully understand is refused rather than partially trusted.
      final Map<String, Object?> json = _user().toJson()
        ..['role'] = 'COORDINATOR'; // allow-coordinator-reference
      expect(AppUser.tryFromJson(json), isNull);
    });

    test('refuses a record whose scope is missing or unusable', () {
      expect(AppUser.tryFromJson(_user().toJson()..remove('scope')), isNull);
      expect(
        AppUser.tryFromJson(
          _user().toJson()
            ..['scope'] = <String, Object?>{
              'level': 'CLUSTER',
              'clusterIds': <String>[],
            },
        ),
        isNull,
        reason: 'a cluster scope with no clusters reaches nothing',
      );
    });

    test('refuses a record with no user id', () {
      expect(AppUser.tryFromJson(_user().toJson()..['userId'] = ''), isNull);
    });

    test('shortName takes the first name, falling back to the email', () {
      expect(_user().shortName, 'Suresh');
      expect(
        _user().copyWith(displayName: '   ').shortName,
        'teacher@natco.test',
      );
      expect(_user().copyWith(displayName: 'Asha').shortName, 'Asha');
    });

    test('toString omits email and display name, because logs see it', () {
      final String rendered = _user().toString();
      expect(rendered, contains('u1'));
      expect(rendered, contains('PST_TEACHER'));
      expect(rendered, isNot(contains('teacher@natco.test')));
      expect(rendered, isNot(contains('Suresh')));
    });
  });

  group('AuthSession validity', () {
    test('is valid immediately after verification', () {
      expect(_session().isValidAt(_t0, _validity), isTrue);
    });

    test('is valid just before the window closes', () {
      final DateTime almost = _t0.add(_validity - const Duration(minutes: 1));
      expect(_session().isValidAt(almost, _validity), isTrue);
    });

    test('is invalid once the window has elapsed', () {
      expect(_session().isValidAt(_t0.add(_validity), _validity), isFalse);
      expect(
        _session().isValidAt(_t0.add(const Duration(days: 30)), _validity),
        isFalse,
      );
    });

    test('measures the window from the last verification, not sign-in', () {
      // Established a week ago, verified an hour ago: still usable.
      final AuthSession refreshed = AuthSession(
        user: _user(),
        establishedAt: _t0,
        lastVerifiedAt: _t0.add(const Duration(days: 6, hours: 23)),
        origin: SessionOrigin.online,
        deviceId: 'device-1',
      );
      expect(
        refreshed.isValidAt(
          _t0.add(const Duration(days: 7, hours: 1)),
          _validity,
        ),
        isTrue,
      );
    });

    test('a deactivated user is never valid, however recent', () {
      expect(_session(isActive: false).isValidAt(_t0, _validity), isFalse);
    });

    test('reports the remaining window, clamped at zero', () {
      expect(_session().remainingValidity(_t0, _validity), _validity);
      expect(
        _session().remainingValidity(
          _t0.add(const Duration(days: 2)),
          _validity,
        ),
        const Duration(days: 5),
      );
      expect(
        _session().remainingValidity(
          _t0.add(const Duration(days: 90)),
          _validity,
        ),
        Duration.zero,
      );
    });
  });

  group('AuthSession serialisation', () {
    test('round-trips', () {
      final AuthSession session = _session(origin: SessionOrigin.offlineCache);
      expect(AuthSession.tryFromJson(session.toJson()), session);
    });

    test('stores no password and no token', () {
      // It is a session cache, not a credential cache.
      final String encoded = _session().toJson().toString().toLowerCase();
      for (final String forbidden in <String>[
        'password',
        'idtoken',
        'refreshtoken',
        'secret',
      ]) {
        expect(encoded, isNot(contains(forbidden)));
      }
    });

    test(
      'returns null on anything unparseable, so the user signs in again',
      () {
        expect(AuthSession.tryFromJson(<String, Object?>{}), isNull);
        expect(
          AuthSession.tryFromJson(<String, Object?>{'user': 'not-a-map'}),
          isNull,
        );
        expect(
          AuthSession.tryFromJson(
            _session().toJson()..remove('lastVerifiedAt'),
          ),
          isNull,
        );
        expect(
          AuthSession.tryFromJson(
            _session().toJson()..['establishedAt'] = 'yesterday',
          ),
          isNull,
        );
      },
    );

    test('defaults an unknown origin to online rather than failing', () {
      final AuthSession? parsed = AuthSession.tryFromJson(
        _session().toJson()..['origin'] = 'SOMETHING_ELSE',
      );
      expect(parsed, isNotNull);
      expect(parsed!.origin, SessionOrigin.online);
    });
  });
}
