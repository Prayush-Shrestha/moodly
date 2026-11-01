import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../app.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/formatters.dart';
import '../../models/emotion.dart';
import '../../models/mood.dart';
import '../../models/mood_entry.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/energy_selector.dart';
import '../../widgets/emotion_chips.dart';
import '../../widgets/mood_selector.dart';
import '../../widgets/section_header.dart';

/// Daily mood check-in form.
///
/// Editing an existing entry (or saving twice for the same day) is safe: the
/// repository upserts per local calendar day, so no duplicate can be created.
class MoodCheckInScreen extends StatefulWidget {
  const MoodCheckInScreen({super.key, this.existing, this.date});

  /// When provided, the screen edits this entry.
  final MoodEntry? existing;

  /// Target day for a new check-in; defaults to today.
  final DateTime? date;

  @override
  State<MoodCheckInScreen> createState() => _MoodCheckInScreenState();
}

class _MoodCheckInScreenState extends State<MoodCheckInScreen> {
  late final DateTime _date;
  Mood? _mood;
  Set<Emotion> _emotions = {};
  int _energy = 3;
  late final TextEditingController _noteController;
  bool _saving = false;
  bool _dirty = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _date = AppDates.dateOnly(existing?.date ?? widget.date ?? DateTime.now());
    if (existing != null) {
      _mood = existing.mood;
      _emotions = existing.emotions.toSet();
      _energy = existing.energy;
      _noteController = TextEditingController(text: existing.note ?? '');
    } else {
      _noteController = TextEditingController();
    }
    _noteController.addListener(() => _dirty = true);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return showConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Your edits to this check-in will not be saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
  }

  Future<void> _cancel() async {
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop(false);
  }

  Future<void> _save() async {
    final mood = _mood;
    if (mood == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose how you are feeling.')),
      );
      return;
    }
    if (AppDates.isFuture(_date)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot check in for future dates.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = AppServices.of(context).moodRepository;
      final note = _noteController.text.trim();
      await repository.save(
        widget.existing?.copyWith(
              date: _date,
              mood: mood,
              emotions: _emotions.toList(),
              energy: _energy,
              note: note,
              clearNote: note.isEmpty,
            ) ??
            MoodEntry(
              date: _date,
              mood: mood,
              emotions: _emotions.toList(),
              energy: _energy,
              note: note.isEmpty ? null : note,
            ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final message = e is DatabaseException || e is ArgumentError
          ? describeDbError(e)
          : 'Could not save your check-in. Please try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _mood != null && !_saving;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop(false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
            onPressed: _cancel,
          ),
          title: Text(_isEditing ? 'Edit check-in' : 'Check in'),
          actions: [
            TextButton(onPressed: _cancel, child: const Text('Cancel')),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              AbsorbPointer(
                absorbing: _saving,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                  children: [
                    _buildDateHeader(theme),
                    const SizedBox(height: 20),
                    _buildMoodSection(theme),
                    const SizedBox(height: 24),
                    _buildEmotionSection(theme),
                    const SizedBox(height: 24),
                    _buildEnergySection(theme),
                    const SizedBox(height: 24),
                    _buildNoteSection(theme),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
              if (_saving)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: LoadingOverlay(),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: canSave ? _save : null,
              icon: const Icon(Icons.check_rounded),
              label: Text(_isEditing ? 'Save changes' : 'Save check-in'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(Formatters.fullDate(_date), style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          _isEditing ? 'Update how this day felt' : 'How did this day feel?',
          style: theme.textTheme.titleLarge,
        ),
      ],
    );
  }

  Widget _buildMoodSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Mood'),
        MoodSelector(
          selected: _mood,
          onSelected: (mood) => setState(() {
            _mood = mood;
            _dirty = true;
          }),
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          child: _mood == null
              ? Text(
                  'Choose one to continue',
                  key: const ValueKey('hint'),
                  style: theme.textTheme.bodySmall,
                )
              : Text(
                  '${_mood!.label} · ${_mood!.subtitle}',
                  key: ValueKey(_mood),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _mood!.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmotionSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Emotions (optional)'),
        Text('Tap everything that applies.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        EmotionChips(
          selected: _emotions,
          onChanged: (next) => setState(() {
            _emotions = next;
            _dirty = true;
          }),
        ),
        if (_emotions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${_emotions.length} selected',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEnergySection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Energy level'),
        EnergySelector(
          value: _energy,
          onChanged: (level) => setState(() {
            _energy = level;
            _dirty = true;
          }),
        ),
      ],
    );
  }

  Widget _buildNoteSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Note (optional)'),
        TextField(
          controller: _noteController,
          maxLines: 5,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 2000,
          decoration: InputDecoration(
            hintText: 'What made you feel this way?',
            counterStyle: const TextStyle(fontSize: 12),
            counterText: '',
          ),
        ),
      ],
    );
  }
}

/// Small centered spinner used while a save is in flight.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
        ),
        child: const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}
