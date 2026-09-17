/// Seed data for demo mode: 1 state, 3 districts, 4 clusters, 59 schools, 624
/// students (requirement §53), built from NorthSouth Foundation's real active
/// -students roster so the demo reads as a real deployment rather than a
/// synthetic sample.
///
/// Real district and school names are used — see
/// `demo_real_roster_data.dart` for the source table. Individual students are
/// **not** real: every student's name and date of birth is synthetically
/// generated from the roster's real (district, school, grade, gender) rows,
/// with the real names, dates of birth and guardian names deliberately
/// discarded during import. This app ships publicly and those fields would
/// identify real children.
///
/// The ids here are the single source of truth for the demo hierarchy, and
/// `buildDemoAccounts()`
/// (`lib/features/auth/data/service/in_memory_auth_service.dart`) imports
/// them for its scopes, so a demo Supervisor's cluster scope and the demo
/// school data can never drift apart. `DemoHierarchyIds`' string *values* are
/// also relied on directly by a few tests
/// (e.g. `test/features/omr_processing/omr_image_writer_test.dart`), so they
/// are never reassigned — only the district/cluster/school *names* attached
/// to them changed when this data was localised to real geography.
library;

import 'package:natco_app/features/schools/data/service/demo_real_roster_data.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/entity/state_entity.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';

/// State/district/cluster/school ids shared with `buildDemoAccounts()`.
abstract final class DemoHierarchyIds {
  static const String stateId = 'st_demo';
  static const String districtId1 = 'di_demo_1';
  static const String districtId2 = 'di_demo_2';
  static const String districtId3 = 'di_demo_3';
  static const String clusterId1 = 'cl_demo_1';
  static const String clusterId2 = 'cl_demo_2';
  static const String clusterId3 = 'cl_demo_3';
  static const String clusterId4 = 'cl_demo_4';
  static const String schoolId1 = 'sch_demo_1';
  static const String schoolId2 = 'sch_demo_2';
  static const String schoolId3 = 'sch_demo_3';
  static const String schoolId4 = 'sch_demo_4';
  static const String schoolId5 = 'sch_demo_5';
}

final DateTime _seedTimestamp = DateTime.utc(2026, 1, 1);

List<StateEntity> demoStates() => <StateEntity>[
  StateEntity(
    stateId: DemoHierarchyIds.stateId,
    stateName: 'Telangana',
    stateCode: 'TG',
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
];

List<District> demoDistricts() => <District>[
  District(
    districtId: DemoHierarchyIds.districtId1,
    districtName: 'Hyderabad',
    districtCode: 'HYD',
    stateId: DemoHierarchyIds.stateId,
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
  District(
    districtId: DemoHierarchyIds.districtId2,
    districtName: 'Rangareddy',
    districtCode: 'RR',
    stateId: DemoHierarchyIds.stateId,
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
  District(
    districtId: DemoHierarchyIds.districtId3,
    districtName: 'Nalgonda',
    districtCode: 'NLG',
    stateId: DemoHierarchyIds.stateId,
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
];

List<Cluster> demoClusters() => <Cluster>[
  Cluster(
    clusterId: DemoHierarchyIds.clusterId1,
    clusterName: 'Hyderabad Cluster 1',
    clusterCode: 'HYD-1',
    districtId: DemoHierarchyIds.districtId1,
    stateId: DemoHierarchyIds.stateId,
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
  Cluster(
    clusterId: DemoHierarchyIds.clusterId2,
    clusterName: 'Hyderabad Cluster 2',
    clusterCode: 'HYD-2',
    districtId: DemoHierarchyIds.districtId1,
    stateId: DemoHierarchyIds.stateId,
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
  Cluster(
    clusterId: DemoHierarchyIds.clusterId3,
    clusterName: 'Rangareddy Cluster',
    clusterCode: 'RR-1',
    districtId: DemoHierarchyIds.districtId2,
    stateId: DemoHierarchyIds.stateId,
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
  Cluster(
    clusterId: DemoHierarchyIds.clusterId4,
    clusterName: 'Nalgonda Cluster',
    clusterCode: 'NLG-1',
    districtId: DemoHierarchyIds.districtId3,
    stateId: DemoHierarchyIds.stateId,
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
];

/// Every real school's grades, derived once from [realStudentRows] rather
/// than guessed — a school only claims to teach a grade it actually has
/// students in.
Map<String, List<String>> _gradesBySchool() {
  final Map<String, Set<int>> grades = <String, Set<int>>{};
  for (final (String schoolId, int grade, String _) in realStudentRows) {
    (grades[schoolId] ??= <int>{}).add(grade);
  }
  return grades.map(
    (String schoolId, Set<int> gradeSet) => MapEntry(
      schoolId,
      (gradeSet.toList()..sort()).map((int g) => g.toString()).toList(growable: false),
    ),
  );
}

List<School> demoSchools() {
  final Map<String, List<String>> gradesBySchool = _gradesBySchool();
  final List<School> schools = <School>[];
  for (final (
    String schoolId,
    String schoolName,
    String districtId,
    String clusterId,
  ) in realSchoolRecords) {
    schools.add(
      School(
        schoolId: schoolId,
        schoolName: schoolName,
        schoolCode: schoolId.toUpperCase(),
        clusterId: clusterId,
        districtId: districtId,
        stateId: DemoHierarchyIds.stateId,
        grades: gradesBySchool[schoolId] ?? const <String>['3', '4', '5'],
        mediumsOfInstruction: const <String>['English', 'Telugu'],
        isActive: true,
        createdAt: _seedTimestamp,
        updatedAt: _seedTimestamp,
      ),
    );
  }
  return schools;
}

const List<String> _firstNames = <String>[
  'Aarav', 'Vivaan', 'Aditya', 'Ishaan', 'Kabir',
  'Arjun', 'Reyansh', 'Ayaan', 'Krishna', 'Rohan',
  'Sai', 'Karthik', 'Naveen', 'Prasad', 'Rahul',
  'Ananya', 'Diya', 'Saanvi', 'Aadhya', 'Kiara',
  'Myra', 'Anika', 'Riya', 'Sara', 'Pari',
  'Zara', 'Lakshmi', 'Meena', 'Priya', 'Divya',
];

const List<String> _lastNames = <String>[
  'Sharma', 'Verma', 'Reddy', 'Iyer', 'Nair',
  'Rao', 'Gupta', 'Das', 'Menon', 'Pillai',
  'Naidu', 'Rathod', 'Shaik', 'Begum', 'Goud',
];

/// 624 students across the 59 real schools, one per row of
/// [realStudentRows] — the same district/school/grade/gender distribution
/// NorthSouth Foundation's real roster has, with a synthetic name and date
/// of birth standing in for each real child's actual details.
List<Student> demoStudents() {
  final Map<String, School> schoolsById = <String, School>{
    for (final School school in demoSchools()) school.schoolId: school,
  };
  final Map<String, int> sectionCounterByKey = <String, int>{};
  const List<String> sections = <String>['A', 'B'];

  final List<Student> students = <Student>[];
  int sequence = 0;
  for (final (String schoolId, int grade, String genderCode) in realStudentRows) {
    final School school = schoolsById[schoolId]!;
    final String sectionKey = '$schoolId-$grade';
    final int sectionIndex = sectionCounterByKey.update(
      sectionKey,
      (int n) => n + 1,
      ifAbsent: () => 0,
    );
    final String firstName = _firstNames[sequence % _firstNames.length];
    final String lastName = _lastNames[sequence % _lastNames.length];
    final DateTime dateOfBirth = DateTime.utc(
      2026 - (8 + grade),
      1 + (sequence % 12),
      1 + (sequence % 27),
    );
    students.add(
      Student(
        studentId: 'stu_demo_${(sequence + 1).toString().padLeft(3, '0')}',
        studentName: '$firstName $lastName',
        gender: genderCode == 'M' ? Gender.male : Gender.female,
        dateOfBirth: dateOfBirth,
        grade: grade.toString(),
        section: sections[sectionIndex % sections.length],
        mediumOfInstruction: school.mediumsOfInstruction.first,
        language: school.mediumsOfInstruction.first,
        schoolId: school.schoolId,
        clusterId: school.clusterId,
        districtId: school.districtId,
        stateId: school.stateId,
        activeStatus: true,
        dedupeKey: 'demo-seed-${school.schoolId}-$grade-$sectionIndex-$sequence',
        createdAt: _seedTimestamp,
        updatedAt: _seedTimestamp,
      ),
    );
    sequence++;
  }
  return students;
}
