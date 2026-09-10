/// Whether a submission's answers still need a human's eyes
/// (docs/02-data-model.md section 6).
///
/// `notRequired` is the correct, non-guessed value for every submission this
/// phase creates: Phase 5 (capture) never detects an answer, so there is
/// nothing yet for a human to validate. Phase 6's detection is what can
/// first produce a low-confidence or unreadable answer and move a
/// submission to `pending` — this is not this phase declaring "no review
/// needed", only "no review is currently outstanding".
library;

enum ValidationStatus {
  notRequired('NOT_REQUIRED'),
  pending('PENDING'),
  inProgress('IN_PROGRESS'),
  completed('COMPLETED');

  const ValidationStatus(this.wireName);

  final String wireName;

  static final Map<String, ValidationStatus> _byWireName =
      <String, ValidationStatus>{
        for (final ValidationStatus status in ValidationStatus.values)
          status.wireName: status,
      };

  static ValidationStatus? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];
}
