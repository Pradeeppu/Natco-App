/// An assignment's progress at its school (docs/02-data-model.md section 4
/// lists the `status` field without enumerating its values; this is this
/// app's own reasonable, linear choice: a school starts an assignment, works
/// through it, and finishes it).
library;

enum AssignmentStatus {
  assigned('ASSIGNED', 'Assigned'),
  inProgress('IN_PROGRESS', 'In progress'),
  completed('COMPLETED', 'Completed');

  const AssignmentStatus(this.wireName, this.displayName);

  final String wireName;
  final String displayName;

  static final Map<String, AssignmentStatus> _byWireName =
      <String, AssignmentStatus>{
        for (final AssignmentStatus status in AssignmentStatus.values)
          status.wireName: status,
      };

  static AssignmentStatus? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];

  bool canTransitionTo(AssignmentStatus next) => next.index == index + 1;
}
