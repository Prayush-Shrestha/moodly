import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../repositories/settings_repository.dart';
import '../../services/remote_ai_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_section.dart';
import '../../widgets/section_header.dart';

/// Privacy controls and explicit consents (Phase 3).
///
/// Every switch starts OFF. Turning one on is the user's explicit choice:
/// - AI processing: journal text may be sent for AI reflections (only while
///   signed in; each reflection still requires the entry-level "Reflect"
///   action).
/// - Cloud sync: mood records may sync to the account.
/// - Journal upload: journal entries may sync (requires cloud sync too).
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => PrivacyScreenState();
}

class PrivacyScreenState extends State<PrivacyScreen> {
  bool _checkingStatus = true;
  bool _reachable = false;
  bool _aiEnabled = false;
  String _aiProvider = 'none';

  @override
  void initState() {
    super.initState();
    _checkBackend();
  }

  /// Called by tests/other screens to re-check connection + AI status.
  Future<void> _checkBackend() async {
    setState(() => _checkingStatus = true);
    final services = AppServices.of(context);
    try {
      await services.apiClient.get('/health', auth: false);
      if (!mounted) return;
      setState(() => _reachable = true);
      if (services.authService.isSignedIn) {
        final status = await RemoteAiService(
          api: services.apiClient,
          auth: services.authService,
          settings: services.settingsRepository,
        ).fetchStatus();
        if (!mounted) return;
        setState(() {
          _aiEnabled = status.aiEnabled;
          _aiProvider = status.provider;
        });
      }
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _reachable = false;
        _aiEnabled = false;
      });
    } finally {
      if (mounted) setState(() => _checkingStatus = false);
    }
  }

  Future<void> _setConsent(
    Future<void> Function(SettingsRepository) update,
  ) async {
    final settings = AppServices.of(context).settingsRepository;
    await update(settings);
    // Mirror to the account record when signed in (server-side double gate).
    if (mounted && AppServices.of(context).authService.isSignedIn) {
      await AppServices.of(context).authService.onConsentChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = AppServices.of(context).settingsRepository;
    final signedIn = AppServices.of(context).authService.isSignedIn;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & data')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text('You are in control', style: theme.textTheme.headlineLarge),
              const SizedBox(height: 6),
              Text(
                'Moodly is local-first. Nothing leaves this device unless you '
                'turn it on below — and you can turn it off at any time.',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 20),

              // --- connection & AI status ---------------------------------
              const SectionHeader(title: 'Connection & AI'),
              AppCard(
                child: _checkingStatus
                    ? const LinearProgressIndicator(minHeight: 3)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StatusRow(
                            icon: Icons.dns_outlined,
                            label: 'Backend server',
                            value: _reachable
                                ? 'Reachable'
                                : 'Not reachable (offline mode)',
                            ok: _reachable,
                          ),
                          const SizedBox(height: 10),
                          _StatusRow(
                            icon: Icons.auto_awesome_outlined,
                            label: 'AI provider',
                            value: !signedIn
                                ? 'Sign in to use AI features'
                                : (_aiEnabled
                                      ? 'AI provider configured ($_aiProvider)'
                                      : 'No AI provider configured — local '
                                            'rule-based reflections are used'),
                            ok: signedIn && _aiEnabled,
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _checkBackend,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Check again'),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 20),

              // --- consents -----------------------------------------------
              const SectionHeader(title: 'Your consents'),
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('AI processing'),
                      subtitle: const Text(
                        'Allows one journal entry at a time to be sent for an '
                        'AI reflection when you tap "Reflect". Requires an '
                        'account. Your entries are never used for model '
                        'training.',
                      ),
                      value: settings.aiProcessingConsent,
                      onChanged: signedIn
                          ? (v) =>
                                _setConsent((s) => s.setAiProcessingConsent(v))
                          : null,
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cloud sync'),
                      subtitle: const Text(
                        'Backs up your mood check-ins to your account so you '
                        'can access them from other devices. Off by default.',
                      ),
                      value: settings.cloudSyncEnabled,
                      onChanged: signedIn
                          ? (v) => _setConsent((s) => s.setCloudSyncEnabled(v))
                          : null,
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Upload journal entries'),
                      subtitle: const Text(
                        'Journal entries are private. This extra opt-in is '
                        'required before any journal text can sync — even '
                        'when cloud sync is on.',
                      ),
                      value: settings.journalUploadConsent,
                      onChanged: signedIn && settings.cloudSyncEnabled
                          ? (v) =>
                                _setConsent((s) => s.setJournalUploadConsent(v))
                          : null,
                    ),
                  ],
                ),
              ),
              if (!signedIn)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Sign in (Settings → Account) to enable AI and sync '
                    'consents.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 20),

              // --- what is stored where ------------------------------------
              const SectionHeader(title: 'What is stored where'),
              AppSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DataLine(
                      icon: Icons.phone_iphone_rounded,
                      text:
                          'On this device (always): every mood check-in, '
                          'journal entry, reflection and report, in a local '
                          'SQLite database (not encrypted by default).',
                    ),
                    const SizedBox(height: 10),
                    _DataLine(
                      icon: Icons.cloud_outlined,
                      text:
                          'On the server (only with your consents above): '
                          'mood check-ins for sync; journal entries only with '
                          'the journal opt-in. Protected by HTTPS-ready APIs '
                          'and account authentication.',
                    ),
                    const SizedBox(height: 10),
                    _DataLine(
                      icon: Icons.auto_awesome_outlined,
                      text:
                          'Sent for AI (only with AI consent + an account): '
                          'exactly one journal entry per reflection, or '
                          'aggregate statistics for reports — never your whole '
                          'journal.',
                    ),
                    const SizedBox(height: 10),
                    _DataLine(
                      icon: Icons.school_outlined,
                      text:
                          'Never: your data is not used to train AI models; '
                          'passwords are hashed with Argon2; journal content '
                          'is never written to server logs.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- disclaimer --------------------------------------------
              AppSection(
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI reflections can be inaccurate. They are a '
                        'reflection aid — not a medical or mental-health '
                        'evaluation.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.ok,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    ok
                        ? Icons.check_circle_rounded
                        : Icons.remove_circle_outline,
                    size: 14,
                    color: ok ? AppColors.mint : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(value, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DataLine extends StatelessWidget {
  const _DataLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }
}
