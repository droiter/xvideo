import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/empty_hint.dart';
import '../../state/providers.dart';
import '../shell/parent_password.dart';
import 'video_player_screen.dart';
import 'video_thumbnail.dart';

/// 某个分类下的视频列表，点一个就播。
class VideoCategoryScreen extends ConsumerStatefulWidget {
  const VideoCategoryScreen({
    super.key,
    required this.categoryId,
    this.onOpenManage,
  });

  final String categoryId;

  /// 分类里还没视频时，退回「我的」去添加。
  final VoidCallback? onOpenManage;

  @override
  ConsumerState<VideoCategoryScreen> createState() =>
      _VideoCategoryScreenState();
}

class _VideoCategoryScreenState extends ConsumerState<VideoCategoryScreen> {
  /// 有视频锁着的时候才转：卡片上的「还剩几分钟」要跟着走，到点了也得自己解锁。
  Timer? _ticker;

  /// 家长模式：输过家长密码才打开，这期间卡片右上角多一个「⋮」可以
  /// 隐藏 / 放出、往前排 / 往后排 / 置顶 / 置尾。退出这个页面就自动关掉。
  bool _parentMode = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker(bool anyLocked) {
    if (anyLocked == (_ticker != null)) return;
    if (anyLocked) {
      _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
        if (!mounted) return;
        ref.read(viewLimitProvider.notifier).pruneExpired();
        setState(() {});
      });
    } else {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = ref.watch(
        videoLibraryProvider.select((lib) => lib.byId(widget.categoryId)));
    // 防反复观看：连着看够 N 遍的视频会锁住 M 分钟，这段时间里缩略图变灰、点不开。
    final limit = ref.watch(viewLimitSettingsProvider);
    final records = ref.watch(viewLimitProvider);
    final now = ref.read(nowProvider)();
    _syncTicker(limit.enabled && records.values.any((r) => r.lockedAt(now)));
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

    // 孩子看到的是「家长没藏起来」的那些；家长模式里连藏起来的一起摆出来。
    final videos =
        _parentMode ? category.videos : category.visibleVideos;
    return Scaffold(
      appBar: AppBar(
        title: Text(category.name),
        backgroundColor: _parentMode ? scheme.primaryContainer : null,
        actions: [
          TextButton.icon(
            key: const ValueKey('parent-mode-button'),
            onPressed: _toggleParentMode,
            style: TextButton.styleFrom(
              foregroundColor:
                  _parentMode ? scheme.onPrimaryContainer : scheme.primary,
            ),
            icon: Icon(_parentMode
                ? Icons.check_rounded
                : Icons.lock_outline_rounded),
            label: Text(_parentMode ? '完成' : '家长设置'),
          ),
        ],
      ),
      body: videos.isEmpty
          ? _emptyBody(category)
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
                    final record = records[v.id];
                    final locked =
                        limit.enabled && (record?.lockedAt(now) ?? false);
                    final minutes =
                        locked ? record!.minutesLeft(now) : 0;
                    return _VideoTile(
                      index: i + 1,
                      video: v,
                      locked: locked,
                      hidden: v.hidden,
                      views: record?.count ?? 0,
                      minutesLeft: minutes,
                      // 家长模式下来点卡片是「调整」，不是「播放」。
                      onTap: _parentMode
                          ? () => _openArrangeSheet(v)
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => VideoPlayerScreen(video: v),
                                ),
                              ),
                      onLockedTap: () => _hintLocked(context, v, record!.count,
                          minutes, limit.lockMinutes),
                      onArrange:
                          _parentMode ? () => _openArrangeSheet(v) : null,
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
                _parentMode
                    ? '家长模式 · 共 ${category.videos.length} 个视频'
                        '${category.hiddenCount > 0 ? '（已隐藏 ${category.hiddenCount} 个）' : ''}'
                        ' · 点卡片上的「⋮」调整'
                    : '共 ${videos.length} 个视频 · 点一下就能播放，随时按返回键退出',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
    );
  }

  /// 分类里没东西可看时：真没视频就给「去添加」，全被家长收起来了就只说一声。
  Widget _emptyBody(VideoCategory category) {
    if (category.videos.isNotEmpty) {
      return const Center(
        child: EmptyHint(
          icon: Icons.visibility_off_outlined,
          text: '这个分类里暂时没有视频',
          detail: '家长把里面的视频都收起来了',
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const EmptyHint(
            icon: Icons.movie_creation_outlined,
            text: '这个分类里还没有视频',
            detail: '去「我的 → 我的视频」给它添几个视频吧',
          ),
          if (widget.onOpenManage != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenManage!();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('去添加视频'),
            ),
        ],
      ),
    );
  }

  /// 点「家长设置」：还没进家长模式就先要密码，已经进来了就是「完成」退出。
  Future<void> _toggleParentMode() async {
    if (_parentMode) {
      setState(() => _parentMode = false);
      return;
    }
    final ok = await askParentPassword(context, title: '家长设置');
    if (!ok || !mounted) return;
    setState(() => _parentMode = true);
    _toast('家长模式：点视频卡片上的「⋮」可以隐藏、调整顺序');
  }

  /// 家长模式下调一个视频：点卡片、点「⋮」都弹这个菜单。
  ///
  /// 每选一项就关掉菜单、改完再弹一句提示 —— 顺序是在卡片列表上变的，
  /// 菜单盖着的时候看不见效果，留在原地反而不知道挪没挪动。
  Future<void> _openArrangeSheet(VideoItem video) async {
    final category = ref.read(videoLibraryProvider).byId(widget.categoryId);
    if (category == null) return;
    final index = category.videos.indexWhere((v) => v.id == video.id);
    if (index < 0) return;
    final last = category.videos.length - 1;
    final hidden = category.videos[index].hidden;

    final picked = await showModalBottomSheet<_Arrange>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        // 横屏 / 矮屏上这几行放不下，让它滚，别撑破。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('第 ${index + 1} 个 · 共 ${category.videos.length} 个'
                    '${hidden ? ' · 已隐藏' : ''}'),
              ),
              const Divider(height: 1),
              _arrangeItem(
                ctx,
                _Arrange.hide,
                hidden ? '放出来给孩子看' : '隐藏（孩子看不到）',
                hidden
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
              _arrangeItem(ctx, _Arrange.up, '向前排', Icons.arrow_upward_rounded,
                  enabled: index > 0),
              _arrangeItem(ctx, _Arrange.down, '向后排',
                  Icons.arrow_downward_rounded, enabled: index < last),
              _arrangeItem(ctx, _Arrange.top, '置顶',
                  Icons.vertical_align_top_rounded, enabled: index > 0),
              _arrangeItem(ctx, _Arrange.bottom, '置尾',
                  Icons.vertical_align_bottom_rounded, enabled: index < last),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final lib = ref.read(videoLibraryProvider.notifier);
    switch (picked) {
      case _Arrange.hide:
        await lib.setVideoHidden(widget.categoryId, video.id, hidden: !hidden);
      case _Arrange.up:
        await lib.moveVideo(widget.categoryId, video.id, VideoMove.up);
      case _Arrange.down:
        await lib.moveVideo(widget.categoryId, video.id, VideoMove.down);
      case _Arrange.top:
        await lib.moveVideo(widget.categoryId, video.id, VideoMove.top);
      case _Arrange.bottom:
        await lib.moveVideo(widget.categoryId, video.id, VideoMove.bottom);
    }
    if (!mounted) return;
    _toast(_doneText(picked, video.title, hidden));
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
      ));
  }

  /// 锁着的视频被点到时，说清楚为什么不能看、还要等多久。
  void _hintLocked(BuildContext context, VideoItem video, int views,
      int minutesLeft, int lockMinutes) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('「${video.title}」连着看了 $views 遍，'
            '再过 $minutesLeft 分钟就能看（每次看完歇 $lockMinutes 分钟）'),
        duration: const Duration(seconds: 4),
      ));
  }
}

/// 家长模式里「⋮」菜单上的几件事。
enum _Arrange { hide, up, down, top, bottom }

Widget _arrangeItem(
  BuildContext ctx,
  _Arrange what,
  String label,
  IconData icon, {
  bool enabled = true,
}) =>
    ListTile(
      enabled: enabled,
      leading: Icon(icon),
      title: Text(label),
      // 已经在头 / 尾的那些项点不动，也就没有 onTap。
      onTap: enabled ? () => Navigator.pop(ctx, what) : null,
    );

/// 改完之后那句提示。[wasHidden] 是动手**之前**的状态。
String _doneText(_Arrange what, String title, bool wasHidden) =>
    switch (what) {
      _Arrange.hide =>
        wasHidden ? '「$title」放出来了，孩子能看到' : '「$title」已隐藏，孩子看不到了',
      _Arrange.up => '「$title」向前排了一位',
      _Arrange.down => '「$title」向后排了一位',
      _Arrange.top => '「$title」已置顶',
      _Arrange.bottom => '「$title」已置尾',
    };

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
    this.locked = false,
    this.hidden = false,
    this.views = 0,
    this.minutesLeft = 0,
    this.onLockedTap,
    this.onArrange,
  });

  final int index;
  final VideoItem video;
  final VoidCallback onTap;

  /// 连着看太多遍了、这会儿正锁着：整张卡变灰，点了不播。
  final bool locked;

  /// 家长把这个视频收起来了：整张卡褪淡、标一句「已隐藏」。
  final bool hidden;

  /// 已经连着看了几遍，锁着的时候写在卡片上。
  final int views;

  /// 还要等几分钟才解锁。
  final int minutesLeft;

  /// 点灰卡时给一句解释（点不进去）。
  final VoidCallback? onLockedTap;

  /// 家长模式里才有：卡片右上角的「⋮」，点开调整菜单。
  final VoidCallback? onArrange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faded = scheme.onSurfaceVariant;
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(16),
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: locked && onArrange == null ? onLockedTap : onTap,
        child: Stack(
          children: [
            // 收起来的整张褪淡，但右上角那颗「⋮」要留着看得清、点得着。
            Opacity(
              opacity: hidden ? 0.45 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    // 缩略图按上面算好的尺寸铺满整块卡片宽度，抽帧、解码都要一个准数。
                    child: LayoutBuilder(
                      builder: (context, c) => Stack(
                        fit: StackFit.expand,
                        children: [
                          _desaturate(
                            VideoThumb(
                              video: video,
                              width: c.maxWidth,
                              height: c.maxHeight,
                              radius: 0,
                              playBadge: true,
                            ),
                          ),
                          if (locked) _lockVeil(c.maxHeight),
                        ],
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
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.18,
                              fontWeight: FontWeight.w700,
                              color: locked ? faded : null,
                            ),
                          ),
                          Row(
                            children: [
                              // 窄屏上「已看 15 遍」和右边的角标会挤，让左边先让步。
                              Flexible(
                                child: Text(
                                  locked ? '已看 $views 遍' : '第 $index 个',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(fontSize: 11.5, color: faded),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: locked || hidden
                                      ? scheme.surfaceContainerHighest
                                      : scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  locked
                                      ? '$minutesLeft 分钟后'
                                      : hidden
                                          ? '已隐藏'
                                          : (video.isLocal ? '本机' : '网络'),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: locked || hidden
                                          ? faded
                                          : scheme.onPrimaryContainer),
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
            if (onArrange != null)
              Positioned(
                top: 6,
                right: 6,
                child: _ArrangeButton(
                  key: ValueKey('arrange-${video.id}'),
                  onTap: onArrange!,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 锁着的时候整个缩略图褪成灰的，一眼就能看出「这个现在不能看」。
  Widget _desaturate(Widget child) =>
      locked ? ColorFiltered(colorFilter: _kGreyscale, child: child) : child;

  /// 缩略图上盖一层：一把锁 + 还剩多久。
  Widget _lockVeil(double height) {
    final side = (height * 0.34).clamp(22.0, 46.0);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.38),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_clock_rounded, color: Colors.white, size: side),
            const SizedBox(height: 6),
            Text(
              '歇 $minutesLeft 分钟',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 家长模式里卡片右上角那颗「⋮」。
class _ArrangeButton extends StatelessWidget {
  const _ArrangeButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const SizedBox(
            width: 34,
            height: 34,
            child:
                Icon(Icons.more_vert_rounded, color: Colors.white, size: 20),
          ),
        ),
      );
}

/// 去色用的矩阵（按亮度把 RGB 拉成同一档灰）。
const ColorFilter _kGreyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);
