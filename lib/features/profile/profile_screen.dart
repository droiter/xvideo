import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../auth/login_screen.dart';
import '../shell/parent_password.dart';
import '../video/video_manage_screen.dart';

/// 「我的」：账号、视频管理、设置、关于、退出。
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider.select((s) => s.user));
    final dark = ref.watch(themeControllerProvider);
    final limit = ref.watch(viewLimitSettingsProvider);
    final lib = ref.watch(videoLibraryProvider);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          const Text('我的',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (user != null) _userCard(context, user) else _guestCard(context),
          const SizedBox(height: 16),
          const _SectionLabel('视频'),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('我的视频'),
              subtitle: Text(
                lib.isEmpty
                    ? '新建分类，往里面添视频'
                    : '${lib.categories.length} 个分类 · ${lib.totalVideos} 个视频',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VideoManageScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('偏好设置'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('深色模式'),
                  subtitle: const Text('晚上看片不刺眼'),
                  value: dark,
                  onChanged: (v) =>
                      ref.read(themeControllerProvider.notifier).setDark(v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.hourglass_top_rounded),
                  title: const Text('限制反复观看'),
                  subtitle: Text(limit.enabled
                      ? '同一个视频连看 ${limit.maxViews} 遍就锁 ${limit.lockMinutes} 分钟'
                      : '关着：同一个视频想看几遍看几遍'),
                  value: limit.enabled,
                  onChanged: (v) => ref
                      .read(viewLimitSettingsProvider.notifier)
                      .setEnabled(v),
                ),
                if (limit.enabled) ...[
                  ListTile(
                    leading: const Icon(Icons.repeat_rounded),
                    title: const Text('连看几遍就锁住'),
                    trailing: Text('${limit.maxViews} 遍'),
                    onTap: () => _pickSetting(
                      context,
                      title: '连着看几遍就锁住',
                      unit: '遍',
                      options: kViewLimitChoices,
                      current: limit.maxViews,
                      onPicked: (v) => ref
                          .read(viewLimitSettingsProvider.notifier)
                          .setMaxViews(v),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('锁住多久'),
                    trailing: Text('${limit.lockMinutes} 分钟'),
                    onTap: () => _pickSetting(
                      context,
                      title: '锁住多久',
                      unit: '分钟',
                      options: kLockMinuteChoices,
                      current: limit.lockMinutes,
                      onPicked: (v) => ref
                          .read(viewLimitSettingsProvider.notifier)
                          .setLockMinutes(v),
                    ),
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.lock_outline_rounded),
                  title: const Text('家长密码'),
                  subtitle: const Text('隐藏视频、调整顺序时要输它'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showChangeParentPassword(context),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('关于 xVideo'),
                  subtitle: const Text('版本 $kVersion'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showAbout(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (user != null) ...[
            const _SectionLabel('账号'),
            Card(
              margin: EdgeInsets.zero,
              color: scheme.errorContainer.withOpacity(0.35),
              child: ListTile(
                leading: Icon(Icons.logout_rounded, color: scheme.error),
                title: Text('退出登录', style: TextStyle(color: scheme.error)),
                trailing: Icon(Icons.chevron_right_rounded, color: scheme.error),
                onTap: () => _confirmLogout(context, ref),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _userCard(BuildContext context, User user) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kBrand, Color(0xFF9A5CFF)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            child: Text(
              user.name.isNotEmpty ? user.name.substring(0, 1) : '我',
              style: const TextStyle(
                  color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 12.5)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('体验版',
                style: TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  /// 没登录时的入口卡片：不登录也能看视频，想用账号从这里去登录或注册。
  Widget _guestCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: scheme.primaryContainer.withOpacity(0.55),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: kBrand,
          child: Icon(Icons.person_outline_rounded, color: Colors.white),
        ),
        title: const Text('未登录',
            style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('点这里登录或注册账号'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: kAppName,
      applicationVersion: kVersion,
      applicationIcon:
          const Icon(Icons.ondemand_video_rounded, size: 40, color: kBrand),
      children: const [Text(kAppTagline)],
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后不登录也能继续看视频，分类和视频都存在本机。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

/// 让家长从几个常用数字里挑一个：手打数字容易多打或少打，给一排选。
Future<void> _pickSetting(
  BuildContext context, {
  required String title,
  required String unit,
  required List<int> options,
  required int current,
  required ValueChanged<int> onPicked,
}) async {
  final picked = await showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final v in options)
          ListTile(
            title: Text('$v $unit'),
            selected: v == current,
            trailing: v == current ? const Icon(Icons.check_rounded) : null,
            onTap: () => Navigator.pop(ctx, v),
          ),
      ],
    ),
  );
  if (picked != null) onPicked(picked);
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}
