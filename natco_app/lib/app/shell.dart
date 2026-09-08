/// The app shell: a role-filtered navigation bar around the primary screens.
///
/// On a phone the bar holds at most five destinations, because a bar with ten
/// items on a 5-inch screen becomes unreadable; the rest move into a "More"
/// sheet. On a wider screen everything goes into a rail. Both read from the
/// same permission-filtered list (docs/05-navigation-map.md).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/navigation.dart';
import 'package:natco_app/core/services/connectivity_service.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

/// Number of destinations shown directly in the bottom bar. Beyond this, a
/// "More" destination opens the remainder in a sheet.
const int kMaxVisibleBarDestinations = 5;

/// Width at which the bar becomes a rail.
const double kRailBreakpoint = 720;

final class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final Authorization authorization = session.authorization;
    final List<NavDestination> destinations = visibleDestinations(
      authorization,
    );

    if (destinations.isEmpty) {
      // A role with no reachable destination would otherwise render an empty
      // bar. It cannot happen with the current matrix (every role holds
      // viewDashboard), but rendering the content bare is the right answer if
      // the matrix ever changes.
      return Scaffold(body: child);
    }

    final String location = GoRouterState.of(context).uri.path;
    final bool useRail = MediaQuery.sizeOf(context).width >= kRailBreakpoint;

    final Widget body = Column(
      children: <Widget>[
        const _ConnectivityBanner(),
        Expanded(child: child),
      ],
    );

    if (useRail) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: selectedDestinationIndex(destinations, location),
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (int index) =>
                  context.go(destinations[index].route),
              destinations: destinations
                  .map(
                    (NavDestination d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                  )
                  .toList(growable: false),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    final ({List<NavDestination> bar, List<NavDestination> overflow}) split =
        splitForBar(destinations, slots: kMaxVisibleBarDestinations);
    final List<NavDestination> barDestinations = split.bar;
    final List<NavDestination> overflowDestinations = split.overflow;
    final bool needsOverflow = overflowDestinations.isNotEmpty;

    // When the current location lives in the overflow, no bar item is the
    // active one; highlighting "More" is the honest answer.
    final int barSelected = selectedDestinationIndex(barDestinations, location);
    final bool activeIsInBar = barDestinations.any(
      (NavDestination d) =>
          location == d.route || location.startsWith('${d.route}/'),
    );

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: activeIsInBar || !needsOverflow
            ? barSelected
            : barDestinations.length,
        onDestinationSelected: (int index) {
          if (needsOverflow && index == barDestinations.length) {
            _showOverflow(context, overflowDestinations);
            return;
          }
          context.go(barDestinations[index].route);
        },
        destinations: <Widget>[
          ...barDestinations.map(
            (NavDestination d) => NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
          ),
          if (needsOverflow)
            const NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'More',
            ),
        ],
      ),
    );
  }

  void _showOverflow(BuildContext context, List<NavDestination> destinations) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: destinations
              .map(
                (NavDestination d) => ListTile(
                  leading: Icon(d.icon),
                  title: Text(d.label),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go(d.route);
                  },
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

/// A persistent strip that appears only when the connection cannot carry work.
///
/// Requirement section 23: the app works offline, so being offline is a normal
/// state and must be *stated* rather than treated as an error.
final class _ConnectivityBanner extends ConsumerWidget {
  const _ConnectivityBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ConnectionStatus> status = ref.watch(
      connectionStatusProvider,
    );
    final ConnectionStatus? value = status.value;
    if (value == null || value.isReachable) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value == ConnectionStatus.offline
                    ? 'Offline. Your work is saved on this device.'
                    : 'Connected, but the server cannot be reached. Your '
                          'work is saved on this device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
