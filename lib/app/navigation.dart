/// The navigation destinations of the app shell.
///
/// One list, filtered by permission. Requirement section 36 asks that only
/// screens allowed for the user's role are shown; doing that from a single
/// declarative list is what keeps a teacher's bar at five items while a Super
/// Admin's has ten, with no per-role widget tree.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';

/// A primary destination.
final class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.route,
    required this.permissions,
    required this.barPriority,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;

  /// Any one of these permissions makes the destination visible.
  ///
  /// A set rather than a single permission because some destinations have
  /// several entry points — *OMR* is reachable by someone who captures sheets
  /// and by someone who only reviews their quality.
  final Set<Permission> permissions;

  /// Which destinations keep a slot in the bottom bar when there are more
  /// permitted destinations than slots. Lower stays.
  ///
  /// This is not the same as display order. Taking the first N in declaration
  /// order would bury *OMR* — a teacher's whole job — behind "More" while
  /// *Schools* and *Students*, which they open occasionally, held bar slots.
  /// The bar carries what the role does; the declaration order still governs
  /// how the surviving items are laid out, so the bar does not reshuffle
  /// between roles.
  final int barPriority;
}

/// The full destination list, in the order requirement section 36 gives.
const List<NavDestination> kNavDestinations = <NavDestination>[
  NavDestination(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    route: RoutePaths.dashboard,
    permissions: <Permission>{Permission.viewDashboard},
    barPriority: 0,
  ),
  NavDestination(
    label: 'Schools',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree,
    route: RoutePaths.schools,
    permissions: <Permission>{Permission.viewSchools},
    barPriority: 7,
  ),
  NavDestination(
    label: 'Students',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
    route: RoutePaths.students,
    permissions: <Permission>{Permission.viewStudents},
    barPriority: 6,
  ),
  NavDestination(
    label: 'Users',
    icon: Icons.badge_outlined,
    selectedIcon: Icons.badge,
    route: RoutePaths.users,
    permissions: <Permission>{Permission.viewUsers},
    // Onboarding staff is occasional work — real, but not what anyone opens
    // the app to do — so it yields its bar slot to OMR, Validation and Sync.
    barPriority: 10,
  ),
  NavDestination(
    label: 'Assessments',
    icon: Icons.assignment_outlined,
    selectedIcon: Icons.assignment,
    route: RoutePaths.assessments,
    permissions: <Permission>{
      Permission.viewAssessments,
      Permission.manageAssessments,
    },
    barPriority: 5,
  ),
  NavDestination(
    label: 'OMR',
    icon: Icons.document_scanner_outlined,
    selectedIcon: Icons.document_scanner,
    route: RoutePaths.omrCapture,
    permissions: <Permission>{Permission.captureOmr},
    barPriority: 1,
  ),
  NavDestination(
    label: 'Validation',
    icon: Icons.rule_folder_outlined,
    selectedIcon: Icons.rule_folder,
    route: RoutePaths.omrValidationQueue,
    permissions: <Permission>{Permission.validateOmr},
    barPriority: 2,
  ),
  NavDestination(
    label: 'Results',
    icon: Icons.grading_outlined,
    selectedIcon: Icons.grading,
    route: RoutePaths.results,
    permissions: <Permission>{Permission.viewResults},
    barPriority: 4,
  ),
  NavDestination(
    label: 'Analytics',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
    route: RoutePaths.analytics,
    permissions: <Permission>{Permission.viewAnalytics},
    barPriority: 8,
  ),
  NavDestination(
    label: 'Reports',
    icon: Icons.download_outlined,
    selectedIcon: Icons.download,
    route: RoutePaths.reports,
    permissions: <Permission>{Permission.exportReports},
    barPriority: 9,
  ),
  NavDestination(
    label: 'Sync',
    icon: Icons.sync_outlined,
    selectedIcon: Icons.sync,
    route: RoutePaths.sync,
    permissions: <Permission>{Permission.syncSubmissions},
    barPriority: 3,
  ),
];

/// The destinations [authorization] may reach.
///
/// Uses the same [Authorization] the route guard uses, so a visible
/// destination can never lead to the unauthorized screen.
List<NavDestination> visibleDestinations(Authorization authorization) =>
    kNavDestinations
        .where(
          (NavDestination destination) =>
              authorization.canAny(destination.permissions),
        )
        .toList(growable: false);

/// Splits [destinations] into the bar's slots and the overflow sheet.
///
/// Selection is by [NavDestination.barPriority]; layout stays in declaration
/// order.
({List<NavDestination> bar, List<NavDestination> overflow}) splitForBar(
  List<NavDestination> destinations, {
  required int slots,
}) {
  if (destinations.length <= slots) {
    return (bar: destinations, overflow: const <NavDestination>[]);
  }
  // One slot is spent on the "More" affordance itself.
  final int keep = slots - 1;
  final List<NavDestination> byPriority = List<NavDestination>.of(destinations)
    ..sort(
      (NavDestination a, NavDestination b) =>
          a.barPriority.compareTo(b.barPriority),
    );
  final Set<NavDestination> kept = byPriority.take(keep).toSet();
  return (
    bar: destinations.where(kept.contains).toList(growable: false),
    overflow: destinations
        .where((NavDestination d) => !kept.contains(d))
        .toList(growable: false),
  );
}

/// The index of the destination matching [location], or 0 when none does.
///
/// Matched on the path prefix so that `/schools/abc` still highlights
/// *Schools*. `/dashboard` is matched exactly, since every path would
/// otherwise be a prefix match against `/`.
int selectedDestinationIndex(
  List<NavDestination> destinations,
  String location,
) {
  for (int index = 0; index < destinations.length; index++) {
    final String route = destinations[index].route;
    if (location == route || location.startsWith('$route/')) {
      return index;
    }
  }
  return 0;
}
