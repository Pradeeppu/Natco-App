/// Create a user account.
///
/// The role dropdown and the scope levels both come from
/// [UserProvisioningPolicy], so the form can only offer what the repository
/// would accept. That is a usability property, not a security one — the
/// repository re-checks everything, because a form is exactly what an attacker
/// skips.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/schools/presentation/widget/scope_editor.dart';
import 'package:natco_app/features/users/domain/entity/user_draft.dart';
import 'package:natco_app/features/users/domain/service/user_provisioning_policy.dart';
import 'package:natco_app/features/users/presentation/controller/user_list_controller.dart';

final class UserFormScreen extends ConsumerStatefulWidget {
  const UserFormScreen({super.key});

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  UserRole? _role;
  AccessScope _scope = const AccessScope(level: ScopeLevel.school);
  bool _saving = false;
  Failure? _failure;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Levels this actor may hand out.
  ///
  /// Only a Super Admin's own reach is unbounded, so only a Super Admin can
  /// grant reach above school level — the same rule
  /// `UserProvisioningPolicy.checkScopeGrant` enforces, expressed here so the
  /// dropdown never offers an option that would be refused on save.
  List<ScopeLevel> _allowedLevels(AppUser? actor) {
    if (actor == null) {
      return const <ScopeLevel>[ScopeLevel.school];
    }
    if (!actor.scope.isGlobal) {
      return const <ScopeLevel>[ScopeLevel.school];
    }
    if (_role == UserRole.superAdmin) {
      return const <ScopeLevel>[ScopeLevel.global];
    }
    return const <ScopeLevel>[
      ScopeLevel.state,
      ScopeLevel.district,
      ScopeLevel.cluster,
      ScopeLevel.school,
    ];
  }

  Future<void> _save() async {
    final UserRole? role = _role;
    if (!(_formKey.currentState?.validate() ?? false) || role == null) {
      return;
    }
    final AppUser? actor = ref.read(sessionProvider).authorization.user;
    if (actor == null) {
      return;
    }

    setState(() {
      _saving = true;
      _failure = null;
    });

    final UserDraft draft = UserDraft(
      email: _email.text,
      displayName: _name.text,
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      role: role,
      scope: _scope,
    );

    final Result<AppUser> result = await ref
        .read(userRepositoryProvider)
        .createUser(draft, actor: actor);

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);

    switch (result) {
      case Success<AppUser>(:final AppUser value):
        // The list is an app-wide singleton, so it has to be told; otherwise
        // the new account is missing until something else happens to refresh.
        await ref.read(userListControllerProvider.notifier).refresh();
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${value.displayName} can now sign in.'),
          ),
        );
        Navigator.of(context).pop();
      case FailureResult<AppUser>(:final Failure failure):
        setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final SessionState session = ref.watch(sessionProvider);
    final AppUser? actor = session.authorization.user;
    final List<UserRole> assignable = UserProvisioningPolicy.assignableRolesFor(
      actor,
    );

    // Pre-select when there is only one choice: a Supervisor is always adding
    // a PST Teacher, and making them open a one-item dropdown to say so is
    // friction with no decision behind it.
    if (_role == null && assignable.length == 1) {
      _role = assignable.single;
    }

    final Failure? failure = _failure;

    return Scaffold(
      appBar: AppBar(title: const Text('Add user')),
      body: SafeArea(
        child: assignable.isEmpty
            ? FailureView(
                failure: PermissionFailure.denied(
                  action: 'create user accounts',
                  diagnostic: 'no assignable roles',
                ),
              )
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: <Widget>[
                    if (failure != null) ...<Widget>[
                      InfoBanner(
                        message: failure.userMessage,
                        icon: Icons.error_outline,
                        isWarning: true,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (String? value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Enter this person\'s name.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        helperText: 'This is how they sign in.',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (assignable.length > 1)
                      DropdownButtonFormField<UserRole>(
                        initialValue: _role,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        items: assignable
                            .map(
                              (UserRole role) => DropdownMenuItem<UserRole>(
                                value: role,
                                child: Text(role.displayName),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (UserRole? value) => setState(() {
                          _role = value;
                          // A role change can change which levels are on
                          // offer, so a scope chosen under the old role is no
                          // longer necessarily grantable.
                          _scope = const AccessScope(level: ScopeLevel.school);
                        }),
                        validator: (UserRole? value) =>
                            value == null ? 'Choose a role.' : null,
                      )
                    else
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.badge_outlined),
                        title: Text(assignable.single.displayName),
                        subtitle: const Text('The only role you can create'),
                      ),
                    const Divider(height: 32),
                    Text(
                      'What they can see',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    ScopeEditor(
                      key: ValueKey<UserRole?>(_role),
                      allowedLevels: _allowedLevels(actor),
                      showGradeSections: _role == UserRole.pstTeacher,
                      onChanged: (AccessScope scope) => _scope = scope,
                    ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_saving ? 'Creating...' : 'Create account'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  static String? _validateEmail(String? value) {
    final String email = (value ?? '').trim();
    if (email.isEmpty) {
      return 'Enter an email address.';
    }
    // Deliberately loose. A strict RFC 5322 pattern rejects addresses that
    // genuinely work, and the authoritative check is the invitation actually
    // arriving.
    final bool looksLikeEmail =
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    return looksLikeEmail ? null : 'That does not look like an email address.';
  }
}
