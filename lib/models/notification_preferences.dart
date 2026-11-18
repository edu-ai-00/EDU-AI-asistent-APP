import 'package:flutter/material.dart' show TimeOfDay;

/// A notification type that always arrives, whatever the push switch says
/// (maintenance, important app updates).
class MandatoryNotificationType {
  final String key;
  final String name;

  const MandatoryNotificationType({required this.key, required this.name});
}

/// `GET|PUT /api/notification-preferences` (NOTIF-6).
///
/// Times travel as `HH:MM` strings. A null quiet-hours bound means "the
/// server default", which [defaultQuietHoursStart]/[defaultQuietHoursEnd]
/// carry; a null [reminderTime] means the learning reminder is off.
class NotificationPreferences {
  final bool pushEnabled;
  final String? quietHoursStart;
  final String? quietHoursEnd;
  final String? reminderTime;
  final String? timezone;
  final String defaultQuietHoursStart;
  final String defaultQuietHoursEnd;
  final String? defaultTimezone;
  final List<MandatoryNotificationType> mandatoryTypes;

  const NotificationPreferences({
    required this.pushEnabled,
    this.quietHoursStart,
    this.quietHoursEnd,
    this.reminderTime,
    this.timezone,
    this.defaultQuietHoursStart = '20:00',
    this.defaultQuietHoursEnd = '07:00',
    this.defaultTimezone,
    this.mandatoryTypes = const [],
  });

  /// The quiet hours actually in force.
  String get effectiveQuietHoursStart =>
      quietHoursStart ?? defaultQuietHoursStart;
  String get effectiveQuietHoursEnd => quietHoursEnd ?? defaultQuietHoursEnd;

  /// Whether "reset to default" would change anything.
  bool get quietHoursAreDefault =>
      effectiveQuietHoursStart == defaultQuietHoursStart &&
      effectiveQuietHoursEnd == defaultQuietHoursEnd;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    final defaults = json['defaults'] is Map
        ? Map<String, dynamic>.from(json['defaults'] as Map)
        : const <String, dynamic>{};
    final mandatory = json['mandatory_types'];

    return NotificationPreferences(
      pushEnabled: json['push_enabled'] != false,
      quietHoursStart: normalizeHm(json['quiet_hours_start']),
      quietHoursEnd: normalizeHm(json['quiet_hours_end']),
      reminderTime: normalizeHm(json['reminder_time']),
      timezone: json['timezone'] as String?,
      defaultQuietHoursStart:
          normalizeHm(defaults['quiet_hours_start']) ?? '20:00',
      defaultQuietHoursEnd: normalizeHm(defaults['quiet_hours_end']) ?? '07:00',
      defaultTimezone: defaults['timezone'] as String?,
      mandatoryTypes: [
        if (mandatory is List)
          for (final row in mandatory)
            if (row is Map && row['name'] is String)
              MandatoryNotificationType(
                key: row['key']?.toString() ?? '',
                name: row['name'] as String,
              ),
      ],
    );
  }

  /// Copy with some fields replaced. The nullable fields take a closure so
  /// "set to null" (back to default / reminder off) can be told apart from
  /// "leave as is".
  NotificationPreferences copyWith({
    bool? pushEnabled,
    String? Function()? quietHoursStart,
    String? Function()? quietHoursEnd,
    String? Function()? reminderTime,
    String? Function()? timezone,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      quietHoursStart:
          quietHoursStart != null ? quietHoursStart() : this.quietHoursStart,
      quietHoursEnd: quietHoursEnd != null ? quietHoursEnd() : this.quietHoursEnd,
      reminderTime: reminderTime != null ? reminderTime() : this.reminderTime,
      timezone: timezone != null ? timezone() : this.timezone,
      defaultQuietHoursStart: defaultQuietHoursStart,
      defaultQuietHoursEnd: defaultQuietHoursEnd,
      defaultTimezone: defaultTimezone,
      mandatoryTypes: mandatoryTypes,
    );
  }

  /// `"20:00:00"` (a SQL `time`) or `"20:00"` → `"20:00"`; anything else null.
  static String? normalizeHm(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return formatHm(TimeOfDay(hour: hour, minute: minute));
  }

  static TimeOfDay? parseHm(String? value) {
    final normalized = normalizeHm(value);
    if (normalized == null) return null;
    return TimeOfDay(
      hour: int.parse(normalized.substring(0, 2)),
      minute: int.parse(normalized.substring(3, 5)),
    );
  }

  static String formatHm(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}
