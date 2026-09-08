/// Injectable time source.
///
/// Nothing in the domain calls `DateTime.now()` directly. Session expiry,
/// sync backoff windows and audit timestamps all depend on time, and a test
/// that cannot control time either sleeps or is flaky.
///
/// All times are UTC. Field devices in different time zones write audit
/// records that have to be ordered against each other, and local time makes
/// that ordering wrong for exactly as long as nobody checks.
library;

abstract interface class Clock {
  /// Current instant, in UTC.
  DateTime nowUtc();
}

/// Production clock.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// Test clock with an explicitly settable instant.
final class FixedClock implements Clock {
  FixedClock(DateTime instant) : _instant = instant.toUtc();

  DateTime _instant;

  @override
  DateTime nowUtc() => _instant;

  /// Moves the clock forward (or backward, with a negative duration).
  void advance(Duration by) => _instant = _instant.add(by);

  /// Jumps to an absolute instant.
  void set(DateTime instant) => _instant = instant.toUtc();
}
