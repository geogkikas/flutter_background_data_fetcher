import 'dart:convert';

/// Represents a single snapshot of generic data saved in the background.
class BackgroundLog {
  /// The SQLite database ID. Null if not yet saved.
  final int? sqliteId;

  /// ISO-8601 timestamp of when the data was collected.
  final String timestamp;

  /// The dynamic JSON payload fetched from your callback.
  final Map<String, dynamic> payload;

  /// Whether this data has been synced to a remote server.
  final bool isSynced;

  BackgroundLog({
    this.sqliteId,
    required this.timestamp,
    required this.payload,
    this.isSynced = false,
  });

  factory BackgroundLog.fromJson(Map<String, dynamic> json) {
    // Parse the stringified payload back into a Map
    final payloadString = json['payload'] as String?;
    final Map<String, dynamic> parsedPayload = payloadString != null
        ? jsonDecode(payloadString)
        : {};

    return BackgroundLog(
      sqliteId: json['sqlite_id'],
      timestamp: json['timestamp'] ?? '',
      payload: parsedPayload,
      isSynced: json['is_synced'] == 1 || json['is_synced'] == true,
    );
  }
}
