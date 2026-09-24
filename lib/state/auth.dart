import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../data/models.dart';
import 'prefs.dart';

/// 基于本地存储的「假认证」：本地注册 / 登录并保持会话。
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final p = ref.watch(prefsProvider);
    try {
      final raw = p.getString(kSessionKey);
      if (raw == null) return const AuthState();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const AuthState();
      return AuthState(user: User.fromJson(decoded));
    } catch (_) {
      return const AuthState();
    }
  }

  /// 返回 null 表示成功，否则返回错误提示文案。
  Future<String?> login(String email, String password) async {
    final key = email.trim().toLowerCase();
    if (key.isEmpty || password.isEmpty) return '请输入邮箱和密码';
    final rec = _allUsers()[key];
    if (rec == null) return '该邮箱尚未注册，请先注册';
    if (rec['password'] != password) return '密码不正确';
    final user = User(
      id: rec['id'] as String,
      name: rec['name'] as String,
      email: key,
    );
    await _storeSession(user);
    return null;
  }

  Future<String?> register(String name, String email, String password) async {
    final key = email.trim().toLowerCase();
    if (name.trim().isEmpty) return '请填写昵称';
    if (key.isEmpty || password.isEmpty) return '请输入邮箱和密码';
    if (password.length < 4) return '密码至少 4 位';
    final users = _allUsers();
    if (users.containsKey(key)) return '该邮箱已注册，请直接登录';
    users[key] = {
      'id': 'u${DateTime.now().millisecondsSinceEpoch}',
      'name': name.trim(),
      'password': password,
    };
    await ref.read(prefsProvider).setString(kUsersKey, jsonEncode(users));
    final user = User(
      id: users[key]!['id'] as String,
      name: users[key]!['name'] as String,
      email: key,
    );
    await _storeSession(user);
    return null;
  }

  Future<void> logout() async {
    await ref.read(prefsProvider).remove(kSessionKey);
    state = const AuthState();
  }

  Future<void> _storeSession(User user) async {
    await ref.read(prefsProvider).setString(kSessionKey, jsonEncode(user.toJson()));
    state = AuthState(user: user);
  }

  Map<String, dynamic> _allUsers() {
    final raw = ref.read(prefsProvider).getString(kUsersKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
