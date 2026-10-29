import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/utils/formatters.dart';
import '../../models/journal_entry.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/status_views.dart';
import 'journal_editor_screen.dart';

/// Journal tab: searchable list of standalone entries with create/edit/delete.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => JournalScreenState();
}

class JournalScreenState extends State<JournalScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<JournalEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Called by the shell when this tab is (re)selected.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await AppServices.of(context).journalRepository
          .getAll(query: _query);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your journal.';
      });
    }
  }

  Future<void> _openEditor({JournalEntry? entry}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => JournalEditorScreen(existing: entry)),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _openDetail(JournalEntry entry) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => JournalDetailScreen(entry: entry)),
    );
    if (changed == true && mounted) _load();
  }

  Future<void> _delete(JournalEntry entry) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete entry?',
      message: '"${entry.displayTitle}" will be permanently removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await AppServices.of(context).journalRepository.delete(entry.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entry deleted.')));
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete the entry. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New entry'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  _query = value;
                  _load();
                },
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search your entries…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            _query = '';
                            _load();
                          },
                        ),
                ),
              ),
            ),
            Expanded(child: _buildBody(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const LoadingState(label: 'Loading entries…');
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    if (_entries.isEmpty) {
      return EmptyState(
        icon: Icons.menu_book_outlined,
        title: _query.isEmpty ? 'Your journal is empty' : 'No matches',
        message: _query.isEmpty
            ? 'Write freely about your day — journal entries are private and stored on this device.'
            : 'Nothing matches "$_query". Try a different search.',
        actionLabel: _query.isEmpty ? 'Write your first entry' : null,
        onAction: _query.isEmpty ? () => _openEditor() : null,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return Dismissible(
            key: ValueKey('journal-${entry.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                color: theme.colorScheme.error,
              ),
            ),
            confirmDismiss: (_) async {
              await _delete(entry);
              return false; // handled manually so the list can reload
            },
            child: Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _openDetail(entry),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete entry',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                            ),
                            onPressed: () => _delete(entry),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Formatters.mediumDate(entry.date),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Read-only view of one journal entry with edit and delete actions.
class JournalDetailScreen extends StatelessWidget {
  const JournalDetailScreen({super.key, required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entry'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => JournalEditorScreen(existing: entry),
                ),
              );
              if (saved == true && context.mounted) {
                Navigator.of(context).pop(true);
              }
            },
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final confirmed = await showConfirmDialog(
                context,
                title: 'Delete entry?',
                message: '"${entry.displayTitle}" will be permanently removed.',
                confirmLabel: 'Delete',
                destructive: true,
              );
              if (!confirmed || !context.mounted) return;
              try {
                await AppServices.of(context).journalRepository
                    .delete(entry.id!);
                if (context.mounted) Navigator.of(context).pop(true);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Could not delete the entry. Please try again.',
                      ),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(entry.displayTitle, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              Formatters.fullDate(entry.date),
              style: theme.textTheme.bodySmall,
            ),
            if (!entry.createdAt.isAtSameMomentAs(entry.updatedAt)) ...[
              const SizedBox(height: 2),
              Text(
                'Edited ${Formatters.dateTime(entry.updatedAt)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 20),
            Text(
              entry.body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
