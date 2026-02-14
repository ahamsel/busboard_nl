import 'package:flutter/widgets.dart';

/// Observes app lifecycle to pause/resume polling when backgrounded.
class AppLifecycleObserver extends WidgetsBindingObserver with ChangeNotifier {
  bool _isForegrounded = true;

  bool get isForegrounded => _isForegrounded;

  AppLifecycleObserver() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _isForegrounded;
    _isForegrounded = state == AppLifecycleState.resumed;

    if (wasForeground != _isForegrounded) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
