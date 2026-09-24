import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../shared/widgets/cover_gradient.dart' show coverGradient;
import '../../state/providers.dart';

/// 抽帧用的通道，实现在 android/.../MainActivity.kt。
const MethodChannel _thumbChannel = MethodChannel('xvideo/video');

/// 缩略图存放的子目录（App 私有目录下）。
const String kThumbDirName = 'xvideo_thumbs';

/// 抽出来的缩略图宽度上限：卡片上那块够用就行，用不着原尺寸。
const int kThumbMaxWidth = 720;

/// 本机视频的缩略图：抽一帧存成 jpg 放在 App 私有目录，下次直接读文件。
///
/// 只有本机视频有缩略图。网络链接要联网抓一帧，列表里会卡、也费流量，
/// 家长拍板不做，链接继续用渐变占位块。
class VideoThumbCache {
  /// [dirProvider] 只在测试里传，真机上缩略图放在 App 私有目录下。
  VideoThumbCache({Future<Directory> Function()? dirProvider})
      : _dirProvider = dirProvider ?? appThumbDir;

  final Future<Directory> Function() _dirProvider;

  final Map<String, File> _files = {};
  final Map<String, Future<File?>> _running = {};
  // 抽过但没抽出来的（文件坏了、根本不是视频），这一轮别再反复试。
  final Set<String> _failed = {};
  Directory? _dir;

  /// 缩略图文件：有现成的就给，没有就抽一帧存下来。抽不出来就是 null。
  Future<File?> ensure(VideoItem video) {
    if (!video.isLocal) return Future.value(null);
    final known = _files[video.id];
    if (known != null) return Future.value(known);
    if (_failed.contains(video.id)) return Future.value(null);
    // 列表滚动时同一个视频会被重新建出来，别同时起好几个抽帧任务。
    return _running[video.id] ??= _extract(video);
  }

  Future<File?> _extract(VideoItem video) async {
    try {
      final bytes = await _thumbChannel.invokeMethod<Uint8List>(
        'thumbnail',
        {'path': video.source, 'maxWidth': kThumbMaxWidth},
      );
      if (bytes == null || bytes.isEmpty) return _giveUp(video.id);
      final dir = await _thumbDir();
      final file = File('${dir.path}/${video.id}.jpg');
      await file.writeAsBytes(bytes, flush: true);
      return _files[video.id] = file;
    } catch (_) {
      // 通道没接（测试、桌面）、目录建不出来、盘写不进去……都当没有缩略图。
      return _giveUp(video.id);
    } finally {
      _running.remove(video.id);
    }
  }

  File? _giveUp(String videoId) {
    _failed.add(videoId);
    return null;
  }

  /// 视频从库里删掉时顺手清掉缩略图，别留下孤儿文件。
  Future<void> remove(String videoId) async {
    _files.remove(videoId);
    _failed.remove(videoId);
    _running.remove(videoId);
    // 一张缩略图都没生成过，那就没有目录、也没有文件要删。
    final dir = _dir;
    if (dir == null) return;
    try {
      final file = File('${dir.path}/$videoId.jpg');
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // 删不掉不影响「从列表里移除」。
    }
  }

  Future<Directory> _thumbDir() async => _dir ??= await _dirProvider();
}

/// 缩略图的默认存放位置：App 私有目录下的 [kThumbDirName]。
Future<Directory> appThumbDir() async {
  final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/$kThumbDirName');
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

final videoThumbCacheProvider =
    Provider<VideoThumbCache>((ref) => VideoThumbCache());

/// 视频缩略图：本机视频抽一帧显示，抽不到（或本来就是链接）就用渐变占位块。
///
/// 尺寸由调用方给死：抽帧、解码都有开销，让图片自己撑开反而会走形。
class VideoThumb extends ConsumerStatefulWidget {
  const VideoThumb({
    super.key,
    required this.video,
    required this.width,
    required this.height,
    this.radius = 12,
    this.placeholderIcon = Icons.play_arrow_rounded,
    this.playBadge = false,
    this.badgeIcon,
  });

  final VideoItem video;
  final double width;
  final double height;
  final double radius;

  /// 没有缩略图时中间画什么图标。
  final IconData placeholderIcon;

  /// 有真的缩略图时，中间还盖不盖一个播放按钮。
  final bool playBadge;

  /// 有真的缩略图时，左下角那个小角标（本机 / 链接）。不传就不画。
  final IconData? badgeIcon;

  @override
  ConsumerState<VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends ConsumerState<VideoThumb> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VideoThumb old) {
    super.didUpdateWidget(old);
    // 列表复用同一个 State 换了个视频时，不能把上一个的缩略图留下来。
    if (old.video.id != widget.video.id) {
      _file = null;
      _load();
    }
  }

  Future<void> _load() async {
    final file = await ref.read(videoThumbCacheProvider).ensure(widget.video);
    if (!mounted || file == null) return;
    setState(() => _file = file);
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: file == null ? _placeholder() : _frame(file),
      ),
    );
  }

  Widget _placeholder() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: coverGradient(widget.video.id),
          ),
        ),
        child: Center(
          child: Icon(
            widget.placeholderIcon,
            color: Colors.white,
            size: _scale(0.52, max: 30),
          ),
        ),
      );

  Widget _frame(File file) {
    final badge = widget.badgeIcon;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          file,
          fit: BoxFit.cover,
          // 缩略图按显示大小解码，别把 480px 的原图整张留在图片缓存里。
          cacheWidth: (widget.width * MediaQuery.devicePixelRatioOf(context))
              .round(),
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
        if (widget.playBadge) Center(child: _playCircle()),
        if (badge != null)
          Positioned(left: 3, bottom: 3, child: _kindBadge(badge)),
      ],
    );
  }

  Widget _playCircle() {
    final side = _scale(0.58, max: 40);
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.38),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.play_arrow_rounded,
          color: Colors.white, size: side * 0.62),
    );
  }

  Widget _kindBadge(IconData icon) {
    final side = _scale(0.4, max: 20);
    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(side * 0.3),
      ),
      child: Icon(icon, color: Colors.white, size: side * 0.68),
    );
  }

  /// 图标大小跟着缩略图高度走，手机和平板上都不会显得突兀。
  double _scale(double ratio, {required double max}) =>
      (widget.height * ratio).clamp(10.0, max);
}
