import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import 'prefs.dart';

/// 播放页手势控制的开关（「我的 → 偏好设置」里改）。
class TouchControlController extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(prefsProvider).getBool(kVideoTouchControlKey) ?? false;

  void setEnabled(bool value) {
    state = value;
    ref.read(prefsProvider).setBool(kVideoTouchControlKey, value);
  }
}

final touchControlProvider =
    NotifierProvider<TouchControlController, bool>(TouchControlController.new);
