import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/journal_entry.dart';
import '../../models/journal_reflection.dart';
import '../../repositories/journal_reflection_repository.dart';
import '../../services/ai_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_views.dart';

/// Shows a rule-based reflection for a journal entry, generating and caching
/// one on first use. Reflections are optional and clearly labeled as
/// rule-based (not medical advice).
class JournalReflectionScreen extends StatefulWidget {
  const JournalReflectionScreen({super.key, required this.entry});

  final JournalEntry entry;

  @override
  State<JournalReflectionScreen> createState() =>
      _JournalReflectionScreenState();
}

class _JournalReflectionScreenState extends State<JournalReflectionScreen> {
  late final JournalReflectionRepository _repository;
  late final AiServiceHolder _ai;

  JournalReflection? _reflection;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final services = AppServices.of(context);
    _repository = services.journalReflectionRepository;
    _ai = AiServiceHolder(services.aiService);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final existing = await _repository.getByEntryId(widget.entry.id!);
      if (existing != null) {
        setState(() {
          _reflection = existing;
          _loading = false;
        });
        return;
      }
      final result = await _ai.service.generateReflection(widget.entry);
      final saved = await _repository.saveForEntry(
        widget.entry.id!,
        JournalReflection(
          journalEntryId: widget.entry.id!,
          summary: result.summary,
          detectedEmotions: result.detectedEmotions,
          themes: result.themes,
          reflectionQuestions: result.reflectionQuestions,
          isRuleBased: result.isRuleBased,
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _reflection = saved;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _regenerate() async {
    setState(() => _loading = true);
    try {
      final result = await _ai.service.generateReflection(widget.entry);
      final saved = await _repository.saveForEntry(
        widget.entry.id!,
        JournalReflection(
          journalEntryId: widget.entry.id!,
          summary: result.summary,
          detectedEmotions: result.detectedEmotions,
          themes: result.themes,
          reflectionQuestions: result.reflectionQuestions,
          isRuleBased: result.isRuleBased,
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _reflection = saved;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reflection'),
        actions: [
          if (_error == null)
            IconButton(
              tooltip: 'Regenerate reflection',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _regenerate,
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const LoadingState(label: 'Reflecting on your entry…')
            : _error != null
            ? ErrorState(message: _error!, onRetry: _load)
            : _reflection == null
            ? ErrorState(message: 'No reflection available.', onRetry: _load)
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Text('Reflection', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    Formatters.mediumDate(widget.entry.date),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(title: "What you wrote"),
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        widget.entry.body,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(title: 'Summary'),
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _reflection!.summary,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  if (_reflection!.detectedEmotions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SectionHeader(title: 'Emotions detected in your words'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _reflection!.detectedEmotions
                          .map((e) => _EmotionChip(label: e))
                          .toList(),
                    ),
                  ],
                  if (_reflection!.themes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SectionHeader(title: 'Themes'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _reflection!.themes
                          .map((t) => Chip(label: Text(t)))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SectionHeader(title: 'Reflection questions'),
                  ..._reflection!.reflectionQuestions.map((q) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        child: ListTile(
                          leading: const Icon(
                            Icons.question_answer_rounded,
                            color: AppColors.primary,
                          ),
                          title: Text(q, style: theme.textTheme.bodyMedium),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),
                  AppCard(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'About this reflection',
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'This reflection is generated locally using simple '
                            'rules over your own words — it is not an AI '
                            'diagnosis and may be inaccurate. It is meant to '
                            'support personal reflection, not to evaluate your '
                            'mental health.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Nothing is uploaded. This stays on your device.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Simple accessor so the screen can be unit-tested with an injected service.
class AiServiceHolder {
  AiServiceHolder(this._service);
  final AiService _service;
  AiService get service => _service;
}

class _EmotionChip extends StatelessWidget {
  const _EmotionChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      label: Text(label),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
    );
  }
}
