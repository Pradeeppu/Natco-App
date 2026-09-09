/// Tests for geographic scope.
///
/// The behaviour under test is Critical Rule 10: a user must not reach a
/// school outside their assignment. The interesting cases are the negative
/// ones — a target that says nothing about the scope's level must not match,
/// because absence of evidence is not access.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

void main() {
  group('GradeSection', () {
    test('parses the wire form', () {
      expect(
        GradeSection.tryParse('5-A'),
        const GradeSection(grade: '5', section: 'A'),
      );
      expect(
        GradeSection.tryParse(' 10 - B '),
        const GradeSection(grade: '10', section: 'B'),
      );
    });

    test('rejects malformed values rather than throwing', () {
      expect(GradeSection.tryParse('5'), isNull);
      expect(GradeSection.tryParse('-A'), isNull);
      expect(GradeSection.tryParse('5-'), isNull);
      expect(GradeSection.tryParse(''), isNull);
    });

    test('sorts grades numerically, so Grade 10 follows Grade 9', () {
      final List<GradeSection> sections = <GradeSection>[
        const GradeSection(grade: '10', section: 'A'),
        const GradeSection(grade: '2', section: 'B'),
        const GradeSection(grade: '9', section: 'A'),
        const GradeSection(grade: '2', section: 'A'),
      ]..sort();
      expect(sections.map((GradeSection gs) => gs.wireName).toList(), <String>[
        '2-A',
        '2-B',
        '9-A',
        '10-A',
      ]);
    });

    test('renders a readable label', () {
      expect(
        const GradeSection(grade: '5', section: 'A').displayName,
        'Grade 5 - Section A',
      );
    });
  });

  group('AccessScope validity', () {
    test('a global scope is valid with no ids', () {
      expect(const AccessScope.global().isValid, isTrue);
    });

    test('a non-global scope with no ids is invalid', () {
      // It would reach nothing, and treating it as either "everything" or
      // "nothing" silently is worse than rejecting it.
      expect(const AccessScope(level: ScopeLevel.cluster).isValid, isFalse);
      expect(const AccessScope(level: ScopeLevel.school).isValid, isFalse);
    });
  });

  group('AccessScope.covers — global', () {
    test('matches everything, including an unidentified target', () {
      const AccessScope scope = AccessScope.global();
      expect(scope.covers(const ScopeTarget(schoolId: 'anything')), isTrue);
      expect(scope.covers(const ScopeTarget()), isTrue);
    });
  });

  group('AccessScope.covers — cluster (a Supervisor)', () {
    const AccessScope scope = AccessScope(
      level: ScopeLevel.cluster,
      stateIds: <String>{'st1'},
      districtIds: <String>{'di1'},
      clusterIds: <String>{'cl1', 'cl2'},
    );

    test('matches a school in an assigned cluster', () {
      expect(
        scope.covers(const ScopeTarget(clusterId: 'cl1', schoolId: 'sch1')),
        isTrue,
      );
    });

    test('rejects a school in another cluster of the same district', () {
      // Requirement section 31: a Supervisor gets no implicit reach beyond
      // their assignment.
      expect(
        scope.covers(
          const ScopeTarget(
            stateId: 'st1',
            districtId: 'di1',
            clusterId: 'cl9',
            schoolId: 'sch9',
          ),
        ),
        isFalse,
      );
    });

    test('rejects a target that does not say which cluster it belongs to', () {
      // The row could belong to any cluster. Guessing permissively is how a
      // Supervisor ends up reading another district's data.
      expect(scope.covers(const ScopeTarget(schoolId: 'sch1')), isFalse);
      expect(scope.covers(const ScopeTarget(districtId: 'di1')), isFalse);
    });

    test('rejects a completely unidentified target', () {
      expect(scope.covers(const ScopeTarget()), isFalse);
    });
  });

  group('AccessScope.covers — school (a teacher)', () {
    test('matches only the enumerated schools', () {
      final AccessScope scope = AccessScope.singleSchool('sch1');
      expect(scope.covers(const ScopeTarget(schoolId: 'sch1')), isTrue);
      expect(scope.covers(const ScopeTarget(schoolId: 'sch2')), isFalse);
    });

    test('does not match by ancestry when scoped to a school', () {
      final AccessScope scope = AccessScope.singleSchool('sch1');
      // Being in the same cluster is not access to the cluster.
      expect(scope.covers(const ScopeTarget(clusterId: 'cl1')), isFalse);
    });
  });

  group('AccessScope.covers — grade and section narrowing', () {
    final AccessScope scope = AccessScope(
      level: ScopeLevel.school,
      schoolIds: const <String>{'sch1'},
      gradeSections: <GradeSection>{
        const GradeSection(grade: '5', section: 'A'),
      },
    );

    test('matches the assigned grade and section', () {
      expect(
        scope.covers(
          const ScopeTarget(schoolId: 'sch1', grade: '5', section: 'A'),
        ),
        isTrue,
      );
    });

    test('rejects another section in the same school', () {
      // Critical Rule 10, one level below the school.
      expect(
        scope.covers(
          const ScopeTarget(schoolId: 'sch1', grade: '5', section: 'B'),
        ),
        isFalse,
      );
    });

    test('rejects another grade in the same school', () {
      expect(
        scope.covers(
          const ScopeTarget(schoolId: 'sch1', grade: '6', section: 'A'),
        ),
        isFalse,
      );
    });

    test('rejects a target with no grade or section at all', () {
      expect(scope.covers(const ScopeTarget(schoolId: 'sch1')), isFalse);
    });

    test('matches on a partially specified grade-section', () {
      // A list filtered by grade alone should still resolve; the section is
      // checked when present.
      expect(
        scope.covers(const ScopeTarget(schoolId: 'sch1', grade: '5')),
        isTrue,
      );
      expect(
        scope.covers(const ScopeTarget(schoolId: 'sch1', grade: '6')),
        isFalse,
      );
    });

    test('an empty grade-section set means every grade in the school', () {
      final AccessScope wide = AccessScope.singleSchool('sch1');
      expect(
        wide.covers(
          const ScopeTarget(schoolId: 'sch1', grade: '7', section: 'C'),
        ),
        isTrue,
      );
    });
  });

  group('AccessScope serialisation', () {
    final AccessScope scope = AccessScope(
      level: ScopeLevel.cluster,
      stateIds: const <String>{'st1'},
      districtIds: const <String>{'di1', 'di2'},
      clusterIds: const <String>{'cl1'},
      schoolIds: const <String>{'sch1'},
      gradeSections: <GradeSection>{
        const GradeSection(grade: '5', section: 'A'),
      },
    );

    test('round-trips through JSON', () {
      expect(AccessScope.tryFromJson(scope.toJson()), scope);
    });

    test('round-trips through the compact claims form', () {
      expect(AccessScope.tryFromJson(scope.toClaims()), scope);
    });

    test('returns null when the level is missing or unrecognised', () {
      expect(AccessScope.tryFromJson(<String, Object?>{}), isNull);
      expect(
        AccessScope.tryFromJson(<String, Object?>{'level': 'PLANET'}),
        isNull,
      );
    });

    test('ignores unparseable grade-sections instead of failing the scope', () {
      final AccessScope? parsed = AccessScope.tryFromJson(<String, Object?>{
        'level': 'SCHOOL',
        'schoolIds': <String>['sch1'],
        'gradeSections': <String>['5-A', 'garbage', ''],
      });
      expect(parsed, isNotNull);
      expect(parsed!.gradeSections, <GradeSection>{
        const GradeSection(grade: '5', section: 'A'),
      });
    });

    test('claims omit grade-sections when there are none', () {
      expect(const AccessScope.global().toClaims().containsKey('gs'), isFalse);
    });
  });

  test('equality is by value, and ignores set ordering', () {
    const AccessScope a = AccessScope(
      level: ScopeLevel.cluster,
      clusterIds: <String>{'cl1', 'cl2'},
    );
    const AccessScope b = AccessScope(
      level: ScopeLevel.cluster,
      clusterIds: <String>{'cl2', 'cl1'},
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  group('isWithin', () {
    test('a global scope contains everything', () {
      const global = AccessScope.global();
      expect(const AccessScope(level: ScopeLevel.school).isWithin(global), isTrue);
    });

    test('nothing but global contains a global scope', () {
      const global = AccessScope.global();
      const state = AccessScope(
        level: ScopeLevel.state,
        stateIds: <String>{'st_1'},
      );
      expect(global.isWithin(state), isFalse);
    });

    test('a school inside a cluster is within that cluster scope', () {
      const cluster = AccessScope(
        level: ScopeLevel.cluster,
        stateIds: <String>{'st_1'},
        districtIds: <String>{'di_1'},
        clusterIds: <String>{'cl_1'},
      );
      const school = AccessScope(
        level: ScopeLevel.school,
        stateIds: <String>{'st_1'},
        districtIds: <String>{'di_1'},
        clusterIds: <String>{'cl_1'},
        schoolIds: <String>{'sch_1'},
      );
      expect(school.isWithin(cluster), isTrue);
    });

    test('a school in a different cluster is not within it', () {
      const cluster = AccessScope(
        level: ScopeLevel.cluster,
        stateIds: <String>{'st_1'},
        districtIds: <String>{'di_1'},
        clusterIds: <String>{'cl_1'},
      );
      const school = AccessScope(
        level: ScopeLevel.school,
        stateIds: <String>{'st_1'},
        districtIds: <String>{'di_1'},
        clusterIds: <String>{'cl_9'},
        schoolIds: <String>{'sch_9'},
      );
      expect(school.isWithin(cluster), isFalse);
    });

    test('a school with no denormalised ancestry is not within any scope', () {
      // Containment that cannot be proven is refused, not assumed — the same
      // conservatism as [AccessScope.covers].
      const cluster = AccessScope(
        level: ScopeLevel.cluster,
        clusterIds: <String>{'cl_1'},
      );
      final bareSchool = AccessScope.singleSchool('sch_1');
      expect(bareSchool.isWithin(cluster), isFalse);
    });

    test('two scopes at the same level are within each other only if equal', () {
      const a = AccessScope(
        level: ScopeLevel.cluster,
        clusterIds: <String>{'cl_1'},
      );
      const b = AccessScope(
        level: ScopeLevel.cluster,
        clusterIds: <String>{'cl_1'},
      );
      const c = AccessScope(
        level: ScopeLevel.cluster,
        clusterIds: <String>{'cl_2'},
      );
      expect(a.isWithin(b), isTrue);
      expect(a.isWithin(c), isFalse);
    });
  });
}
