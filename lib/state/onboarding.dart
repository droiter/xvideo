import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import 'prefs.dart';

/// 是否看过引导页。
class OnboardingController extends Notifier<bool> {
  @override
  bool build() {
    return ref.watch(prefsProvider).getBool(kSeenOnboardingKey) ?? false;
  }

  void markSeen() {
    state = true;
    ref.read(prefsProvider).setBool(kSeenOnboardingKey, true);
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, bool>(OnboardingController.new);
