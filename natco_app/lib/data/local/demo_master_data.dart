/// Seeds the demo hierarchy and student roster.
///
/// The counts are exactly what requirement section 53 specifies: 1 state, 2
/// districts, 3 clusters, 5 schools, 100 students. This is the only place
/// those numbers appear — the repositories themselves know nothing about
/// "demo" and would seed any shape handed to them.
///
/// No real student data is used (requirement section 53); every name here is
/// a placeholder.
library;

import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/schools/domain/entity/geo_node.dart';
import 'package:natco_app/features/schools/domain/entity/hierarchy_level.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/students/data/repository/in_memory_students_repository.dart';
import 'package:natco_app/features/students/domain/entity/gender.dart';

const List<String> _firstNames = <String>[
  'Aarav', 'Vivaan', 'Aditya', 'Vihaan', 'Arjun', 'Sai', 'Reyansh', 'Ayaan',
  'Krishna', 'Ishaan', 'Ananya', 'Diya', 'Saanvi', 'Aadhya', 'Kiara', 'Myra',
  'Pari', 'Anika', 'Navya', 'Riya',
];

const List<String> _lastNames = <String>[
  'Kumar', 'Sharma', 'Singh', 'Reddy', 'Rao', 'Nair', 'Iyer', 'Menon',
  'Gupta', 'Verma',
];

/// Populates [schools] and [students] with the demo dataset.
///
/// Deterministic given the same [idGenerator] and [clock]: two calls with
/// fresh `SequentialIdGenerator`s produce identical data, which is what makes
/// this usable directly in widget tests, not only in the shipped demo build.
void seedDemoMasterData({
  required InMemorySchoolsRepository schools,
  required InMemoryStudentsRepository students,
  required IdGenerator idGenerator,
  required Clock clock,
}) {
  final DateTime now = clock.nowUtc();

  GeoNode makeNode(
    HierarchyLevel level,
    String name,
    String code, {
    String? parentId,
    String? stateId,
    String? districtId,
  }) => GeoNode(
    id: idGenerator.newId(),
    level: level,
    name: name,
    code: code,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    parentId: parentId,
    stateId: stateId,
    districtId: districtId,
  );

  // 1 state.
  final GeoNode state = makeNode(HierarchyLevel.state, 'Karnataka', 'KA');
  schools.seedState(state);

  // 2 districts.
  final List<GeoNode> districts = <GeoNode>[
    makeNode(
      HierarchyLevel.district,
      'Bengaluru Urban',
      'BU',
      parentId: state.id,
      stateId: state.id,
    ),
    makeNode(
      HierarchyLevel.district,
      'Mysuru',
      'MY',
      parentId: state.id,
      stateId: state.id,
    ),
  ];
  for (final GeoNode district in districts) {
    schools.seedDistrict(district);
  }

  // 3 clusters, spread across the 2 districts.
  final List<GeoNode> clusters = <GeoNode>[
    makeNode(
      HierarchyLevel.cluster,
      'Whitefield',
      'WF',
      parentId: districts[0].id,
      stateId: state.id,
      districtId: districts[0].id,
    ),
    makeNode(
      HierarchyLevel.cluster,
      'Koramangala',
      'KM',
      parentId: districts[0].id,
      stateId: state.id,
      districtId: districts[0].id,
    ),
    makeNode(
      HierarchyLevel.cluster,
      'Mysuru North',
      'MN',
      parentId: districts[1].id,
      stateId: state.id,
      districtId: districts[1].id,
    ),
  ];
  for (final GeoNode cluster in clusters) {
    schools.seedCluster(cluster);
  }

  // 5 schools, spread across the 3 clusters.
  const List<String> schoolNames = <String>[
    'NATCO Public School',
    'Green Valley School',
    'St. Xavier\'s High School',
    'Sunrise Vidyalaya',
    'Lakeview School',
  ];
  final List<int> clusterForSchool = <int>[0, 0, 1, 2, 2];
  final List<School> seededSchools = <School>[];
  for (int i = 0; i < schoolNames.length; i++) {
    final GeoNode cluster = clusters[clusterForSchool[i]];
    final School school = School(
      schoolId: idGenerator.newId(),
      schoolName: schoolNames[i],
      schoolCode: 'SCH${(i + 1).toString().padLeft(3, '0')}',
      clusterId: cluster.id,
      districtId: cluster.districtId!,
      stateId: cluster.stateId!,
      grades: const <String>['1', '2', '3', '4', '5', '6', '7', '8'],
      mediumsOfInstruction: const <String>['English', 'Regional'],
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    schools.seedSchool(school);
    seededSchools.add(school);
  }

  // 100 students, distributed across the 5 schools, grades 3-8, sections A-C.
  const List<String> grades = <String>['3', '4', '5', '6', '7', '8'];
  const List<String> sections = <String>['A', 'B', 'C'];
  // Names, grades and sections cycle and repeat across 100 students by
  // design — that is what makes the roster look like a real school's, not a
  // list of unique codes. Date of birth is what keeps every row distinct:
  // one calendar day per index, spanning a few months, so the dedupe key
  // (school + name + grade + section + dob) can never collide by
  // construction, however the other fields happen to repeat.
  final DateTime firstBirthDate = DateTime.utc(2012, 1, 1);

  for (int i = 0; i < 100; i++) {
    final School school = seededSchools[i % seededSchools.length];
    final String firstName = _firstNames[i % _firstNames.length];
    final String lastName =
        _lastNames[(i ~/ _firstNames.length) % _lastNames.length];
    final String grade = grades[i % grades.length];
    final String section = sections[i % sections.length];
    final DateTime dob = firstBirthDate.add(Duration(days: i));

    // The synchronous seed path, not the async `createStudent`: it still
    // runs the dedupe check, but fails loudly on a collision instead of
    // relying on the async interface happening to resolve synchronously
    // today (see `InMemoryStudentsRepository.seedStudent`).
    students.seedStudent(
      schoolId: school.schoolId,
      studentName: '$firstName $lastName',
      gender: i.isEven ? Gender.male : Gender.female,
      grade: grade,
      section: section,
      mediumOfInstruction: school.mediumsOfInstruction.first,
      language: 'English',
      dateOfBirth: dob,
    );
  }
}
