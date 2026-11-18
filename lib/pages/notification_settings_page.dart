import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/breakpoints.dart';
import '../core/notifications/push/push_messaging.dart';
import '../core/providers/notification_providers.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/ui/app_toast.dart';
import '../models/notification_preferences.dart';
import '../widgets/detail_shell.dart';
import '../widgets/page_header.dart';

/// Profile → "Oznámení" (NOTIF-6, spec §8).
///
/// The push switch covers the optional types only — the mandatory ones are
/// listed underneath because they arrive regardless. Quiet hours hold back
/// pushes overnight (default 20:00–07:00, resettable), and the learning
/// reminder is off until a time is picked. The device timezone is sent along
/// automatically, so all of it follows the user's own clock.
///
/// Every change is saved at once (`PUT /api/notification-preferences`) and
/// shown optimistically; a failed save puts the previous value back.
class NotificationSettingsPage extends ConsumerStatefulWidget {
  final VoidCallback? onBack;

  const NotificationSettingsPage({super.key, this.onBack});

  static const pushSwitchKey = Key('notification-settings-push');
  static const quietStartKey = Key('notification-settings-quiet-start');
  static const quietEndKey = Key('notification-settings-quiet-end');
  static const quietResetKey = Key('notification-settings-quiet-reset');
  static const reminderSwitchKey = Key('notification-settings-reminder');
  static const reminderTimeKey = Key('notification-settings-reminder-time');
  static const enableDeviceKey = Key('notification-settings-enable-device');

  /// Offered when the reminder is switched on without a time of its own.
  static const TimeOfDay defaultReminderTime = TimeOfDay(hour: 17, minute: 0);

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  NotificationPreferences? _prefs;
  bool _loading = true;
  bool _loadFailed = false;

  /// The server has no preferences endpoint (older API).
  bool _unavailable = false;

  /// Push works on this device but the OS permission is not granted.
  bool _deviceOff = false;

  String? _deviceTimezone;

  /// Only the newest save may write its answer back — an older one landing
  /// late would undo the user's last tap.
  int _saveSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _unavailable = false;
    });
    final result =
        await ref.read(notificationsRemoteDataSourceProvider).getPreferences();
    if (!mounted) return;
    if (result.isFailure) {
      setState(() {
        _loading = false;
        _loadFailed = true;
        _unavailable = result.statusCode == 404;
      });
      return;
    }
    setState(() {
      _loading = false;
      _prefs = result.data;
    });
    unawaited(_syncTimezone());
    unawaited(_checkDevicePermission());
  }

  /// Send the device timezone when the server has a different one.
  Future<void> _syncTimezone() async {
    final sync = ref.read(notificationTimezoneSyncProvider);
    final tz = await sync.deviceTimezone();
    if (!mounted || tz == null) return;
    setState(() => _deviceTimezone = tz);
    final prefs = _prefs;
    if (prefs == null || prefs.timezone == tz) return;
    final saved = await _save(
      {'timezone': tz},
      prefs.copyWith(timezone: () => tz),
      quiet: true,
    );
    if (saved) await sync.markSent(tz);
  }

  Future<void> _checkDevicePermission() async {
    final status = await ref.read(pushControllerProvider).authorization();
    if (!mounted || status == null) return;
    setState(() => _deviceOff = status != PushAuthorization.authorized);
  }

  Future<void> _enableOnDevice() async {
    final granted =
        await ref.read(pushControllerProvider).requestPermissionAndRegister();
    if (!mounted) return;
    if (granted) {
      setState(() => _deviceOff = false);
    } else {
      showAppToast(context, AppStrings.pushPermissionDenied);
    }
  }

  /// Save [changes], showing [optimistic] meanwhile. Returns whether it stuck.
  Future<bool> _save(
    Map<String, dynamic> changes,
    NotificationPreferences optimistic, {
    bool quiet = false,
  }) async {
    final previous = _prefs;
    final seq = ++_saveSeq;
    setState(() => _prefs = optimistic);

    final result = await ref
        .read(notificationsRemoteDataSourceProvider)
        .updatePreferences(changes);
    if (!mounted) return false;
    if (seq != _saveSeq) return result.isSuccess;

    if (result.isSuccess) {
      setState(() => _prefs = result.data);
      return true;
    }
    setState(() => _prefs = previous);
    if (!quiet) {
      showAppToast(
        context,
        AppStrings.notifSettingsSaveError,
        variant: ToastVariant.error,
      );
    }
    return false;
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) {
    return showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
  }

  Future<void> _setPush(bool enabled) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await _save({'push_enabled': enabled}, prefs.copyWith(pushEnabled: enabled));
  }

  Future<void> _pickQuietBound({required bool start}) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final current = NotificationPreferences.parseHm(
      start ? prefs.effectiveQuietHoursStart : prefs.effectiveQuietHoursEnd,
    );
    final picked = await _pickTime(current ?? const TimeOfDay(hour: 20, minute: 0));
    if (picked == null || !mounted) return;
    final value = NotificationPreferences.formatHm(picked);
    final from = start ? value : prefs.effectiveQuietHoursStart;
    final to = start ? prefs.effectiveQuietHoursEnd : value;
    // The API takes both bounds or neither.
    await _save(
      {'quiet_hours_start': from, 'quiet_hours_end': to},
      prefs.copyWith(quietHoursStart: () => from, quietHoursEnd: () => to),
    );
  }

  Future<void> _resetQuietHours() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await _save(
      {'quiet_hours_start': null, 'quiet_hours_end': null},
      prefs.copyWith(quietHoursStart: () => null, quietHoursEnd: () => null),
    );
  }

  Future<void> _setReminder(bool on) async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (!on) {
      await _save(
        {'reminder_time': null},
        prefs.copyWith(reminderTime: () => null),
      );
      return;
    }
    await _pickReminderTime();
  }

  Future<void> _pickReminderTime() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final picked = await _pickTime(
      NotificationPreferences.parseHm(prefs.reminderTime) ??
          NotificationSettingsPage.defaultReminderTime,
    );
    // Cancelled: a reminder switched on without a time stays off.
    if (picked == null || !mounted) return;
    final value = NotificationPreferences.formatHm(picked);
    await _save(
      {'reminder_time': value},
      (_prefs ?? prefs).copyWith(reminderTime: () => value),
    );
  }

  // ── Layout ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (context.widthClass == WidthClass.compact) {
      return _buildPage(context, showHeader: true);
    }
    // Above the phone breakpoint this route sits over the shell; without the
    // sidebar the user would drop out of the navigation (same as the profile).
    return DetailShell(
      title: AppStrings.profileNotifications,
      onBack: widget.onBack,
      accountActive: true,
      child: ContentWidth(
        maxWidth: ContentWidth.reading,
        child: _buildPage(context, showHeader: false),
      ),
    );
  }

  Widget _buildPage(BuildContext context, {required bool showHeader}) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            if (showHeader) ...[
              PageHeader(
                title: AppStrings.profileNotifications,
                onBack: widget.onBack,
              ),
              const SizedBox(height: 24),
            ],
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final prefs = _prefs;
    if (_loadFailed || prefs == null) return _buildError();

    final timezone =
        prefs.timezone ?? _deviceTimezone ?? prefs.defaultTimezone;
    final push = ref.read(pushControllerProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        _card([
          _switchRow(
            key: NotificationSettingsPage.pushSwitchKey,
            icon: Icons.notifications_outlined,
            title: AppStrings.notifSettingsPushTitle,
            subtitle: AppStrings.notifSettingsPushSubtitle,
            value: prefs.pushEnabled,
            onChanged: _setPush,
          ),
          if (_deviceOff && push.isAvailable) ...[
            _divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStrings.notifSettingsDeviceOff,
                      style: AppTextStyles.bodySmall(
                        color: AppColors.primaryDark64,
                      ),
                    ),
                  ),
                  TextButton(
                    key: NotificationSettingsPage.enableDeviceKey,
                    onPressed: _enableOnDevice,
                    child: Text(AppStrings.notifSettingsDeviceEnable),
                  ),
                ],
              ),
            ),
          ],
        ]),
        if (prefs.mandatoryTypes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.notifSettingsMandatoryTitle,
                  style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
                ),
                const SizedBox(height: 4),
                for (final type in prefs.mandatoryTypes)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '• ${type.name}',
                      style: AppTextStyles.bodySmall(
                        color: AppColors.primaryDark64,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        _sectionHeader(AppStrings.notifSettingsQuietTitle),
        const SizedBox(height: 8),
        _card([
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              AppStrings.notifSettingsQuietSubtitle,
              style: AppTextStyles.bodySmall(color: AppColors.primaryDark48),
            ),
          ),
          _timeRow(
            key: NotificationSettingsPage.quietStartKey,
            label: AppStrings.notifSettingsQuietFrom,
            value: prefs.effectiveQuietHoursStart,
            onTap: () => _pickQuietBound(start: true),
          ),
          _divider(),
          _timeRow(
            key: NotificationSettingsPage.quietEndKey,
            label: AppStrings.notifSettingsQuietTo,
            value: prefs.effectiveQuietHoursEnd,
            onTap: () => _pickQuietBound(start: false),
          ),
          _divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: TextButton(
                key: NotificationSettingsPage.quietResetKey,
                onPressed:
                    prefs.quietHoursAreDefault ? null : _resetQuietHours,
                child: Text(AppStrings.notifSettingsQuietReset),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 24),
        _sectionHeader(AppStrings.notifSettingsReminderTitle),
        const SizedBox(height: 8),
        _card([
          _switchRow(
            key: NotificationSettingsPage.reminderSwitchKey,
            icon: Icons.alarm_outlined,
            title: AppStrings.notifSettingsReminderTitle,
            subtitle: AppStrings.notifSettingsReminderSubtitle,
            value: prefs.reminderTime != null,
            onChanged: _setReminder,
          ),
          if (prefs.reminderTime != null) ...[
            _divider(),
            _timeRow(
              key: NotificationSettingsPage.reminderTimeKey,
              label: AppStrings.notifSettingsReminderTime,
              value: prefs.reminderTime!,
              onTap: _pickReminderTime,
            ),
          ],
        ]),
        if (timezone != null) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              AppStrings.notifSettingsTimezone(timezone),
              style: AppTextStyles.caption(color: AppColors.primaryDark48),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _unavailable
                  ? AppStrings.notifSettingsUnavailable
                  : AppStrings.notifSettingsLoadError,
              style: AppTextStyles.bodyLarge(color: AppColors.primaryDark64),
              textAlign: TextAlign.center,
            ),
            if (!_unavailable) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: _load,
                child: Text(AppStrings.novinkyRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(title, style: AppTextStyles.meta(color: AppColors.primaryDark48)),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDecorations.radiusL,
        boxShadow: AppDecorations.shadowLight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(height: 1, color: AppColors.primaryDark08),
    );
  }

  Widget _switchRow({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.primaryDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.statSuffix()),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall(color: AppColors.primaryDark48),
                ),
              ],
            ),
          ),
          Switch(
            key: key,
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primaryDark,
            activeTrackColor: AppColors.primary,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: AppColors.primaryDark16,
          ),
        ],
      ),
    );
  }

  Widget _timeRow({
    required Key key,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTextStyles.statSuffix())),
            Text(value, style: AppTextStyles.bodyBold()),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 22, color: AppColors.primaryDark32),
          ],
        ),
      ),
    );
  }
}
