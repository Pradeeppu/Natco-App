/// Student gender, per requirement section 11.
library;

enum Gender {
  male('MALE'),
  female('FEMALE'),
  other('OTHER'),
  notSpecified('NOT_SPECIFIED');

  const Gender(this.wireName);

  final String wireName;

  /// Unrecognised or missing values resolve to [notSpecified] rather than
  /// throwing — an older or newer build must not crash on this field, and
  /// "not specified" is the one value that is always a safe default.
  static Gender fromWireName(String? name) {
    for (final Gender gender in Gender.values) {
      if (gender.wireName == name) {
        return gender;
      }
    }
    return Gender.notSpecified;
  }
}
