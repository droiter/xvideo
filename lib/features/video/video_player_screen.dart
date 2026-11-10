import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants.dart';
import '../../state/providers.dart';

/// 视频播放页。
///
/// 这里**不做任何返回拦截**：按返回键随时退回到上一页，
/// 不弹家长验证，也不受播放进度影响。放完则自动退回视频列表，
/// 除非打开了控制条上的「循环播放」——那就从头再来一遍。
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.video,
    this.playlist = const [],
  });

  final VideoItem video;

  /// 同一个列表里的全部视频（按显示顺序）。
  ///
  /// 传进来才能在开着手势控制时左右划换片；不传就只播 [video] 一个。
  final List<VideoItem> playlist;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  String? _error;

  /// 已经因为播完退回去过了，别再退第二次。
  bool _leftAfterEnd = false;

  /// 循环播放开关，跟着上一次的选择走。
  bool _loop = false;

  /// 静音开关，也跟着上一次的选择走。
  bool _muted = false;

  /// 点画面 / 左右划这套手势开不开（「我的 → 偏好设置」里改）。
  bool _touchControl = false;

  /// 这一轮播完已经绕回去过了；等画面真的重新走起来再放行下一次。
  bool _restartedLoop = false;

  late final SharedPreferences _prefs = ref.read(prefsProvider);

  /// 上次落盘的位置（毫秒），用来避免每 500 毫秒都写一遍。
  int _lastSavedMs = 0;

  /// 当前播的是 [VideoPlayerScreen.playlist] 里的第几个；
  /// 没传 playlist 时就只有自己一个。
  late final List<VideoItem> _playlist;
  late int _index;

  /// 快速连划时，把上一轮还没 init 完的加载作废。
  int _loadToken = 0;

  /// 这一下横向拖了多远（右正左负）。
  double _dragDx = 0;

  VideoItem get _video => _playlist[_index];

  String get _posKey => '$kVideoPositionPrefix${_video.id}';

  @override
  void initState() {
    super.initState();
    final i = widget.playlist.indexWhere((v) => v.id == widget.video.id);
    _playlist = i >= 0 ? widget.playlist : [widget.video];
    _index = i >= 0 ? i : 0;
    _loop = _prefs.getBool(kVideoLoopKey) ?? false;
    _muted = _prefs.getBool(kVideoMuteKey) ?? false;
    _touchControl = ref.read(touchControlProvider);
    // 防反复观看：打开播放页就算看过一遍。记到下一帧再动手——这一帧还在建
    // 新路由，直接改 provider 会把底下的视频列表标记成要重建。
    _recordView(_video.id);
    _init();
  }

  void _recordView(String videoId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(viewLimitProvider.notifier).recordView(videoId);
    });
  }

  Future<void> _init() async {
    final token = ++_loadToken;
    final item = _video;
    final controller = item.isLocal
        ? VideoPlayerController.file(File(item.source))
        : VideoPlayerController.networkUrl(Uri.parse(item.source));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || token != _loadToken) return;
      // 循环交给播放器自己做：到头不回退、不黑一下。
      await controller.setLooping(_loop);
      if (!mounted || token != _loadToken) return;
      await controller.setVolume(_muted ? 0 : 1);
      if (!mounted || token != _loadToken) return;
      await _resumeFromLastStop(controller);
      if (!mounted || token != _loadToken) return;
      setState(() {});
      // 挂在播放器上而不是写在 build 里：build 期间动导航栈会直接断言失败。
      controller.addListener(() => _onPlaybackChanged(controller));
      await controller.play();
    } catch (_) {
      if (!mounted || token != _loadToken) return;
      setState(() => _error = item.isLocal
          ? '这个视频文件打不开了\n可能已被删除，请重新添加'
          : '视频暂时无法播放\n请检查网络后重试');
    }
  }

  /// 重试前先把失败的播放器丢掉，避免两份实例同时占着解码器。
  Future<void> _retry() async {
    final old = _controller;
    setState(() {
      _controller = null;
      _error = null;
    });
    await old?.dispose();
    await _init();
  }

  /// 从上次停下的地方接着放。离结尾不到 1 秒的当作看完了，从头来。
  Future<void> _resumeFromLastStop(VideoPlayerController c) async {
    final saved = _prefs.getInt(_posKey) ?? 0;
    _lastSavedMs = saved;
    final total = c.value.duration.inMilliseconds;
    if (saved < kVideoResumeMinMs || total <= 0) return;
    if (saved >= total - 1000) {
      _clearPosition();
      return;
    }
    await c.seekTo(Duration(milliseconds: saved));
  }

  /// 顺手记下看到哪儿了。每 [kVideoResumeSaveStepMs] 写一次就够，
  /// 别跟着播放器每 500 毫秒的进度回调一直写盘。
  void _rememberPosition(VideoPlayerValue v) {
    if (!v.isInitialized) return;
    final ms = v.position.inMilliseconds;
    if (ms < kVideoResumeMinMs) {
      // 刚开头（或者被拖回开头）就不值得记，下次从头看也一样。
      if (_lastSavedMs != 0) {
        _lastSavedMs = 0;
        _prefs.remove(_posKey);
      }
      return;
    }
    if ((ms - _lastSavedMs).abs() < kVideoResumeSaveStepMs) return;
    _lastSavedMs = ms;
    _prefs.setInt(_posKey, ms);
  }

  void _clearPosition() {
    _lastSavedMs = 0;
    _prefs.remove(_posKey);
  }

  /// 放完就退回视频列表；开着循环就从头再来。
  void _onPlaybackChanged(VideoPlayerController c) {
    // 换片时旧播放器还没 dispose 完，它的回调别拿新播放器的状态说事。
    if (!identical(c, _controller) || !mounted || _leftAfterEnd) return;
    if (!c.value.isCompleted) {
      _restartedLoop = false;
      _rememberPosition(c.value);
      return;
    }
    if (_loop) {
      // 一般让播放器自己接上（setLooping），这里兜住那些仍然报「播完」的机型。
      if (_restartedLoop) return;
      _restartedLoop = true;
      _clearPosition();
      c.seekTo(Duration.zero);
      c.play();
      return;
    }
    // 看完了就把位置清掉，下次进这个视频从头放。
    _clearPosition();
    // 先按住声音再退，不然退出去的瞬间还响着。
    c.pause();
    _leftAfterEnd = true;
    Navigator.of(context).maybePop();
  }

  /// 开关循环播放，并记住这次的选择。
  void _toggleLoop() {
    setState(() => _loop = !_loop);
    _controller?.setLooping(_loop);
    _prefs.setBool(kVideoLoopKey, _loop);
  }

  /// 开关静音，并记住这次的选择。
  void _toggleMute() {
    setState(() => _muted = !_muted);
    _controller?.setVolume(_muted ? 0 : 1);
    _prefs.setBool(kVideoMuteKey, _muted);
  }

  /// 点画面：开着手势控制就暂停 / 继续，关着只用来「接着播」。
  void _onTapStage() {
    if (_touchControl) {
      _togglePlay();
      return;
    }
    _resumeByTouch();
  }

  /// 没开手势控制时的老行为：点画面只接着播。
  ///
  /// 播放中碰到画面**不暂停**：小孩看视频手总在屏幕上摸，一按画面就断了；
  /// 要暂停请用下面的控制条。
  void _resumeByTouch() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isPlaying) return;
    if (c.value.isCompleted) c.seekTo(Duration.zero);
    c.play();
  }

  void _onDragStart(DragStartDetails _) => _dragDx = 0;

  void _onDragUpdate(DragUpdateDetails d) => _dragDx += d.delta.dx;

  /// 左划上一个、右划下一个（主人定的方向）。划得太短不算。
  void _onDragEnd(DragEndDetails _) {
    final dx = _dragDx;
    _dragDx = 0;
    if (!_touchControl || dx.abs() < _kSwipeMinDx) return;
    if (dx < 0) {
      _index > 0 ? _goTo(_index - 1) : _toast('已经是第一个视频了');
    } else {
      _index < _playlist.length - 1
          ? _goTo(_index + 1)
          : _toast('已经是最后一个视频了');
    }
  }

  /// 换到列表里的第 [index] 个视频，在这一页里直接换，不另开路由。
  Future<void> _goTo(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    final target = _playlist[index];
    // 锁着的视频跟列表里一样不给看，也不能靠划过去绕开。
    final minutes = ref.read(viewLimitProvider.notifier).minutesLeft(target.id);
    if (minutes > 0) {
      _toast('「${target.title}」还要等 $minutes 分钟才能看');
      return;
    }

    final old = _controller;
    // 先把这一部的位置记下来，再换片。
    _savePosition(old);
    setState(() {
      _index = index;
      _controller = null;
      _error = null;
      _leftAfterEnd = false;
      _restartedLoop = false;
    });
    _lastSavedMs = 0;
    // 旧播放器让它自己回收，不 await：有些平台实现 dispose 的 Future 迟迟
    // 不回来，卡在这儿就换不了片。
    unawaited(old?.dispose());
    if (!mounted) return;
    _recordView(target.id);
    await _init();
  }

  /// 记下当前视频看到哪儿了；刚开头（或已经看完）就不记。
  void _savePosition(VideoPlayerController? c) {
    if (c == null || !c.value.isInitialized || c.value.isCompleted) return;
    final ms = c.value.position.inMilliseconds;
    if (ms < kVideoResumeMinMs) return;
    _prefs.setInt(_posKey, ms);
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  void dispose() {
    // 退出时把停下的地方记下来：没看完的下次接着看，看完了的已经在
    // _onPlaybackChanged 里清掉了。
    _savePosition(_controller);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: _error != null
            ? Center(child: _errorView())
            : (c == null || !c.value.isInitialized)
                ? const Center(child: CircularProgressIndicator())
                : _playerView(c),
      ),
    );
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 56),
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _playerView(VideoPlayerController c) {
    return PlayerStage(
      aspectRatio: c.value.aspectRatio,
      video: VideoPlayer(c),
      // 手势盖在画面那块（含上下黑边）上：控制条里的按钮和进度条照旧归它们自己。
      onTap: _onTapStage,
      onHorizontalDragStart: _touchControl ? _onDragStart : null,
      onHorizontalDragUpdate: _touchControl ? _onDragUpdate : null,
      onHorizontalDragEnd: _touchControl ? _onDragEnd : null,
      // 播放键、进度条、循环、静音都挤在同一行：竖屏视频底下能少占一行高度。
      controls: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: c,
        builder: (context, value, _) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 6, 2),
          child: Row(
            children: [
              IconButton(
                onPressed: _togglePlay,
                tooltip: value.isPlaying ? '暂停' : '播放',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                icon: Icon(
                  value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: _sliderValue(value),
                    onChanged: (v) => c.seekTo(Duration(
                        milliseconds:
                            (v * value.duration.inMilliseconds).round())),
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                  ),
                ),
              ),
              Text(
                '${_fmt(value.position)} / ${_fmt(value.duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 11.5),
              ),
              const SizedBox(width: 4),
              // 开着的时候按钮亮起来，一眼能看出现在是不是在循环 / 静音。
              _controlIcon(
                icon: Icons.repeat_rounded,
                active: _loop,
                tooltip: _loop ? '关闭循环播放' : '循环播放',
                onPressed: _toggleLoop,
              ),
              _controlIcon(
                icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                active: _muted,
                tooltip: _muted ? '取消静音' : '静音',
                onPressed: _toggleMute,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 控制条右边的小圆钮：循环 / 静音共用，亮着表示开着。
  Widget _controlIcon({
    required IconData icon,
    required bool active,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 21,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      icon: Icon(icon, color: active ? Colors.white : Colors.white38),
    );
  }

  double _sliderValue(VideoPlayerValue v) {
    final total = v.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (v.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isCompleted) {
      c.seekTo(Duration.zero);
      c.play();
      return;
    }
    c.value.isPlaying ? c.pause() : c.play();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

/// 左右划至少这么远才算换片（防手抖）。
const double _kSwipeMinDx = 56;

/// 播放画面 + 控制条。
///
/// 画面只吃剩下的高度：竖屏（或平板上的）视频比屏幕还高，早先按宽度撑高的写法
/// 会把控制条顶到 SafeArea 外面去，正好被系统导航条盖住。
class PlayerStage extends StatelessWidget {
  const PlayerStage({
    super.key,
    required this.aspectRatio,
    required this.video,
    required this.controls,
    this.onTap,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
  });

  /// 视频宽高比；拿不到时按 16:9 算。
  final double aspectRatio;
  final Widget video;
  final Widget controls;

  /// 画面那一块的轻点 / 左右划。控制条不在里面，免得跟进度条抢手势。
  final GestureTapCallback? onTap;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onHorizontalDragStart: onHorizontalDragStart,
            onHorizontalDragUpdate: onHorizontalDragUpdate,
            onHorizontalDragEnd: onHorizontalDragEnd,
            child: Center(
              child: AspectRatio(
                aspectRatio: aspectRatio <= 0 ? 16 / 9 : aspectRatio,
                child: video,
              ),
            ),
          ),
        ),
        controls,
      ],
    );
  }
}
