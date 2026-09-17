/// Shown while the session is being restored.
///
/// It exists so that a signed-in user opening the app never sees the login
/// screen flash past. The router holds this screen for exactly as long as
/// [SessionRestoring] is the state, and restoration is bounded — an offline
/// restore reads local storage only.
library;

import 'package:flutter/material.dart';

final class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Image.asset(
                'assets/logo/nsf_icon.png',
                height: 80,
                width: 80,
              ),
              const SizedBox(height: 20),
              Text('NCP Assessments', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 40),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              Text(
                'Restoring your session',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
