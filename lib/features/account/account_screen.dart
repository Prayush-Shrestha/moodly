import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/network/api_client.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_header.dart';

/// Optional account management: sign in, register, profile, password reset
/// and account deletion. Everything in Moodly works without an account —
/// signing in only enables AI reflection and optional cloud sync.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => AccountScreenState();
}

class AccountScreenState extends State<AccountScreen> {
  late final AuthService _auth;

  @override
  void initState() {
    super.initState();
    _auth = AppServices.of(context).authService;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _auth,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Account')),
          body: SafeArea(
            child: _auth.isSignedIn
                ? const _ProfileView()
                : const _SignInView(),
          ),
        );
      },
    );
  }
}

// --- signed-out: sign in / register -------------------------------------------

class _SignInView extends StatefulWidget {
  const _SignInView();

  @override
  State<_SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends State<_SignInView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  bool _registerMode = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = AppServices.of(context).authService;
    try {
      if (_registerMode) {
        await auth.register(
          email: _email.text.trim(),
          password: _password.text,
          displayName: _name.text.trim(),
        );
      } else {
        await auth.login(email: _email.text.trim(), password: _password.text);
      }
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _registerMode
                ? 'Account created — you are signed in.'
                : 'Signed in.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.isOffline
            ? 'Could not reach the server. Check your connection — Moodly '
                  'keeps working offline.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(
        () => _error = 'Enter your email first, then tap Forgot password.',
      );
      return;
    }
    setState(() => _busy = true);
    final auth = AppServices.of(context).authService;
    try {
      final result = await auth.forgotPassword(email);
      if (!mounted) return;
      setState(() => _busy = false);
      final token = result.devResetToken;
      if (token != null) {
        // Dev mode: show the token so the flow is testable without email.
        showDialog<void>(
          context: context,
          builder: (context) => _DevResetDialog(token: token),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('If an account exists, a reset link has been sent.'),
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.isOffline ? 'Could not reach the server.' : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          _registerMode ? 'Create your account' : 'Welcome back',
          style: theme.textTheme.headlineLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Accounts are optional. Everything in Moodly works locally without '
          'one — an account enables AI reflections and optional cloud sync.',
          style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty || !value.contains('@')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: [
                    if (_registerMode)
                      AutofillHints.newPassword
                    else
                      AutofillHints.password,
                  ],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: _registerMode
                        ? 'At least 8 characters, with a letter and a digit'
                        : null,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    final value = v ?? '';
                    if (value.length < 8) return 'Use at least 8 characters';
                    if (_registerMode && !RegExp(r'[A-Za-z]').hasMatch(value)) {
                      return 'Include a letter';
                    }
                    if (_registerMode && !RegExp(r'\d').hasMatch(value)) {
                      return 'Include a digit';
                    }
                    return null;
                  },
                ),
                if (_registerMode) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Display name (optional)',
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : Text(_registerMode ? 'Create account' : 'Sign in'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _registerMode = !_registerMode;
                          _error = null;
                        }),
                  child: Text(
                    _registerMode
                        ? 'I already have an account'
                        : 'Create an account',
                  ),
                ),
                if (!_registerMode)
                  TextButton(
                    onPressed: _busy ? null : _forgotPassword,
                    child: const Text('Forgot password?'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DevResetDialog extends StatelessWidget {
  const _DevResetDialog({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dev mode: reset token'),
      content: Text(
        'The backend is running in dev mode without an email provider, so the '
        'reset token is shown here instead of being emailed.\n\n$token',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// --- signed-in: profile ---------------------------------------------------------

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services = AppServices.of(context);
    final session = services.authService.session!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('Your account', style: theme.textTheme.headlineLarge),
        const SizedBox(height: 6),
        Text(
          'Signed in. Your account enables AI reflections and optional cloud '
          'sync — both are controlled in Privacy & data.',
          style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Profile'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(
                  session.displayName.isEmpty
                      ? 'No display name'
                      : session.displayName,
                ),
                subtitle: Text(
                  session.email.isEmpty ? 'Signed in (offline)' : session.email,
                ),
              ),
              const Divider(indent: 16, endIndent: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(
                  'Delete account',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                subtitle: const Text(
                  'Permanently removes your account and all synced records',
                ),
                onTap: () => _deleteAccount(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Session'),
        AppCard(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Sign out'),
                subtitle: const Text('Your data stays on this device'),
                onTap: () => services.authService.logout(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete your account?',
      message:
          'This permanently removes your account and every record synced to '
          'it (mood entries and any uploaded journal entries). Your data on '
          'this device is NOT deleted. This cannot be undone.',
      confirmLabel: 'Delete account',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final auth = AppServices.of(context).authService;
    try {
      await auth.deleteAccount();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Account deleted. Local data remains on this device.'),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.isOffline ? 'Could not reach the server.' : e.message,
          ),
        ),
      );
    }
  }
}
