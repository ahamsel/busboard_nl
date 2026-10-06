import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/arrival_alerts/arrival_alert.dart';

/// The one active arrival alert and the rider's last lead time. Uses [SharedPreferencesAsync],
/// which has no cache, so the Android watcher's isolate and the app see each other's writes.
class AlertStore {
  AlertStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;
  static const _alertKey = 'arrival_alert.v1';
  static const _leadKey = 'arrival_alert.lead_minutes';

  Future<ArrivalAlert?> read() async => ArrivalAlert.decode(await _prefs.getString(_alertKey));

  Future<void> write(ArrivalAlert alert) => _prefs.setString(_alertKey, alert.encode());

  Future<void> clear() => _prefs.remove(_alertKey);

  Future<int> lastLead() async {
    final v = await _prefs.getInt(_leadKey);
    return v != null && alertLeadChoices.contains(v) ? v : 5;
  }

  Future<void> saveLead(int minutes) => _prefs.setInt(_leadKey, minutes);
}
