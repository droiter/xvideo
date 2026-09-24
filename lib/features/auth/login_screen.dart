import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../state/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  bool _registerMode = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authControllerProvider.notifier);
    final err = _registerMode
        ? await auth.register(_name.text, _email.text, _password.text)
        : await auth.login(_email.text, _password.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF4F6BFF), Color(0xFF9A5CFF)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(Icons.ondemand_video_rounded,
                          color: Colors.white, size: 40),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(kAppName,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(kAppTagline,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 34),
                  if (_registerMode) ...[
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                          labelText: '昵称', prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        labelText: '邮箱', prefixIcon: Icon(Icons.mail_outline)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(color: scheme.error, fontSize: 13)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4))
                        : Text(_registerMode ? '注册并登录' : '登录'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _registerMode = !_registerMode;
                              _error = null;
                            }),
                    child: Text(_registerMode ? '已有账号？去登录' : '还没有账号？立即注册'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
