import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在 main() 中通过 overrideWithValue 注入真实的 SharedPreferences。
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider 需要在 runApp 前被覆盖'),
);
