import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../app.dart';
import '../../core/utils/date_utils.dart';
import '../../models/journal_entry.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_header.dart';

/// Create or edit a standalone journal entry. Multiple entries per day are
/// allowed; only the body is required.
class JournalEditorScreen extends StatefulWidget {
  const JournalEditorScreen({super.key, this.existing});

  final JournalEntry? existing;

  @override
  State<JournalEditorScreen> createState() => _JournalEditorScreenState();
}

class _JournalEditorScreenState extends State<JournalEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late DateTime _date;
  bool _saving = false;
  bool _dirty = false;
  String? _validationError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _bodyController = TextEditingController(text: existing?.body ?? '');
    _date = AppDates.dateOnly(existing?.date ?? DateTime.now());
    _titleController.addListener(() => _dirty = true);
    _bodyController.addListener(() => _dirty = true);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return showConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Your edits will not be saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
  }

  Future<void> _cancel() async {
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop(false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = AppDates.dateOnly(picked));
  }

  Future<void> _save() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      setState(() => _validationError = 'Write something before saving.');
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    try {
      final repository = AppServices.of(context).journalRepository;
      final title = _titleController.text.trim();
      if (_isEditing) {
        await repository.update(
          widget.existing!.copyWith(
            date: _date,
            title: title,
            clearTitle: title.isEmpty,
            body: body,
          ),
        );
      } else {
        await repository.insert(
          JournalEntry(date: _date, title: title, body: body),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final message = e is DatabaseException || e is ArgumentError
          ? 'Could not save your entry. Your text is still here — please try again.'
          : 'Something went wrong. Your text is still here — please try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            onPressed: _cancel,
          ),
          title: Text(_isEditing ? 'Edit entry' : 'New entry'),
        ),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: _saving,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                TextField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    hintText: 'Title (optional)',
                    counterText: '',
                  ),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(16),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      hintText: 'Date',
                      prefixIcon: Icon(Icons.event_outlined),
                      suffixIcon: Icon(Icons.arrow_drop_down_rounded),
                    ),
                    child: Text(DateFormat('EEEE, MMMM d, y').format(_date)),
                  ),
                ),
                const SizedBox(height: 16),
                const SectionHeader(title: 'Entry'),
                TextField(
                  controller: _bodyController,
                  maxLines: 12,
                  minLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'What is on your mind?',
                  ),
                ),
                if (_validationError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _validationError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(_isEditing ? 'Save changes' : 'Save entry'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
