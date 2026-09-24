import 'package:flutter/foundation.dart';

/// 用户账号。
@immutable
class User {
  const User({required this.id, required this.name, required this.email});

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
      );

  final String id;
  final String name;
  final String email;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}

/// 认证状态。
@immutable
class AuthState {
  const AuthState({this.user});

  final User? user;

  bool get isLoggedIn => user != null;
}
