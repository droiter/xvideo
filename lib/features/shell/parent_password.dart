import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../state/providers.dart';

/// 家长密码：全机一份、落盘。分类列表里的「隐藏视频 / 调整顺序」用它拦一道 ——
/// 孩子猜不出来就动不了这些设置。没改过就是 [kDefaultParentPassword]。
class ParentPasswordController extends Notifier<String> {
  @override
  String build() {
    final raw = ref.read(prefsProvider).getString(kParentPasswordKey);
    return (raw == null || raw.isEmpty) ? kDefaultParentPassword : raw;
  }

  Future<void> set(String value) async {
    state = value;
    await ref.read(prefsProvider).setString(kParentPasswordKey, value);
  }
}

final parentPasswordProvider =
    NotifierProvider<ParentPasswordController, String>(
        ParentPasswordController.new);

/// 弹一个「输入家长密码」的框：输对返回 true，取消（或点掉）返回 false。
///
/// 输错不清空框、也不关框，就地提示「密码不对」让孩子/家长重来 ——
/// 家长手抖打错一位不该从头再走一遍流程。
Future<bool> askParentPassword(
  BuildContext context, {
  required String title,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _ParentPasswordDialog(title: title),
  );
  return ok ?? false;
}

class _ParentPasswordDialog extends ConsumerStatefulWidget {
  const _ParentPasswordDialog({required this.title});

  final String title;

  @override
  ConsumerState<_ParentPasswordDialog> createState() =>
      _ParentPasswordDialogState();
}

class _ParentPasswordDialogState extends ConsumerState<_ParentPasswordDialog> {
  final _input = TextEditingController();
  bool _wrong = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    if (_input.text == ref.read(parentPasswordProvider)) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _wrong = true;
      _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      scrollable: true,
      icon: Icon(Icons.lock_outline_rounded, color: scheme.primary),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('请让家长输入家长密码',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('parent-password-input'),
            controller: _input,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 8,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: '家长密码',
              counterText: '',
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _wrong ? '密码不对' : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('parent-password-ok'),
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 「我的 → 偏好设置 → 家长密码」：改密码要先输一遍现在的，省得孩子顺手改掉。
Future<void> showChangeParentPassword(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _ChangeParentPasswordDialog(),
    );

class _ChangeParentPasswordDialog extends ConsumerStatefulWidget {
  const _ChangeParentPasswordDialog();

  @override
  ConsumerState<_ChangeParentPasswordDialog> createState() =>
      _ChangeParentPasswordDialogState();
}

class _ChangeParentPasswordDialogState
    extends ConsumerState<_ChangeParentPasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_current.text != ref.read(parentPasswordProvider)) {
      setState(() => _error = '当前密码不对');
      return;
    }
    if (_next.text.length < kMinParentPasswordLength) {
      setState(() => _error = '新密码至少 $kMinParentPasswordLength 位');
      return;
    }
    await ref.read(parentPasswordProvider.notifier).set(_next.text);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('家长密码已更新'),
        duration: Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      scrollable: true,
      icon: Icon(Icons.password_rounded, color: scheme.primary),
      title: const Text('家长密码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('在分类列表里隐藏视频、调整顺序时要输它。缺省是 '
              '$kDefaultParentPassword，建议家长改成自己的。',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          _field(_current, '当前密码', const ValueKey('parent-password-old')),
          const SizedBox(height: 10),
          _field(_next, '新密码（至少 $kMinParentPasswordLength 位）',
              const ValueKey('parent-password-new')),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(fontSize: 12.5, color: scheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('parent-password-save'),
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, Key key) => TextField(
        key: key,
        controller: c,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 8,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );
}
