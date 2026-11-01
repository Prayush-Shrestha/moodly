import 'package:flutter/foundation.dart';

import '../core/network/api_client.dart';
import '../models/journal_entry.dart';
import 'ai_service.dart';
import 'journal_reflection_service.dart';
import 'remote_ai_service.dart';

/// Routes reflection requests to the remote AI backend when it is genuinely
/// available (signed in + AI consent + reachable), and otherwise falls back
/// to the Phase 2 local rule-based reflection.
///
/// Honesty rules:
/// - The returned result always reflects its real source (`provider` field).
/// - A remote failure never breaks the flow: the local reflection is returned
///   and the failure is recorded in [lastRemoteFailure] so the UI can explain
///   why the local fallback was used.
class RoutingAiService implements AiService {
  RoutingAiService({required this.local, required this.remote});

  final AiService local;
  final RemoteAiService remote;

  /// Why the most recent remote attempt failed (null = no failure/n.a.).
  String? lastRemoteFailure;

  bool get canUseRemote => remote.isAvailable;

  @override
  bool get isRuleBased => !remote.isAvailable;

  @override
  Future<JournalReflectionResult> generateReflection(JournalEntry entry) async {
    if (!remote.isAvailable) {
      lastRemoteFailure = null;
      return local.generateReflection(entry);
    }
    try {
      final result = await remote.generateReflection(entry);
      lastRemoteFailure = null;
      return result;
    } on ApiException catch (e) {
      lastRemoteFailure = e.isOffline
          ? 'offline'
          : (e.isRateLimited ? 'rate_limited' : 'server_error');
      debugPrint(
        'remote AI unavailable (${e.isOffline ? 'offline' : e.statusCode}) — using local reflection',
      );
      return local.generateReflection(entry);
    } catch (e) {
      lastRemoteFailure = 'server_error';
      return local.generateReflection(entry);
    }
  }
}
