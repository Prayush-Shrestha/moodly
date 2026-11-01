import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/theme/app_colors.dart';
import '../../repositories/settings_repository.dart';
import '../../services/sync_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/section_header.dart';

/// Cloud sync status and controls (Phase 3, optional).
///
/// Sync never runs by itself: the user enables it in Privacy & data and taps
/// "Sync now" here (or from Settings). Conflicts are resolved by recency —
/// the outcome of each run is shown honestly.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => SyncScreenState();
}

class SyncScreenState extends State<SyncScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    await AppServices.of(context).syncService.refresh();
  }

  Future<void> _syncNow() async {
    final sync = AppServices.of(context).syncService;
    final outcome = await sync.syncNow();
    if (!mounted || outcome == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final parts = <String>[
      if (outcome.uploadedMoods > 0) '${outcome.uploadedMoods} mood uploaded',
      if (outcome.uploadedJournals > 0)
        '${outcome.uploadedJournals} journal uploaded',
      if (outcome.downloadedMoods > 0)
        '${outcome.downloadedMoods} mood downloaded',
      if (outcome.downloadedJournals > 0)
        '${outcome.downloadedJournals} journal downloaded',
      if (outcome.resolvedConflicts > 0)
        '${outcome.resolvedConflicts} conflict(s) resolved with the newer cloud copy',
      if (outcome.keptLocalConflicts > 0)
        '${outcome.keptLocalConflicts} local edit(s) newer — kept and will be pushed',
      if (outcome.rejectedJournals > 0)
        '${outcome.rejectedJournals} journal(s) not uploaded — enable the journal opt-in',
    ];
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          parts.isEmpty ? 'Everything is up to date.' : parts.join(' · '),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services = AppServices.of(context);
    final settings = services.settingsRepository;

    return Scaffold(
      appBar: AppBar(title: const Text('Cloud sync')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([services.syncService, settings]),
          builder: (context, _) {
            final sync = services.syncService;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text('Sync your data', style: theme.textTheme.headlineLarge),
                const SizedBox(height: 6),
                Text(
                  'Optional and user-controlled. Local-first: everything stays '
                  'on this device and works offline — sync only backs it up '
                  'to your account.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 20),
                const SectionHeader(title: 'Status'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatusLine(
                        label: 'Cloud sync',
                        value: !services.authService.isSignedIn
                            ? 'Sign in to enable'
                            : (settings.cloudSyncEnabled
                                  ? 'Enabled'
                                  : 'Disabled'),
                        ok: sync.canSync,
                      ),
                      const SizedBox(height: 8),
                      _StatusLine(
                        label: 'Connection',
                        value: switch (sync.status) {
                          SyncStatus.disabled => 'Not active',
                          SyncStatus.idle => 'Ready',
                          SyncStatus.syncing => 'Syncing…',
                          SyncStatus.error => 'Problem — will retry on demand',
                        },
                        ok: sync.status == SyncStatus.idle,
                      ),
                      const SizedBox(height: 8),
                      _StatusLine(
                        label: 'Pending changes',
                        value:
                            '${sync.pendingMoods} mood · '
                            '${sync.pendingJournals} journal',
                        ok: sync.pendingMoods == 0 && sync.pendingJournals == 0,
                      ),
                      const SizedBox(height: 8),
                      _StatusLine(
                        label: 'Last sync',
                        value: sync.lastSyncAt == null
                            ? 'Never'
                            : _formatDateTime(sync.lastSyncAt!),
                        ok: sync.lastSyncAt != null,
                      ),
                      if (sync.lastError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          sync.lastError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                              sync.canSync && sync.status != SyncStatus.syncing
                              ? _syncNow
                              : null,
                          icon: sync.status == SyncStatus.syncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(Icons.sync_rounded),
                          label: const Text('Sync now'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeader(title: 'How conflicts are handled'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Each record keeps the time it was last edited. If the '
                        'same record changed in two places, the newer edit '
                        'wins — the older one is never silently kept. When '
                        'your local edit is newer, it stays on this device '
                        'and is pushed on the next sync.',
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Journal entries only sync with the separate journal '
                        'opt-in (Privacy & data).',
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeader(title: 'Advanced'),
                AppCard(child: _ServerUrlField(settings: settings)),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime time) {
    final local = time.toLocal();
    final date = '${local.day}/${local.month}/${local.year}';
    final clock =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return '$date $clock';
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.value,
    required this.ok,
  });

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 16,
          color: ok
              ? (theme.brightness == Brightness.light
                    ? AppColors.mint
                    : AppColors.darkMint)
              : theme.colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodyMedium),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _ServerUrlField extends StatefulWidget {
  const _ServerUrlField({required this.settings});

  final SettingsRepository settings;

  @override
  State<_ServerUrlField> createState() => _ServerUrlFieldState();
}

class _ServerUrlFieldState extends State<_ServerUrlField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.serverBaseUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Server address', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'The Moodly backend you connect to. On the Android emulator the '
          'host machine is 10.0.2.2; on a real device use its address.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'http://10.0.2.2:8000'),
          onSubmitted: (value) => widget.settings.setServerBaseUrl(value),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => widget.settings.setServerBaseUrl(_controller.text),
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}
