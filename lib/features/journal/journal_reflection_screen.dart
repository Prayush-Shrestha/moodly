import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/journal_entry.dart';
import '../../models/journal_reflection.dart';
import '../../repositories/journal_reflection_repository.dart';
import '../../services/ai_service.dart';
import '../../services/routing_ai_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_section.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_views.dart';

/// Shows a reflection for a journal entry, generating and caching one on
/// first use. Phase 3: reflections come from the AI backend when available
/// (signed in + consent), otherwise from the local rule-based fallback —
/// the true source is always labeled.
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
  late final RoutingAiService? _routing;

  JournalReflection? _reflection;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final services = AppServices.of(context);
    _repository = services.journalReflectionRepository;
    _ai = AiServiceHolder(services.aiService);
    _routing = services.aiService;
    _load();
  }

  /// Explains (in plain words) why a local fallback was used after a remote
  /// failure; null when there was no failure.
  String? get _fallbackReason {
    final reason = _routing?.lastRemoteFailure;
    if (reason == null) return null;
    return switch (reason) {
      'offline' =>
        'The AI service could not be reached (offline), so a local '
            'rule-based reflection was used instead.',
      'rate_limited' =>
        'The AI service asked to slow down, so a local rule-based '
            'reflection was used instead.',
      _ =>
        'The AI service had a problem, so a local rule-based reflection '
            'was used instead.',
    };
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
      await _generateAndSave();
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
      await _generateAndSave();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _generateAndSave() async {
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
        positiveObservations: result.positiveObservations,
        challenges: result.challenges,
        explicitEmotions: result.explicitEmotions,
        inferredEmotions: result.inferredEmotions,
        provider: result.provider,
      ),
    );
    if (!mounted) return;
    setState(() {
      _reflection = saved;
      _loading = false;
    });
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
                  Text('Reflection', style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          Formatters.mediumDate(widget.entry.date),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      _SourceBadge(reflection: _reflection!),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(title: "What you wrote"),
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        widget.entry.body,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.7,
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
                  if (_reflection!.explicitEmotions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SectionHeader(title: 'Emotions you expressed'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _reflection!.explicitEmotions
                          .map((e) => _EmotionChip(label: e))
                          .toList(),
                    ),
                  ],
                  if (_reflection!.inferredEmotions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SectionHeader(title: 'Emotions inferred (not exact words)'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _reflection!.inferredEmotions
                          .map((e) => _EmotionChip(label: e, inferred: true))
                          .toList(),
                    ),
                  ],
                  if (_reflection!.explicitEmotions.isEmpty &&
                      _reflection!.detectedEmotions.isNotEmpty) ...[
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
                  if (_reflection!.positiveObservations.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SectionHeader(title: 'Positive things you mentioned'),
                    ..._reflection!.positiveObservations.map(
                      (p) => _BulletLine(
                        icon: Icons.favorite_outline_rounded,
                        color: theme.brightness == Brightness.light
                            ? AppColors.mint
                            : AppColors.darkMint,
                        text: p,
                      ),
                    ),
                  ],
                  if (_reflection!.challenges.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SectionHeader(title: 'Challenges you mentioned'),
                    ..._reflection!.challenges.map(
                      (c) => _BulletLine(
                        icon: Icons.hiking_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                        text: c,
                      ),
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
                  AppSection(
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
                          _reflection!.isRuleBased
                              ? 'This reflection was generated locally using '
                                    'simple rules over your own words — no AI '
                                    'was involved and nothing left your device. '
                                    'It may be inaccurate and is meant to '
                                    'support personal reflection, not to '
                                    'evaluate your mental health.'
                              : 'This reflection was generated by an AI model '
                                    'from your entry. AI can be inaccurate or '
                                    'misread your words — treat it as a '
                                    'reflection aid, not a mental-health '
                                    'assessment. Your entry was sent only '
                                    'because you enabled AI processing in '
                                    'Privacy & data, and it is never used to '
                                    'train models.',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (_reflection!.isRuleBased &&
                            _fallbackReason != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.cloud_off_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _fallbackReason!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              _reflection!.isRuleBased
                                  ? Icons.lock_outline_rounded
                                  : Icons.sync_alt_rounded,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _reflection!.isRuleBased
                                    ? 'Nothing is uploaded. This stays on your '
                                          'device.'
                                    : 'One entry was sent for this reflection '
                                          '(with your consent). Reports and '
                                          'insights only ever send numbers, '
                                          'never journal text.',
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

/// Honest label of what produced the reflection.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.reflection});

  final JournalReflection reflection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAi = !reflection.isRuleBased;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAi ? Icons.auto_awesome_outlined : Icons.handyman_outlined,
            size: 13,
            color: isAi
                ? AppColors.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            isAi ? 'AI reflection' : 'Local reflection',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmotionChip extends StatelessWidget {
  const _EmotionChip({required this.label, this.inferred = false});

  final String label;

  /// Inferred emotions are visually and textually distinguished from emotions
  /// the writer explicitly expressed.
  final bool inferred;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: inferred
          ? const Icon(Icons.lightbulb_outline_rounded, size: 16)
          : null,
      label: Text(inferred ? '$label (inferred)' : label),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
    );
  }
}
