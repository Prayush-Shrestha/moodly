import 'dart:math';

/// Stable per-row identifiers used for cloud synchronization.
///
/// A `client_id` is generated once (on first save/sync) and never changes, so
/// the same row can be recognized across devices and duplicate records are
/// impossible regardless of which device uploads first. UUIDv4-compatible
/// format, generated from a cryptographically secure source without adding a
/// package dependency.
class ClientId {
  ClientId._();

  static final Random _random = Random.secure();

  /// 32 random hex chars grouped as a UUID: `xxxxxxxx-xxxx-4xxx-8xxx-xxxxxxxxxxxx`.
  static String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
