import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/empty_hint.dart';
import '../../state/providers.dart';
import 'video_player_screen.dart';
import 'video_thumbnail.dart';

/// 某个分类下的视频列表，点一个就播。
class VideoCategoryScreen extends ConsumerWidget {
  const VideoCategoryScreen({
    super.key,
    required this.categoryId,
    this.onOpenManage,
  });

  final String categoryId;

  /// 分类里还没视频时，退回「我的」去添加。
  final VoidCallback? onOpenManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category =
        ref.watch(videoLibraryProvider.select((lib) => lib.byId(categoryId)));
    final scheme = Theme.of(context).colorScheme;

    if (category == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('视频')),
        body: const EmptyHint(
          icon: Icons.delete_outline_rounded,
          text: '这个分类已经不在了',
          detail: '可能刚在「我的」里被删掉了',
        ),
      );
    }

    final videos = category.videos;
    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      body: videos.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EmptyHint(
                    icon: Icons.movie_creation_outlined,
                    text: '这个分类里还没有视频',
                    detail: '去「我的 → 我的视频」给它添几个视频吧',
                  ),
                  if (onOpenManage != null)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onOpenManage!();
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('去添加视频'),
                    ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: videos.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _columns(constraints.maxWidth),
                    mainAxisSpacing: _kGap,
                    crossAxisSpacing: _kGap,
                    // 缩略图占满卡片宽度、按 16:9 定高，底下留出固定的文字区，
                    // 这样每张卡都填得满满当当，不会空一块。
                    mainAxisExtent: _tileWidth(constraints.maxWidth) * 9 / 16 +
                        _kTileTextHeight,
                  ),
                  itemBuilder: (context, i) {
                    final v = videos[i];
                    return _VideoTile(
                      index: i + 1,
                      video: v,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(video: v),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
      bottomNavigationBar: videos.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: Text(
                '共 ${videos.length} 个视频 · 点一下就能播放，随时按返回键退出',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
    );
  }
}

/// 卡片之间的横竖间距。
const double _kGap = 14;

/// 卡片里缩略图下面那块的高度：两行标题 + 一行「第几个」。
const double _kTileTextHeight = 74;

/// 每张卡片的宽度希望在 280 上下：手机上一行两个，平板上三到四个。
const double _kMinTileWidth = 280;

/// 最多排几列，屏幕再宽也把方块留得大大的。
const int _kMaxColumns = 4;

int _columns(double available) {
  final count = (available / (_kMinTileWidth + _kGap)).ceil();
  return count.clamp(1, _kMaxColumns);
}

double _tileWidth(double available) {
  final count = _columns(available);
  return (available - _kGap * (count - 1)) / count;
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.index,
    required this.video,
    required this.onTap,
  });

  final int index;
  final VideoItem video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(16),
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // 缩略图按上面算好的尺寸铺满整块卡片宽度，抽帧、解码都要一个准数。
              child: LayoutBuilder(
                builder: (context, c) => VideoThumb(
                  video: video,
                  width: c.maxWidth,
                  height: c.maxHeight,
                  radius: 0,
                  playBadge: true,
                ),
              ),
            ),
            SizedBox(
              height: _kTileTextHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Row(
                      children: [
                        Text('第 $index 个',
                            style: TextStyle(
                                fontSize: 11.5, color: scheme.onSurfaceVariant)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            video.isLocal ? '本机' : '网络',
                            style: TextStyle(
                                fontSize: 11, color: scheme.onPrimaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
