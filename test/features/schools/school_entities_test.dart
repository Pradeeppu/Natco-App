/// Round-trip and equality tests for the hierarchy entities.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/entity/state_entity.dart';

void main() {
  final DateTime t0 = DateTime.utc(2026, 1, 1);

  group('StateEntity', () {
    test('round-trips through JSON', () {
      final StateEntity original = StateEntity(
        stateId: 'st1',
        stateName: 'Telangana',
        stateCode: 'TG',
        isActive: true,
        createdAt: t0,
        updatedAt: t0,
      );
      final StateEntity? decoded = StateEntity.tryFromJson(original.toJson());
      expect(decoded, original);
    });

    test('rejects a document missing required fields', () {
      expect(StateEntity.tryFromJson(<String, Object?>{}), isNull);
    });
  });

  group('District', () {
    test('round-trips and carries state ancestry', () {
      final District original = District(
        districtId: 'di1',
        districtName: 'Hyderabad',
        districtCode: 'HYD',
        stateId: 'st1',
        isActive: true,
        createdAt: t0,
        updatedAt: t0,
      );
      final District? decoded = District.tryFromJson(original.toJson());
      expect(decoded, original);
      expect(decoded!.stateId, 'st1');
    });
  });

  group('Cluster', () {
    test('round-trips and carries district+state ancestry', () {
      final Cluster original = Cluster(
        clusterId: 'cl1',
        clusterName: 'Central',
        clusterCode: 'CTR',
        districtId: 'di1',
        stateId: 'st1',
        isActive: true,
        createdAt: t0,
        updatedAt: t0,
      );
      final Cluster? decoded = Cluster.tryFromJson(original.toJson());
      expect(decoded, original);
    });
  });

  group('School', () {
    final School original = School(
      schoolId: 'sch1',
      schoolName: 'Riverside Primary',
      schoolCode: 'SCH1',
      clusterId: 'cl1',
      districtId: 'di1',
      stateId: 'st1',
      address: '12 River Road',
      pincode: '500001',
      grades: const <String>['3', '4', '5'],
      mediumsOfInstruction: const <String>['English', 'Telugu'],
      isActive: true,
      createdAt: t0,
      updatedAt: t0,
    );

    test('round-trips including lists and optional fields', () {
      final School? decoded = School.tryFromJson(original.toJson());
      expect(decoded, original);
      expect(decoded!.grades, <String>['3', '4', '5']);
    });

    test('decodes a document with no address/pincode', () {
      final Map<String, Object?> json = original.toJson()
        ..remove('address')
        ..remove('pincode');
      final School? decoded = School.tryFromJson(json);
      expect(decoded!.address, isNull);
      expect(decoded.pincode, isNull);
    });

    test('copyWith replaces only the given fields', () {
      final School updated = original.copyWith(schoolName: 'Renamed School');
      expect(updated.schoolName, 'Renamed School');
      expect(updated.schoolCode, original.schoolCode);
      expect(updated.schoolId, original.schoolId);
    });
  });
}
