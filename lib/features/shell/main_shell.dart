import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../profile/profile_screen.dart';
import '../video/video_library_screen.dart';

/// 底部导航主框架：看视频 / 我的。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = kVideoTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          VideoLibraryScreen(onOpenManage: () => _goTab(kProfileTab)),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: _TabBar(index: _index, onSelect: _goTab),
    );
  }

  void _goTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }
}

/// 底部选项卡。「现在在哪一格」只靠高亮表示：当前那格是主色 + 药丸底色。
class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const cells = [
      (Icons.ondemand_video_rounded, '看视频'),
      (Icons.person_outline_rounded, '我的'),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 0.6),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++)
                _TabCell(
                  key: ValueKey('tab-$i'),
                  icon: cells[i].$1,
                  label: cells[i].$2,
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一格选项卡。[selected] 是「现在就在这一格」。
class _TabCell extends StatelessWidget {
  const _TabCell({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 当前这一格垫一层药丸底色，一眼看出现在在哪一格。
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? scheme.primaryContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: selected ? scheme.onPrimaryContainer : color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
