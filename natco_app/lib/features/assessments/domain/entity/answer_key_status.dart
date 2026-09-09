/// An answer key version's lifecycle (docs/02-data-model.md section 4).
///
/// `PUBLISHED` is a one-way door: once a key reaches it, that document is
/// immutable (enforced by the repository exposing no update method at all,
/// not by a convention a caller could forget) and the only way to change the
/// answers is to publish the *next* version, which marks this one
/// `SUPERSEDED`.
library;

enum AnswerKeyStatus {
  draft('DRAFT'),
  published('PUBLISHED'),
  superseded('SUPERSEDED');

  const AnswerKeyStatus(this.wireName);

  final String wireName;
}
