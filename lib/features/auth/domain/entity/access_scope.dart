/// Geographic access scope.
///
/// Permissions answer *what* a user may do; the scope answers *which* schools
/// they may do it to. Both are checked, on the client for usability and on the
/// server for enforcement (docs/04-security-model.md).
///
/// Every entity in the system carries denormalised ancestry — `stateId`,
/// `districtId`, `clusterId`, `schoolId` — so a scope check is a single
/// set-membership test with no additional reads, both here and inside a
/// Firestore rule.
library;

/// How wide a user's reach is.
enum ScopeLevel {
  /// Everything. Super Admin only.
  global('GLOBAL'),
  state('STATE'),
  district('DISTRICT'),
  cluster('CLUSTER'),
  school('SCHOOL');

  const ScopeLevel(this.wireName);

  final String wireName;

  static final Map<String, ScopeLevel> _byWireName = <String, ScopeLevel>{
    for (final ScopeLevel level in ScopeLevel.values) level.wireName: level,
  };

  static ScopeLevel? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];
}

/// A grade and section pair, e.g. Grade 5 Section A.
///
/// A teacher assigned to 5-A must not open 5-B's session even in their own
/// school, which is Critical Rule 10 enforced one level below the school.
final class GradeSection implements Comparable<GradeSection> {
  const GradeSection({required this.grade, required this.section});

  /// Parses `"5-A"`. Returns `null` on anything else rather than throwing,
  /// because this parses stored data that an older or newer build may have
  /// written differently.
  static GradeSection? tryParse(String value) {
    final int separator = value.indexOf('-');
    if (separator <= 0 || separator == value.length - 1) {
      return null;
    }
    return GradeSection(
      grade: value.substring(0, separator).trim(),
      section: value.substring(separator + 1).trim(),
    );
  }

  final String grade;
  final String section;

  /// Wire form, `"5-A"`.
  String get wireName => '$grade-$section';

  /// Label for the UI, `"Grade 5 - Section A"`.
  String get displayName => 'Grade $grade - Section $section';

  @override
  int compareTo(GradeSection other) {
    final int gradeComparison = _compareGrades(grade, other.grade);
    return gradeComparison != 0
        ? gradeComparison
        : section.compareTo(other.section);
  }

  /// Orders grades numerically when both are numbers, so Grade 10 sorts after
  /// Grade 9 rather than between Grade 1 and Grade 2.
  static int _compareGrades(String a, String b) {
    final int? left = int.tryParse(a);
    final int? right = int.tryParse(b);
    if (left != null && right != null) {
      return left.compareTo(right);
    }
    return a.compareTo(b);
  }

  @override
  bool operator ==(Object other) =>
      other is GradeSection && other.grade == grade && other.section == section;

  @override
  int get hashCode => Object.hash(grade, section);

  @override
  String toString() => wireName;
}

/// A target's position in the hierarchy, as far as the caller knows it.
///
/// Any field may be `null` — a school list row knows its cluster, a student
/// row knows its school. Matching uses the most specific field available.
final class ScopeTarget {
  const ScopeTarget({
    this.stateId,
    this.districtId,
    this.clusterId,
    this.schoolId,
    this.grade,
    this.section,
  });

  /// A target identified only by school. The remaining ancestry is unknown to
  /// the caller.
  const ScopeTarget.school(String schoolId) : this(schoolId: schoolId);

  final String? stateId;
  final String? districtId;
  final String? clusterId;
  final String? schoolId;
  final String? grade;
  final String? section;

  GradeSection? get gradeSection => (grade == null || section == null)
      ? null
      : GradeSection(grade: grade!, section: section!);

  /// Whether any ancestry at all is known.
  bool get isUnidentified =>
      stateId == null &&
      districtId == null &&
      clusterId == null &&
      schoolId == null;
}

/// A user's geographic reach.
final class AccessScope {
  const AccessScope({
    required this.level,
    this.stateIds = const <String>{},
    this.districtIds = const <String>{},
    this.clusterIds = const <String>{},
    this.schoolIds = const <String>{},
    this.gradeSections = const <GradeSection>{},
  });

  /// Unrestricted reach.
  const AccessScope.global() : this(level: ScopeLevel.global);

  /// A single school, optionally narrowed to specific grade-sections.
  AccessScope.singleSchool(
    String schoolId, {
    Set<GradeSection> gradeSections = const <GradeSection>{},
  }) : this(
         level: ScopeLevel.school,
         schoolIds: <String>{schoolId},
         gradeSections: gradeSections,
       );

  final ScopeLevel level;
  final Set<String> stateIds;
  final Set<String> districtIds;
  final Set<String> clusterIds;
  final Set<String> schoolIds;

  /// Teacher-level narrowing. Empty means "every grade-section in the schools
  /// this scope covers".
  final Set<GradeSection> gradeSections;

  bool get isGlobal => level == ScopeLevel.global;

  /// The ids that define this scope, at its own level.
  Set<String> get definingIds => switch (level) {
    ScopeLevel.global => const <String>{},
    ScopeLevel.state => stateIds,
    ScopeLevel.district => districtIds,
    ScopeLevel.cluster => clusterIds,
    ScopeLevel.school => schoolIds,
  };

  /// Whether this scope is usable.
  ///
  /// A non-global scope with no ids reaches nothing. That is a configuration
  /// error, and it must be reported rather than silently behaving as either
  /// "everything" (a privilege escalation) or "nothing" (a user who cannot
  /// work and does not know why).
  bool get isValid => isGlobal || definingIds.isNotEmpty;

  /// Whether [target] falls inside this scope.
  ///
  /// Matching is deliberately conservative:
  ///
  /// * A global scope matches everything.
  /// * Otherwise the target must positively match on the scope's own level, or
  ///   on a *narrower* level the scope also enumerates. A cluster-scoped
  ///   Supervisor matches a school only when that school's `clusterId` is in
  ///   `clusterIds`, or the school itself is in `schoolIds`.
  /// * A target that carries no information about the scope's level does not
  ///   match. Absence of evidence is not access — a row whose cluster is
  ///   unknown could belong to any cluster, and guessing in the permissive
  ///   direction is how a Supervisor ends up reading another district's data.
  bool covers(ScopeTarget target) {
    if (isGlobal) {
      return true;
    }
    if (target.isUnidentified) {
      return false;
    }
    if (!_coversGeography(target)) {
      return false;
    }
    return _coversGradeSection(target);
  }

  bool _coversGeography(ScopeTarget target) {
    // An explicitly enumerated school always matches, whatever the level.
    if (target.schoolId != null && schoolIds.contains(target.schoolId)) {
      return true;
    }
    return switch (level) {
      ScopeLevel.global => true,
      ScopeLevel.state =>
        target.stateId != null && stateIds.contains(target.stateId),
      ScopeLevel.district =>
        target.districtId != null && districtIds.contains(target.districtId),
      ScopeLevel.cluster =>
        target.clusterId != null && clusterIds.contains(target.clusterId),
      // At school level, the enumerated-school check above is the only way in.
      ScopeLevel.school => false,
    };
  }

  bool _coversGradeSection(ScopeTarget target) {
    if (gradeSections.isEmpty) {
      return true;
    }
    final GradeSection? targetGradeSection = target.gradeSection;
    // A scope narrowed to specific grade-sections cannot authorise a target
    // that does not say which grade-section it belongs to.
    if (targetGradeSection == null) {
      return target.grade == null && target.section == null
          ? false
          : gradeSections.any(
              (GradeSection gs) =>
                  (target.grade == null || gs.grade == target.grade) &&
                  (target.section == null || gs.section == target.section),
            );
    }
    return gradeSections.contains(targetGradeSection);
  }

  /// Whether everything this scope reaches is also reachable by [other].
  ///
  /// [covers] answers "may this user touch that row". This answers "is this
  /// user's whole reach inside that user's reach", which is a different
  /// question and the one user management needs: a Supervisor may list, and
  /// hand scope to, only people who cannot see past the Supervisor's own
  /// boundary.
  ///
  /// The test runs at [other]'s level, using this scope's denormalised
  /// ancestry — a school-level scope created through `UserRepositoryImpl`
  /// carries its cluster, district and state alongside its schools, so a
  /// cluster-scoped Supervisor can evaluate it without a lookup.
  ///
  /// Conservative in the same way [covers] is: if this scope names nothing at
  /// [other]'s level, containment cannot be *proven* and the answer is `false`.
  /// A scope whose ancestry was never denormalised is unreadable, not
  /// unrestricted.
  bool isWithin(AccessScope other) {
    if (other.isGlobal) {
      return true;
    }
    // Only a global scope contains a global scope, and that is handled above.
    if (isGlobal) {
      return false;
    }
    final Set<String> mineAtOtherLevel = switch (other.level) {
      ScopeLevel.global => const <String>{},
      ScopeLevel.state => stateIds,
      ScopeLevel.district => districtIds,
      ScopeLevel.cluster => clusterIds,
      ScopeLevel.school => schoolIds,
    };
    if (mineAtOtherLevel.isEmpty) {
      return false;
    }
    return other.definingIds.containsAll(mineAtOtherLevel);
  }

  /// Compact claims form, matching what `onUserWrite` writes into the ID token
  /// (docs/04-security-model.md).
  Map<String, Object?> toClaims() => <String, Object?>{
    'lvl': level.wireName,
    'st': stateIds.toList(growable: false),
    'di': districtIds.toList(growable: false),
    'cl': clusterIds.toList(growable: false),
    'sc': schoolIds.toList(growable: false),
    if (gradeSections.isNotEmpty)
      'gs': gradeSections
          .map((GradeSection gs) => gs.wireName)
          .toList(growable: false),
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'level': level.wireName,
    'stateIds': stateIds.toList(growable: false),
    'districtIds': districtIds.toList(growable: false),
    'clusterIds': clusterIds.toList(growable: false),
    'schoolIds': schoolIds.toList(growable: false),
    'gradeSections': gradeSections
        .map((GradeSection gs) => gs.wireName)
        .toList(growable: false),
  };

  /// Reads a scope from stored JSON or from custom claims.
  ///
  /// Returns `null` when the level is missing or unrecognised. The caller
  /// refuses the session in that case: a user whose reach cannot be determined
  /// gets no reach at all.
  static AccessScope? tryFromJson(Map<String, Object?> json) {
    final ScopeLevel? level =
        ScopeLevel.tryFromWireName(json['level'] as String?) ??
        ScopeLevel.tryFromWireName(json['lvl'] as String?);
    if (level == null) {
      return null;
    }
    Set<String> ids(String primary, String claim) {
      final Object? value = json[primary] ?? json[claim];
      if (value is! Iterable) {
        return const <String>{};
      }
      return value.whereType<String>().toSet();
    }

    final Object? rawGradeSections = json['gradeSections'] ?? json['gs'];
    final Set<GradeSection> gradeSections = rawGradeSections is Iterable
        ? rawGradeSections
              .whereType<String>()
              .map(GradeSection.tryParse)
              .whereType<GradeSection>()
              .toSet()
        : const <GradeSection>{};

    return AccessScope(
      level: level,
      stateIds: ids('stateIds', 'st'),
      districtIds: ids('districtIds', 'di'),
      clusterIds: ids('clusterIds', 'cl'),
      schoolIds: ids('schoolIds', 'sc'),
      gradeSections: gradeSections,
    );
  }

  AccessScope copyWith({
    ScopeLevel? level,
    Set<String>? stateIds,
    Set<String>? districtIds,
    Set<String>? clusterIds,
    Set<String>? schoolIds,
    Set<GradeSection>? gradeSections,
  }) => AccessScope(
    level: level ?? this.level,
    stateIds: stateIds ?? this.stateIds,
    districtIds: districtIds ?? this.districtIds,
    clusterIds: clusterIds ?? this.clusterIds,
    schoolIds: schoolIds ?? this.schoolIds,
    gradeSections: gradeSections ?? this.gradeSections,
  );

  @override
  bool operator ==(Object other) =>
      other is AccessScope &&
      other.level == level &&
      _setEquals(other.stateIds, stateIds) &&
      _setEquals(other.districtIds, districtIds) &&
      _setEquals(other.clusterIds, clusterIds) &&
      _setEquals(other.schoolIds, schoolIds) &&
      _setEquals(other.gradeSections, gradeSections);

  @override
  int get hashCode => Object.hash(
    level,
    Object.hashAllUnordered(stateIds),
    Object.hashAllUnordered(districtIds),
    Object.hashAllUnordered(clusterIds),
    Object.hashAllUnordered(schoolIds),
    Object.hashAllUnordered(gradeSections),
  );

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  String toString() =>
      'AccessScope(${level.wireName}, ids=${definingIds.length}, '
      'gradeSections=${gradeSections.length})';
}
