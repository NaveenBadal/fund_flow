import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/expense_provider.dart';
import '../providers/notification_ingestion_provider.dart';

final appControlServiceProvider = Provider(AppControlService.new);

/// The sole mutation boundary for assistant-driven app settings.
class AppControlService {
  AppControlService(this.ref);
  final Ref ref;
  Future<void> Function()? _undo;

  bool get canUndo => _undo != null;

  Future<void> undoLast() async {
    final action = _undo;
    _undo = null;
    if (action != null) await action();
  }

  Future<Map<String, dynamic>> handle(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    switch (name) {
      case 'get_app_state':
        return {
          'theme': ref.read(themeModeProvider).name,
          'amounts_visible': !ref.read(privateModeProvider),
          'app_lock_enabled': ref.read(appLockEnabledProvider),
          'notification_capture_enabled': ref.read(
            notificationParsingEnabledProvider,
          ),
          'preferred_currency': ref.read(preferredCurrencyProvider),
          'sync_lookback_days': ref.read(syncLookbackProvider),
        };
      case 'set_theme':
        final previous = ref.read(themeModeProvider);
        final mode = switch (arguments['mode']?.toString()) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => throw ArgumentError('mode must be system, light, or dark'),
        };
        await _persistTheme(mode);
        _undo = () => _persistTheme(previous);
        return {'changed': true, 'theme': mode.name, 'undo_available': true};
      case 'set_amount_visibility':
        final previous = !ref.read(privateModeProvider);
        final visible = _bool(arguments, 'visible');
        await ref.read(privateModeProvider.notifier).set(!visible);
        _undo = () => ref.read(privateModeProvider.notifier).set(!previous);
        return {
          'changed': true,
          'amounts_visible': visible,
          'undo_available': true,
        };
      case 'set_app_lock':
        final enabled = _bool(arguments, 'enabled');
        await ref.read(appLockEnabledProvider.notifier).setEnabled(enabled);
        _undo = null;
        return {'changed': true, 'app_lock_enabled': enabled};
      case 'set_notification_capture':
        final enabled = _bool(arguments, 'enabled');
        await ref
            .read(notificationIngestionProvider.notifier)
            .setEnabled(enabled);
        _undo = null;
        return {'changed': true, 'notification_capture_enabled': enabled};
      case 'set_currency':
        final previous = ref.read(preferredCurrencyProvider);
        final currency = arguments['currency']?.toString().toUpperCase();
        const allowed = {'INR', 'USD', 'EUR', 'GBP', 'SGD', 'AED'};
        if (!allowed.contains(currency)) {
          throw ArgumentError('unsupported currency');
        }
        await ref
            .read(preferredCurrencyProvider.notifier)
            .setCurrency(currency!);
        _undo = () =>
            ref.read(preferredCurrencyProvider.notifier).setCurrency(previous);
        return {
          'changed': true,
          'preferred_currency': currency,
          'undo_available': true,
        };
      case 'set_sync_lookback':
        final previous = ref.read(syncLookbackProvider);
        final days = (arguments['days'] as num?)?.toInt();
        if (days == null || days < 7 || days > 180) {
          throw ArgumentError('days must be between 7 and 180');
        }
        await _persistLookback(days);
        _undo = () => _persistLookback(previous);
        return {
          'changed': true,
          'sync_lookback_days': days,
          'undo_available': true,
        };
      default:
        throw ArgumentError('unknown app tool');
    }
  }

  bool _bool(Map<String, dynamic> values, String key) {
    final value = values[key];
    if (value is! bool) throw ArgumentError('$key must be boolean');
    return value;
  }

  Future<void> _persistTheme(ThemeMode mode) async {
    ref.read(themeModeProvider.notifier).setThemeMode(mode);
    await ref
        .read(secureStorageProvider)
        .write(key: 'theme_mode', value: mode.toString());
  }

  Future<void> _persistLookback(int days) async {
    ref.read(syncLookbackProvider.notifier).setDays(days);
    await ref
        .read(secureStorageProvider)
        .write(key: 'sync_lookback_days', value: '$days');
  }
}
