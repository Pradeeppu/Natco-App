/// Seed data for demo mode: 1 state, 2 districts, 3 clusters, 5 schools, 100
/// students (requirement §53). Holds no real student data.
///
/// The ids here are the single source of truth for the demo hierarchy, and
/// `buildDemoAccounts()`
/// (`lib/features/auth/data/service/in_memory_auth_service.dart`) imports
/// them for its scopes, so a demo Supervisor's cluster scope and the demo
/// school data can never drift apart.
library;

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
  static const String clusterId1 = 'cl_demo_1';
  static const String clusterId2 = 'cl_demo_2';
  static const String clusterId3 = 'cl_demo_3';
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
    stateName: 'Demo State',
    stateCode: 'DS',
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
];

List<District> demoDistricts() => <District>[
  District(
    districtId: DemoHierarchyIds.districtId1,
    districtName: 'North District',
    districtCode: 'DS-N',
    stateId: DemoHierarchyIds.stateId,
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
  District(
    districtId: DemoHierarchyIds.districtId2,
    districtName: 'South District',
    districtCode: 'DS-S',
    stateId: DemoHierarchyIds.stateId,
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
];

List<Cluster> demoClusters() => <Cluster>[
  Cluster(
    clusterId: DemoHierarchyIds.clusterId1,
    clusterName: 'Riverside Cluster',
    clusterCode: 'DS-N-1',
    districtId: DemoHierarchyIds.districtId1,
    stateId: DemoHierarchyIds.stateId,
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
  Cluster(
    clusterId: DemoHierarchyIds.clusterId2,
    clusterName: 'Hilltop Cluster',
    clusterCode: 'DS-N-2',
    districtId: DemoHierarchyIds.districtId1,
    stateId: DemoHierarchyIds.stateId,
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
  Cluster(
    clusterId: DemoHierarchyIds.clusterId3,
    clusterName: 'Lakeside Cluster',
    clusterCode: 'DS-S-1',
    districtId: DemoHierarchyIds.districtId2,
    stateId: DemoHierarchyIds.stateId,
    isActive: true,
    createdAt: _seedTimestamp,
    updatedAt: _seedTimestamp,
  ),
];

List<School> demoSchools() => <School>[
  _school(
    DemoHierarchyIds.schoolId1,
    'Riverside Government Primary School',
    DemoHierarchyIds.clusterId1,
    DemoHierarchyIds.districtId1,
  ),
  _school(
    DemoHierarchyIds.schoolId2,
    'Riverside Upper Primary School',
    DemoHierarchyIds.clusterId1,
    DemoHierarchyIds.districtId1,
  ),
  _school(
    DemoHierarchyIds.schoolId3,
    'Hilltop Government Primary School',
    DemoHierarchyIds.clusterId2,
    DemoHierarchyIds.districtId1,
  ),
  _school(
    DemoHierarchyIds.schoolId4,
    'Hilltop Upper Primary School',
    DemoHierarchyIds.clusterId2,
    DemoHierarchyIds.districtId1,
  ),
  _school(
    DemoHierarchyIds.schoolId5,
    'Lakeside Government Primary School',
    DemoHierarchyIds.clusterId3,
    DemoHierarchyIds.districtId2,
  ),
];

School _school(
  String schoolId,
  String schoolName,
  String clusterId,
  String districtId,
) => School(
  schoolId: schoolId,
  schoolName: schoolName,
  schoolCode: schoolId.toUpperCase(),
  clusterId: clusterId,
  districtId: districtId,
  stateId: DemoHierarchyIds.stateId,
  grades: const <String>['3', '4', '5', '6', '7', '8'],
  mediumsOfInstruction: const <String>['English', 'Telugu'],
  isActive: true,
  createdAt: _seedTimestamp,
  updatedAt: _seedTimestamp,
);

const List<String> _firstNames = <String>[
  'Aarav', 'Vivaan', 'Aditya', 'Ishaan', 'Kabir', 'Arjun', 'Reyansh', 'Ayaan',
  'Krishna', 'Ananya', 'Diya', 'Saanvi', 'Aadhya', 'Kiara', 'Myra', 'Anika',
  'Riya', 'Sara', 'Pari', 'Zara',
];

const List<String> _lastNames = <String>[
  'Sharma', 'Verma', 'Reddy', 'Iyer', 'Nair', 'Rao', 'Gupta', 'Das', 'Menon',
  'Pillai',
];

const List<String> _grades = <String>['3', '4', '5', '6', '7'];
const List<String> _sections = <String>['A', 'B'];

/// 100 students across the 5 demo schools (20 each), spread over grades 3-7
/// and sections A/B, including Grade 5 Section A at [DemoHierarchyIds.schoolId1]
/// — the demo teacher account's assigned grade-section.
List<Student> demoStudents() {
  final List<School> schools = demoSchools();
  final List<Student> students = <Student>[];
  int sequence = 0;
  for (final School school in schools) {
    for (int i = 0; i < 20; i++) {
      final String firstName = _firstNames[sequence % _firstNames.length];
      final String lastName = _lastNames[sequence % _lastNames.length];
      final String grade = _grades[i % _grades.length];
      final String section = _sections[(i ~/ _grades.length) % _sections.length];
      final DateTime dateOfBirth = DateTime.utc(
        2026 - (8 + int.parse(grade)),
        1 + (sequence % 12),
        1 + (sequence % 27),
      );
      students.add(
        Student(
          studentId: 'stu_demo_${(sequence + 1).toString().padLeft(3, '0')}',
          studentName: '$firstName $lastName',
          gender: sequence.isEven ? Gender.male : Gender.female,
          dateOfBirth: dateOfBirth,
          grade: grade,
          section: section,
          mediumOfInstruction: school.mediumsOfInstruction.first,
          language: school.mediumsOfInstruction.first,
          schoolId: school.schoolId,
          clusterId: school.clusterId,
          districtId: school.districtId,
          stateId: school.stateId,
          activeStatus: true,
          dedupeKey:
              'demo-seed-${school.schoolId}-$firstName-$lastName-$grade-$section-$sequence',
          createdAt: _seedTimestamp,
          updatedAt: _seedTimestamp,
        ),
      );
      sequence++;
    }
  }
  return students;
}
