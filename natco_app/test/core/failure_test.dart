/// Tests for the failure hierarchy.
///
/// Two properties matter: a user-facing message never leaks technical detail
/// (requirement section 40), and retryability is classified correctly, because
/// the sync engine decides between backoff and surfacing a failure to a human
/// based on it (docs/06-offline-sync-strategy.md).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';

void main() {
  final List<Failure> allFailures = <Failure>[
    NetworkFailure.offline(),
    NetworkFailure.timeout(),
    NetworkFailure.unreachable(),
    AuthFailure.invalidCredentials(),
    AuthFailure.accountDisabled(),
    AuthFailure.sessionExpired(),
    AuthFailure.unauthenticated(),
    AuthFailure.tooManyAttempts(),
    PermissionFailure.denied(action: 'validate OMR sheets'),
    PermissionFailure.outOfScope(),
    const ValidationFailure(userMessage: 'Enter a grade.'),
    const DuplicateFailure(
      userMessage: 'This OMR has already been submitted.',
      entityType: 'omr',
      entityId: '0001827',
    ),
    const ConflictFailure(
      userMessage: 'This record was changed elsewhere.',
      entityType: 'session',
      entityId: 's1',
      localRevision: 4,
      serverRevision: 5,
    ),
    StorageFailure.localWrite(),
    StorageFailure.uploadFailed(),
    const NotFoundFailure(
      userMessage: 'That record could not be found.',
      entityType: 'student',
      entityId: 's1',
    ),
    const IllegalStateTransitionFailure(
      entityType: 'omr',
      from: 'CAPTURED',
      to: 'SCORED',
    ),
    const ConfigurationFailure(userMessage: 'This app is not configured.'),
    const UnexpectedFailure(),
  ];

  group('user-facing messages', () {
    test('are present and read as sentences', () {
      for (final Failure failure in allFailures) {
        expect(failure.userMessage, isNotEmpty, reason: '$failure');
        expect(
          failure.userMessage.endsWith('.'),
          isTrue,
          reason: '${failure.runtimeType} message is not a sentence',
        );
      }
    });

    test('never contain technical detail', () {
      for (final Failure failure in allFailures) {
        for (final String forbidden in <String>[
          'Exception',
          'Error',
          'Firebase',
          'null',
          'permission-denied',
          'stack',
          'Hive',
          'Firestore',
        ]) {
          expect(
            failure.userMessage,
            isNot(contains(forbidden)),
            reason: '${failure.runtimeType} leaked "$forbidden"',
          );
        }
      }
    });

    test('reassure the user when data is held locally', () {
      // Requirement section 40: preserve local data, then say so.
      expect(NetworkFailure.offline().userMessage, contains('this device'));
      expect(
        StorageFailure.uploadFailed().userMessage,
        contains('this device'),
      );
      expect(NetworkFailure.unreachable().userMessage, contains('this device'));
      expect(const UnexpectedFailure().userMessage, contains('safe'));
    });

    test('do not reveal whether an email address exists', () {
      // Otherwise the sign-in form becomes an account-enumeration oracle.
      final String message = AuthFailure.invalidCredentials().userMessage;
      expect(message, contains('email or password'));
      expect(message.toLowerCase(), isNot(contains('no account')));
      expect(message.toLowerCase(), isNot(contains('not registered')));
    });
  });

  group('retryability', () {
    test('transient conditions are retryable', () {
      for (final Failure failure in <Failure>[
        NetworkFailure.offline(),
        NetworkFailure.timeout(),
        NetworkFailure.unreachable(),
        AuthFailure.sessionExpired(),
        StorageFailure.uploadFailed(),
      ]) {
        expect(failure.isRetryable, isTrue, reason: '$failure');
      }
    });

    test('definitive rejections are not retryable', () {
      // Retrying a permission denial forever looks like a bug to the user and
      // hides the real problem.
      for (final Failure failure in <Failure>[
        PermissionFailure.denied(),
        PermissionFailure.outOfScope(),
        AuthFailure.invalidCredentials(),
        AuthFailure.accountDisabled(),
        const ValidationFailure(userMessage: 'Enter a grade.'),
        const DuplicateFailure(
          userMessage: 'Already submitted.',
          entityType: 'omr',
          entityId: '1',
        ),
        const ConflictFailure(
          userMessage: 'Changed elsewhere.',
          entityType: 'session',
          entityId: 's1',
          localRevision: 1,
          serverRevision: 2,
        ),
        const NotFoundFailure(
          userMessage: 'Not found.',
          entityType: 'student',
          entityId: 's1',
        ),
        const UnexpectedFailure(),
      ]) {
        expect(failure.isRetryable, isFalse, reason: '$failure');
      }
    });
  });

  group('structured detail for the caller', () {
    test('a duplicate carries the earlier submission details to show', () {
      // Requirement section 22: the dialog names the previous submission
      // rather than rejecting with nothing.
      const DuplicateFailure failure = DuplicateFailure(
        userMessage: 'This OMR has already been submitted.',
        entityType: 'omr_submission',
        entityId: '0001827',
        details: <String, String>{
          'School': 'ABC School',
          'Date': '08 Sep 2026',
          'Time': '10:42 AM',
        },
      );
      expect(failure.entityId, '0001827');
      expect(failure.details['School'], 'ABC School');
    });

    test('a conflict carries both revisions', () {
      const ConflictFailure failure = ConflictFailure(
        userMessage: 'Changed elsewhere.',
        entityType: 'session',
        entityId: 's1',
        localRevision: 4,
        serverRevision: 5,
      );
      expect(failure.localRevision, 4);
      expect(failure.serverRevision, 5);
    });

    test('a validation failure can carry per-field messages', () {
      const ValidationFailure failure = ValidationFailure(
        userMessage: 'Please correct the highlighted fields.',
        fieldErrors: <String, String>{'grade': 'Choose a grade.'},
      );
      expect(failure.fieldErrors['grade'], 'Choose a grade.');
    });

    test('an illegal transition names both states for the log', () {
      const IllegalStateTransitionFailure failure =
          IllegalStateTransitionFailure(
            entityType: 'omr',
            from: 'CAPTURED',
            to: 'SCORED',
          );
      expect(failure.from, 'CAPTURED');
      expect(failure.to, 'SCORED');
      expect(failure.code, FailureCode.illegalStateTransition);
    });
  });

  test('toString is log-shaped and includes the code', () {
    expect(
      NetworkFailure.timeout().toString(),
      startsWith('NetworkFailure(timeout):'),
    );
  });

  test('every failure code is reachable from some failure', () {
    final Set<FailureCode> used = allFailures
        .map((Failure f) => f.code)
        .toSet();
    final Set<FailureCode> unused = FailureCode.values.toSet()..removeAll(used);
    // These are produced by phases that own the corresponding pipeline stage.
    expect(unused, <FailureCode>{
      FailureCode.imageQuality,
      FailureCode.omrProcessing,
    });
  });
}
