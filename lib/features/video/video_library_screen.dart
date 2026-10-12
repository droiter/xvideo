import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/empty_hint.dart';
import '../../shared/widgets/cover_gradient.dart' show coverGradient;
import '../../state/providers.dart';
import 'video_category_screen.dart';

/// 「看视频」选项卡：展示「我的」里建好的视频分类，点进去看分类下的视频。
class VideoLibraryScreen extends ConsumerWidget {
  const VideoLibraryScreen({super.key, required this.onOpenManage});

  /// 视频为空时跳到「我的」去添加。
  final VoidCallback onOpenManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(videoLibraryProvider);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          const Text('看视频',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            lib.isEmpty
                ? '视频分类在「我的 → 我的视频」里添加'
                // 家长藏起来的那些不报数：孩子连数都对不上，才看不出被收走了。
                : '共 ${lib.categories.length} 个分类 · ${lib.visibleCount} 个视频',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (lib.isEmpty)
            Column(
              children: [
                const EmptyHint(
                  icon: Icons.video_library_outlined,
                  text: '还没有视频',
                  detail: '去「我的 → 我的视频」新建一个分类，再往里添视频',
                ),
                FilledButton.icon(
                  onPressed: onOpenManage,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('去添加视频'),
                ),
              ],
            )
          else
            _grid(context, ref),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(videoLibraryProvider).categories;
    // 固定卡片高度（而不是宽高比）：窄屏上两行分类名也不会把卡片撑破。
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisExtent: 134,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (context, i) => _CategoryCard(
        id: categories[i].id,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoCategoryScreen(categoryId: categories[i].id),
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  const _CategoryCard({required this.id, required this.onTap});

  final String id;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 按 id 取，删除分类后卡片会自动消失。
    final category =
        ref.watch(videoLibraryProvider.select((lib) => lib.byId(id)));
    if (category == null) return const SizedBox.shrink();
    final colors = coverGradient(id);

    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(18),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.play_circle_fill_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.white.withOpacity(0.9)),
                  ],
                ),
                const Spacer(),
                Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  // 同上：卡片上也只算孩子看得到的。
                  '${category.visibleVideos.length} 个视频',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
