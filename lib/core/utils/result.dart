/// A success-or-failure value, used as the return type of every repository and
/// use-case method in the domain layer.
///
/// The point is not functional purity; it is that an expected failure cannot
/// be forgotten. A `try`/`catch` around a call is easy to omit, while a
/// [Result] has to be destructured before the value inside it can be used.
library;

import 'package:natco_app/core/errors/failure.dart';

/// Either a [Success] carrying a `T`, or a [FailureResult] carrying a
/// [Failure].
sealed class Result<T> {
  const Result();

  /// Wraps a value.
  const factory Result.success(T value) = Success<T>;

  /// Wraps a failure.
  const factory Result.failure(Failure failure) = FailureResult<T>;

  bool get isSuccess => this is Success<T>;

  bool get isFailure => this is FailureResult<T>;

  /// The value, or `null` when this is a failure.
  T? get valueOrNull => switch (this) {
    Success<T>(:final value) => value,
    FailureResult<T>() => null,
  };

  /// The failure, or `null` when this is a success.
  Failure? get failureOrNull => switch (this) {
    Success<T>() => null,
    FailureResult<T>(:final failure) => failure,
  };

  /// The value, or [fallback] when this is a failure.
  T valueOr(T fallback) => valueOrNull ?? fallback;

  /// Transforms the success value, leaving a failure untouched.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Success<T>(:final value) => Result<R>.success(transform(value)),
    FailureResult<T>(:final failure) => Result<R>.failure(failure),
  };

  /// Chains another [Result]-returning operation.
  Result<R> flatMap<R>(Result<R> Function(T value) transform) => switch (this) {
    Success<T>(:final value) => transform(value),
    FailureResult<T>(:final failure) => Result<R>.failure(failure),
  };

  /// Collapses both branches into a single value.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Failure failure) onFailure,
  }) => switch (this) {
    Success<T>(:final value) => onSuccess(value),
    FailureResult<T>(:final failure) => onFailure(failure),
  };

  /// Runs [action] only on success. Useful for side effects such as audit
  /// writes, without breaking the chain.
  Result<T> onSuccess(void Function(T value) action) {
    if (this case Success<T>(:final value)) {
      action(value);
    }
    return this;
  }

  /// Runs [action] only on failure.
  Result<T> onFailure(void Function(Failure failure) action) {
    if (this case FailureResult<T>(:final failure)) {
      action(failure);
    }
    return this;
  }
}

final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Success<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Success<T>, value);

  @override
  String toString() => 'Success<$T>($value)';
}

final class FailureResult<T> extends Result<T> {
  const FailureResult(this.failure);

  final Failure failure;

  @override
  bool operator ==(Object other) =>
      other is FailureResult<T> && other.failure == failure;

  @override
  int get hashCode => Object.hash(FailureResult<T>, failure);

  @override
  String toString() => 'FailureResult<$T>($failure)';
}

/// Shorthand for a successful result.
Result<T> ok<T>(T value) => Result<T>.success(value);

/// Shorthand for a failed result.
Result<T> err<T>(Failure failure) => Result<T>.failure(failure);

/// Runs [body], converting any thrown object into an [UnexpectedFailure].
///
/// This is the single place where an unexpected `throw` becomes a [Result].
/// Feature code should not contain bare `try`/`catch` blocks around
/// infrastructure calls; it should wrap them here so that nothing is
/// swallowed and everything is logged with its cause.
Future<Result<T>> guardAsync<T>(
  Future<T> Function() body, {
  Failure Function(Object error, StackTrace stackTrace)? onError,
}) async {
  try {
    return ok(await body());
  } catch (error, stackTrace) {
    if (onError != null) {
      return err(onError(error, stackTrace));
    }
    return err(
      UnexpectedFailure(
        diagnostic: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      ),
    );
  }
}

/// Recovers a [Failure] from an object thrown into an `AsyncValue.error` —
/// the read-side counterpart of [guardAsync]. A `PagedListController`
/// (`lib/core/pagination/paged_list_controller.dart`) throws a domain
/// [Failure] verbatim so it round-trips through Riverpod's error slot
/// unchanged; this is what a screen calls to render that slot with
/// `FailureView`. Anything that is not already a [Failure] is a bug rather
/// than an expected condition, so it still gets a safe, generic message
/// instead of reaching the screen raw (requirement §40).
Failure asFailure(Object error) =>
    error is Failure
        ? error
        : UnexpectedFailure(diagnostic: error.toString(), cause: error);

/// Synchronous counterpart to [guardAsync].
Result<T> guard<T>(
  T Function() body, {
  Failure Function(Object error, StackTrace stackTrace)? onError,
}) {
  try {
    return ok(body());
  } catch (error, stackTrace) {
    if (onError != null) {
      return err(onError(error, stackTrace));
    }
    return err(
      UnexpectedFailure(
        diagnostic: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      ),
    );
  }
}
