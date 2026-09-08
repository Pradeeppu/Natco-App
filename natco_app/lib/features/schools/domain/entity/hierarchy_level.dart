/// The four levels of the geographic master-data hierarchy.
///
/// Kept separate from `ScopeLevel` (`features/auth/domain/entity/access_scope.dart`):
/// that enum also has `GLOBAL`, which describes a user's *reach*, not a node's
/// *kind*. A hierarchy node is always exactly one of these four; a scope can
/// additionally be unrestricted.
library;

enum HierarchyLevel {
  state('STATE', 'State'),
  district('DISTRICT', 'District'),
  cluster('CLUSTER', 'Cluster'),
  school('SCHOOL', 'School');

  const HierarchyLevel(this.wireName, this.displayName);

  final String wireName;
  final String displayName;
}
