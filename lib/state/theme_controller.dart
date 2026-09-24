import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import 'prefs.dart';

class ThemeController extends Notifier<bool> {
  @override
  bool build() {
    return ref.watch(prefsProvider).getBool(kDarkModeKey) ?? false;
  }

  void setDark(bool value) {
    state = value;
    ref.read(prefsProvider).setBool(kDarkModeKey, value);
  }
}

final themeControllerProvider =
    NotifierProvider<ThemeController, bool>(ThemeController.new);
