/// Create a new school (Super Admin only, `manageSchools`).
///
/// State, district and cluster are chosen from dropdowns backed by master
/// data, never typed (requirement §10) — a plain dropdown is enough at
/// these levels because, unlike Schools or Students, they are expected to
/// stay small (docs/03-firestore-schema.md "Pagination").
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/entity/state_entity.dart';
import 'package:natco_app/features/schools/presentation/controller/hierarchy_providers.dart';

const List<String> _kGrades = <String>[
  '1', '2', '3', '4', '5', '6', '7', '8', '9', '10',
];
const List<String> _kMediums = <String>['English', 'Telugu', 'Hindi', 'Urdu'];

final class SchoolFormScreen extends ConsumerStatefulWidget {
  const SchoolFormScreen({super.key});

  @override
  ConsumerState<SchoolFormScreen> createState() => _SchoolFormScreenState();
}

class _SchoolFormScreenState extends ConsumerState<SchoolFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _pincodeController = TextEditingController();
  final Set<String> _grades = <String>{};
  final Set<String> _mediums = <String>{};

  String? _stateId;
  String? _districtId;
  String? _clusterId;
  bool _submitting = false;
  Failure? _failure;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _addressController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_clusterId == null) {
      setState(
        () => _failure = const ValidationFailure(
          userMessage: 'Choose a state, district and cluster first.',
        ),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _failure = null;
    });
    final SessionState session = ref.read(sessionProvider);
    final DateTime now = DateTime.now().toUtc();
    const IdGenerator idGenerator = UuidIdGenerator();
    final School school = School(
      schoolId: idGenerator.newId(),
      schoolName: _nameController.text.trim(),
      schoolCode: _codeController.text.trim(),
      clusterId: _clusterId!,
      districtId: _districtId!,
      stateId: _stateId!,
      address: _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim(),
      pincode: _pincodeController.text.trim().isEmpty
          ? null
          : _pincodeController.text.trim(),
      grades: _grades.toList()..sort(),
      mediumsOfInstruction: _mediums.toList()..sort(),
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    final Result<School> result = await ref
        .read(schoolHierarchyRepositoryProvider)
        .createSchool(
          school,
          actorUserId: session.session?.user.userId ?? 'unknown',
          actorRole: session.session?.user.role.wireName ?? 'UNKNOWN',
        );
    if (!mounted) {
      return;
    }
    if (result.isFailure) {
      setState(() {
        _submitting = false;
        _failure = result.failureOrNull;
      });
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add school')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_failure != null) ...<Widget>[
                  Text(
                    _failure!.userMessage,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _stateDropdown(),
                const SizedBox(height: 12),
                if (_stateId != null) _districtDropdown(),
                if (_districtId != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _clusterDropdown(),
                ],
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(labelText: 'School name'),
                  validator: (String? v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a school name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _codeController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(labelText: 'School code'),
                  validator: (String? v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a school code' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(labelText: 'Address (optional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pincodeController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(labelText: 'Pincode (optional)'),
                ),
                const SizedBox(height: 20),
                Text('Grades taught', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kGrades
                      .map(
                        (String g) => FilterChip(
                          label: Text('Grade $g'),
                          selected: _grades.contains(g),
                          onSelected: _submitting
                              ? null
                              : (bool selected) => setState(() {
                                  selected ? _grades.add(g) : _grades.remove(g);
                                }),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 20),
                Text('Mediums of instruction', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kMediums
                      .map(
                        (String m) => FilterChip(
                          label: Text(m),
                          selected: _mediums.contains(m),
                          onSelected: _submitting
                              ? null
                              : (bool selected) => setState(() {
                                  selected ? _mediums.add(m) : _mediums.remove(m);
                                }),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Create school'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Renders one cascade level, unwrapping both the async state and the
  /// [Result] inside it (see `hierarchy_providers.dart` for why failures
  /// arrive as data rather than as a thrown error).
  Widget _levelDropdown<T>({
    required AsyncValue<Result<List<T>>> value,
    required String label,
    required String? selected,
    required String Function(T item) idOf,
    required String Function(T item) nameOf,
    required ValueChanged<String?> onChanged,
  }) => value.when(
    loading: () => const LinearProgressIndicator(),
    error: (Object e, StackTrace _) =>
        Text('Could not load $label: ${asFailure(e).userMessage}'),
    data: (Result<List<T>> result) => result.fold(
      onFailure: (Failure failure) =>
          Text('Could not load $label: ${failure.userMessage}'),
      onSuccess: (List<T> items) => DropdownButtonFormField<String>(
        initialValue: selected,
        decoration: InputDecoration(labelText: label),
        items: items
            .map(
              (T item) => DropdownMenuItem<String>(
                value: idOf(item),
                child: Text(nameOf(item)),
              ),
            )
            .toList(growable: false),
        onChanged: _submitting ? null : onChanged,
      ),
    ),
  );

  Widget _stateDropdown() => _levelDropdown<StateEntity>(
    value: ref.watch(statesProvider),
    label: 'State',
    selected: _stateId,
    idOf: (StateEntity s) => s.stateId,
    nameOf: (StateEntity s) => s.stateName,
    onChanged: (String? value) => setState(() {
      _stateId = value;
      _districtId = null;
      _clusterId = null;
    }),
  );

  Widget _districtDropdown() => _levelDropdown<District>(
    value: ref.watch(districtsProvider(_stateId)),
    label: 'District',
    selected: _districtId,
    idOf: (District d) => d.districtId,
    nameOf: (District d) => d.districtName,
    onChanged: (String? value) => setState(() {
      _districtId = value;
      _clusterId = null;
    }),
  );

  Widget _clusterDropdown() => _levelDropdown<Cluster>(
    value: ref.watch(clustersProvider(_districtId)),
    label: 'Cluster',
    selected: _clusterId,
    idOf: (Cluster c) => c.clusterId,
    nameOf: (Cluster c) => c.clusterName,
    onChanged: (String? value) => setState(() => _clusterId = value),
  );
}
