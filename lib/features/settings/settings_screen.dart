import 'package:flutter/material.dart';

import '../../app.dart';
import '../../repositories/settings_repository.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/logo_mark.dart';
import '../../widgets/section_header.dart';
import '../account/account_screen.dart';
import '../privacy/privacy_screen.dart';
import '../reports/reports_screen.dart';
import '../sync/sync_screen.dart';

/// Settings: theme, Phase 3 account/sync/reports/privacy, data export,
/// clear data and app info.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final SettingsRepository settings;

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  int _moodCount = 0;
  int _journalCount = 0;
  bool _exporting = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Called by the shell when this tab is (re)selected.
  Future<void> refresh() => _loadCounts();

  Future<void> _loadCounts() async {
    try {
      final services = AppServices.of(context);
      final moods = await services.moodRepository.count();
      final journals = await services.journalRepository.count();
      if (!mounted) return;
      setState(() {
        _moodCount = moods;
        _journalCount = journals;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final result = await AppServices.of(context).exportService.exportAll();
      if (!mounted) return;
      final message = result.shared
          ? 'Backup ready — choose where to save it.'
          : 'Backup saved to a temporary file:\n${result.savedPath}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear all data?',
      message:
          'Every mood check-in, journal entry, and saved reflection will be permanently deleted from this device. '
          'This cannot be undone. Consider exporting a backup first.',
      confirmLabel: 'Delete everything',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final services = AppServices.of(context);
      await services.moodRepository.deleteAll();
      await services.journalRepository.deleteAll();
      await services.journalReflectionRepository.deleteAll();
      await services.reportRepository.deleteAll();
      if (!mounted) return;
      await _loadCounts();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('All data deleted.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not clear data. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services = AppServices.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: services.authService,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              const SectionHeader(title: 'Appearance'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Theme', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {widget.settings.themeMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) =>
                          widget.settings.setThemeMode(selection.first),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Account & sync'),
              AppCard(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline_rounded),
                      title: const Text('Account'),
                      subtitle: Text(
                        services.authService.isSignedIn
                            ? (services.authService.session?.email.isNotEmpty ==
                                      true
                                  ? services.authService.session!.email
                                  : 'Signed in')
                            : 'Optional — sign in for AI and sync',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AccountScreen(),
                        ),
                      ),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.sync_rounded),
                      title: const Text('Cloud sync'),
                      subtitle: Text(
                        !services.authService.isSignedIn
                            ? 'Sign in to enable'
                            : (widget.settings.cloudSyncEnabled
                                  ? 'Enabled — manage and run sync here'
                                  : 'Disabled (opt-in)'),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SyncScreen(),
                        ),
                      ),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.summarize_outlined),
                      title: const Text('Reports'),
                      subtitle: const Text(
                        'Weekly and monthly summaries from your check-ins',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ReportsScreen(),
                        ),
                      ),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Privacy & data'),
                      subtitle: const Text(
                        'Consents, AI processing, what is stored where',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PrivacyScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Your data'),
              AppCard(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.ios_share_rounded),
                      title: const Text('Export all data (JSON)'),
                      subtitle: Text(
                        _loading
                            ? 'Loading…'
                            : '$_moodCount mood check-ins · $_journalCount journal entries',
                      ),
                      trailing: _exporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      enabled: !_exporting,
                      onTap: _export,
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: Icon(
                        Icons.delete_forever_outlined,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        'Clear all data',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      subtitle: const Text(
                        'Permanently delete everything on this device',
                      ),
                      onTap: _clearAllData,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'About'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: BrandLockup(markSize: 60)),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        'Version 1.1.0 (Phase 3)',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Privacy', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Moodly is local-first: your mood check-ins, journal entries, '
                      'reflections, and reports are stored on this device in a SQLite '
                      'database. SQLite files are not encrypted by default, so treat '
                      'this device accordingly. Optional cloud sync and AI reflections '
                      'require an account and explicit consent (Settings → Privacy & '
                      'data) — nothing is uploaded otherwise, and your data is never '
                      'used to train AI models.',
                      style: theme.textTheme.bodySmall,
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
