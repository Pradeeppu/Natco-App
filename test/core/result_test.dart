/// Tests for the Result type and the guard helpers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';

void main() {
  final Failure failure = NetworkFailure.timeout(diagnostic: 'test');

  group('construction and inspection', () {
    test('a success carries its value', () {
      final Result<int> result = ok(42);
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.failureOrNull, isNull);
    });

    test('a failure carries its failure', () {
      final Result<int> result = err<int>(failure);
      expect(result.isFailure, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, failure);
    });

    test('a success can legitimately hold null', () {
      final Result<int?> result = ok<int?>(null);
      expect(result.isSuccess, isTrue);
      // valueOrNull cannot distinguish this case, which is why isSuccess
      // exists and callers pattern-match rather than null-check.
      expect(result.valueOrNull, isNull);
    });

    test('valueOr supplies a fallback only on failure', () {
      expect(ok(7).valueOr(0), 7);
      expect(err<int>(failure).valueOr(0), 0);
    });
  });

  group('transformations', () {
    test('map transforms a success', () {
      expect(ok(2).map((int v) => v * 3).valueOrNull, 6);
    });

    test('map leaves a failure untouched and does not run the transform', () {
      var ran = false;
      final Result<int> result = err<int>(failure).map((int v) {
        ran = true;
        return v;
      });
      expect(ran, isFalse);
      expect(result.failureOrNull, failure);
    });

    test('flatMap chains', () {
      expect(ok(2).flatMap((int v) => ok(v + 1)).valueOrNull, 3);
      expect(
        ok(2).flatMap((int v) => err<int>(failure)).failureOrNull,
        failure,
      );
      expect(
        err<int>(failure).flatMap((int v) => ok(v + 1)).failureOrNull,
        failure,
      );
    });

    test('fold collapses both branches', () {
      expect(
        ok(2).fold(onSuccess: (int v) => 'v$v', onFailure: (_) => 'f'),
        'v2',
      );
      expect(
        err<int>(failure).fold(
          onSuccess: (int v) => 'v$v',
          onFailure: (Failure f) => 'f${f.code.name}',
        ),
        'ftimeout',
      );
    });
  });

  group('side effects', () {
    test('onSuccess runs only on success and returns the same result', () {
      int? seen;
      final Result<int> input = ok(5);
      final Result<int> output = input.onSuccess((int v) => seen = v);
      expect(seen, 5);
      expect(output, input);

      seen = null;
      err<int>(failure).onSuccess((int v) => seen = v);
      expect(seen, isNull);
    });

    test('onFailure runs only on failure', () {
      Failure? seen;
      err<int>(failure).onFailure((Failure f) => seen = f);
      expect(seen, failure);

      seen = null;
      ok(1).onFailure((Failure f) => seen = f);
      expect(seen, isNull);
    });
  });

  group('guard', () {
    test('wraps a returned value', () {
      expect(guard(() => 3).valueOrNull, 3);
    });

    test('converts a throw into an UnexpectedFailure with its cause', () {
      final Result<int> result = guard<int>(() => throw StateError('boom'));
      expect(result.failureOrNull, isA<UnexpectedFailure>());
      expect(result.failureOrNull!.code, FailureCode.unexpected);
      expect(result.failureOrNull!.cause, isA<StateError>());
      expect(result.failureOrNull!.stackTrace, isNotNull);
      // The technical detail is kept for logs, not for the screen.
      expect(result.failureOrNull!.diagnostic, contains('boom'));
      expect(result.failureOrNull!.userMessage, isNot(contains('boom')));
    });

    test('honours a custom error mapper', () {
      final Result<int> result = guard<int>(
        () => throw StateError('boom'),
        onError: (Object _, StackTrace _) => NetworkFailure.offline(),
      );
      expect(result.failureOrNull!.code, FailureCode.offline);
    });
  });

  group('guardAsync', () {
    test('wraps a resolved future', () async {
      expect((await guardAsync(() async => 3)).valueOrNull, 3);
    });

    test('converts a thrown async error', () async {
      final Result<int> result = await guardAsync<int>(
        () async => throw StateError('boom'),
      );
      expect(result.failureOrNull, isA<UnexpectedFailure>());
    });

    test('honours a custom error mapper', () async {
      final Result<int> result = await guardAsync<int>(
        () async => throw StateError('boom'),
        onError: (Object _, StackTrace _) =>
            PermissionFailure.denied(action: 'do that'),
      );
      expect(result.failureOrNull!.code, FailureCode.permissionDenied);
    });
  });

  group('equality', () {
    test('successes with equal values are equal', () {
      expect(ok(1), ok(1));
      expect(ok(1).hashCode, ok(1).hashCode);
      expect(ok(1), isNot(ok(2)));
    });

    test('failures with the same failure are equal', () {
      expect(err<int>(failure), err<int>(failure));
    });

    test('a success is never equal to a failure', () {
      expect(ok(1), isNot(err<int>(failure)));
    });
  });
}
