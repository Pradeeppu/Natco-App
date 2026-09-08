/// The root widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/router.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/services/connectivity_service.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

final class NatcoApp extends ConsumerStatefulWidget {
  const NatcoApp({super.key});

  @override
  ConsumerState<NatcoApp> createState() => _NatcoAppState();
}

class _NatcoAppState extends ConsumerState<NatcoApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Revalidate the session whenever a usable connection appears, so a role
    // change or a deactivation that happened while the device was offline
    // takes effect rather than waiting for the cache to expire.
    ref.listenManual<AsyncValue<ConnectionStatus>>(connectionStatusProvider, (
      AsyncValue<ConnectionStatus>? previous,
      AsyncValue<ConnectionStatus> next,
    ) {
      final bool wasReachable = previous?.value?.isReachable ?? false;
      final bool isReachable = next.value?.isReachable ?? false;
      if (!wasReachable && isReachable) {
        ref.read(sessionProvider.notifier).revalidate();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the foreground is the other moment worth re-checking: the
    // app may have been backgrounded for days.
    if (state == AppLifecycleState.resumed) {
      final SessionState session = ref.read(sessionProvider);
      if (session.isAuthenticated) {
        ref.read(sessionProvider.notifier).revalidate();
      }
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    final GoRouter router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'NATCO Assessment',
      debugShowCheckedModeBanner: false,
      theme: NatcoTheme.light(),
      darkTheme: NatcoTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (BuildContext context, Widget? child) {
        // Cap text scaling rather than ignore it: accessibility settings must
        // work (requirement section 56), but an unbounded scale factor breaks
        // the capture screen's camera overlay, and a broken capture screen is
        // an accessibility failure of its own.
        final double scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale.clamp(0.85, 1.6))),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
