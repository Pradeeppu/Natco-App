/// Sign-in.
///
/// Field-oriented choices worth naming:
///
/// * Validation is inline and immediate, so a mistyped address does not cost a
///   round trip on a weak link.
/// * The submit button owns its own loading state; the session does not change
///   until sign-in succeeds, so the router never reacts to a half-finished
///   attempt.
/// * Errors are [Failure.userMessage] only. No exception name, no Firebase
///   code (requirement section 40).
/// * In demo mode the available accounts are listed and fill the form on tap,
///   because a build with no backend is useless if nobody can get in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/app_config.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/presentation/controller/session_controller.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

final class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  Failure? _failure;

  /// Set when the user arrives here because a cached session expired or an
  /// account was deactivated, so the screen can explain why.
  Failure? _sessionFailure;

  @override
  void initState() {
    super.initState();
    final SessionState session = ref.read(sessionProvider);
    if (session is SessionUnauthenticated) {
      _sessionFailure = session.failure;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    final SessionController controller = ref.read(sessionProvider.notifier);
    final Failure? failure = await controller.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _isSubmitting = false;
      _failure = failure;
      // Once a real attempt has been made, the "why you are back here"
      // message has been superseded by a concrete result.
      _sessionFailure = null;
    });
    // On success the router redirects; nothing to do here.
  }

  Future<void> _resetPassword() async {
    final String email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(
        () => _failure = const ValidationFailure(
          userMessage:
              'Enter your email address first, then tap Forgot password.',
        ),
      );
      return;
    }
    final SessionController controller = ref.read(sessionProvider.notifier);
    final Failure? failure = await controller.requestPasswordReset(email);
    if (!mounted) {
      return;
    }
    if (failure != null) {
      setState(() => _failure = failure);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'If that address has an account, a reset link is on its way.',
        ),
      ),
    );
  }

  String? _validateEmail(String? value) {
    final String email = (value ?? '').trim();
    if (email.isEmpty) {
      return 'Enter your email address';
    }
    // Deliberately permissive: the authority on whether an address exists is
    // the server, and a strict client-side pattern only rejects valid
    // addresses.
    if (!email.contains('@') || email.startsWith('@') || email.endsWith('@')) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').isEmpty) {
      return 'Enter your password';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppConfig config = ref.watch(appConfigProvider);
    final List<DemoAccount> demoAccounts = ref.watch(demoAccountsProvider);
    final Failure? message = _failure ?? _sessionFailure;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Icon(
                      Icons.fact_check_outlined,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'NATCO Assessment',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to continue',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (message != null) ...<Widget>[
                      _ErrorPanel(failure: message),
                      const SizedBox(height: 20),
                    ],
                    TextFormField(
                      controller: _emailController,
                      enabled: !_isSubmitting,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.username],
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_isSubmitting,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const <String>[AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                      validator: _validatePassword,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isSubmitting ? null : _resetPassword,
                      child: const Text('Forgot password?'),
                    ),
                    if (demoAccounts.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 24),
                      _DemoAccountPicker(
                        accounts: demoAccounts,
                        enabled: !_isSubmitting,
                        onSelected: (DemoAccount account) {
                          _emailController.text = account.user.email;
                          _passwordController.text = account.password;
                          setState(() => _failure = null);
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Environment: ${config.environment.name}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.error_outline,
            size: 20,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              failure.userMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lists the demo accounts in builds with no backend.
final class _DemoAccountPicker extends StatelessWidget {
  const _DemoAccountPicker({
    required this.accounts,
    required this.enabled,
    required this.onSelected,
  });

  final List<DemoAccount> accounts;
  final bool enabled;
  final ValueChanged<DemoAccount> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.science_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Demo accounts', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'This build has no backend and holds no real student data. '
              'Tap a role to fill the form.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: accounts
                  .map(
                    (DemoAccount account) => ActionChip(
                      label: Text(account.user.role.displayName),
                      onPressed: enabled ? () => onSelected(account) : null,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}
