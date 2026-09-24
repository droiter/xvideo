import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/main_shell.dart';
import 'state/providers.dart';

class XVideoApp extends ConsumerWidget {
  const XVideoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(themeControllerProvider);
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: const RootGate(),
    );
  }
}

/// 看完引导页就直接进主界面：没有账号也能用，账号到「我的」里随时登录或注册。
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seenOnboarding = ref.watch(onboardingControllerProvider);
    if (!seenOnboarding) return const OnboardingScreen();
    return const MainShell();
  }
}
