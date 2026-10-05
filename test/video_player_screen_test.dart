import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:xvideo/core/constants.dart';
import 'package:xvideo/features/video/video_category_screen.dart';
import 'package:xvideo/features/video/video_player_screen.dart';
import 'package:xvideo/state/providers.dart';

/// 假的播放器实现。
///
/// 测试环境里没有真的平台通道，`initialize()` 一上来就抛错，播放页永远停在
/// 「播放失败」兜底上——想验证「正在播」时的行为，得自己搭一个平台实现出来。
class _FakePlayer extends VideoPlayerPlatform {
  /// 收到过的 play / pause / seek，用来断言「这一下到底有没有让画面停」。
  final List<String> calls = <String>[];

  StreamController<VideoEvent>? _events;
  bool isPlaying = false;
  bool looping = false;
  Duration position = Duration.zero;
  final Duration total = const Duration(seconds: 30);

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => 1;

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final events = StreamController<VideoEvent>();
    _events = events;
    return events.stream;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    this.looping = looping;
    calls.add('loop:${looping ? 'on' : 'off'}');
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
          int playerId, bool preventing) async {}

  @override
  Future<void> play(int playerId) async {
    isPlaying = true;
    calls.add('play');
  }

  @override
  Future<void> pause(int playerId) async {
    isPlaying = false;
    calls.add('pause');
  }

  @override
  Future<void> seekTo(int playerId, Duration pos) async {
    position = pos;
    calls.add('seek');
  }

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  /// 第一帧就绪，对应真机上那个 `initialized` 事件。
  void ready() => _events!.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: total,
        size: const Size(1280, 720),
      ));

  /// 播到最后一帧。
  void finish() {
    position = total;
    _events!.add(VideoEvent(eventType: VideoEventType.completed));
  }
}

_FakePlayer _installFakePlayer() {
  final previous = VideoPlayerPlatform.instance;
  final fake = _FakePlayer();
  VideoPlayerPlatform.instance = fake;
  addTearDown(() => VideoPlayerPlatform.instance = previous);
  return fake;
}

String _libraryJson() => jsonEncode({
      'categories': [
        {
          'id': 'vc1',
          'name': '动画片',
          'videos': [
            {
              'id': 'v1',
              'title': '小猪佩奇 第 1 集',
              'source': 'https://example.com/p1.mp4',
              'kind': 'link',
            },
          ],
        },
      ],
    });

Future<Widget> _host() async {
  SharedPreferences.setMockInitialValues({kVideoLibraryKey: _libraryJson()});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const MaterialApp(home: VideoCategoryScreen(categoryId: 'vc1')),
  );
}

/// 页面里有入场动画，统一用显式 pump 推进，不用 pumpAndSettle。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 推帧推到 [finder] 找不到为止——退场动画跑完还要再推一帧，路由才真正摘掉。
Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 8 && finder.evaluate().isNotEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// 从视频列表点进播放页，并把播放器推到「已经开播」的状态。
Future<_FakePlayer> _openPlayer(WidgetTester tester) async {
  final fake = _installFakePlayer();
  await tester.pumpWidget(await _host());
  await tester.pump();

  await tester.tap(find.text('小猪佩奇 第 1 集'));
  await _settle(tester);

  fake.ready();
  await _settle(tester);
  return fake;
}

/// 摸一下画面正中——中间那个播放圆钮待的地方。
Future<void> _touchStage(WidgetTester tester) async {
  await tester.tapAt(tester.getRect(find.byType(VideoPlayer)).center);
  await tester.pump();
}

/// 收摊：把整棵树换掉，播放器的定时器才会跟着停。
Future<void> _tearDownTree(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('视频放完自动退回视频列表', (tester) async {
    final fake = await _openPlayer(tester);
    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    expect(fake.isPlaying, isTrue);

    fake.finish();
    await _pumpUntilGone(tester, find.byType(VideoPlayerScreen));

    expect(find.byType(VideoPlayerScreen), findsNothing);
    expect(find.byType(VideoCategoryScreen), findsOneWidget);
    // 退出去之前先把声音停了，别让声音跟着退场动画继续响。
    expect(fake.isPlaying, isFalse);
  });

  testWidgets('开循环后播完从头再来，关掉后照旧退回列表', (tester) async {
    final fake = await _openPlayer(tester);

    await tester.tap(find.text('循环'));
    await _settle(tester);
    expect(fake.looping, isTrue);

    fake.calls.clear();
    fake.finish();
    await _settle(tester);

    // 人还在播放页上，画面重新走起来了。
    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    expect(fake.calls, contains('seek'));
    expect(fake.isPlaying, isTrue);

    await tester.tap(find.text('循环'));
    await _settle(tester);
    expect(fake.looping, isFalse);

    fake.finish();
    await _pumpUntilGone(tester, find.byType(VideoPlayerScreen));
    expect(find.byType(VideoPlayerScreen), findsNothing);
    expect(fake.isPlaying, isFalse);
  });

  testWidgets('循环开关记在本机上，再进播放页还是开的', (tester) async {
    final fake = await _openPlayer(tester);
    expect(fake.looping, isFalse);

    await tester.tap(find.text('循环'));
    await _settle(tester);
    expect(fake.looping, isTrue);

    // 退回列表，再点进同一个视频。
    await tester.pageBack();
    await _settle(tester);
    await tester.tap(find.text('小猪佩奇 第 1 集'));
    await _settle(tester);
    fake.ready();
    await _settle(tester);

    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    expect(fake.looping, isTrue);

    await _tearDownTree(tester);
  });

  testWidgets('窄屏手机上多出来的循环按钮也不会把控制条挤出屏幕', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openPlayer(tester);

    expect(tester.getRect(find.text('循环')).right, lessThanOrEqualTo(360));
    expect(tester.getRect(find.text('网络视频')).right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);

    await _tearDownTree(tester);
  });

  testWidgets('播放中摸画面不会暂停', (tester) async {
    final fake = await _openPlayer(tester);
    fake.calls.clear();

    await _touchStage(tester);
    await _touchStage(tester);

    expect(fake.calls, isEmpty);
    expect(fake.isPlaying, isTrue);
    expect(find.byType(VideoPlayerScreen), findsOneWidget);

    await _tearDownTree(tester);
  });

  testWidgets('控制条暂停后，点画面正中也能接着播', (tester) async {
    final fake = await _openPlayer(tester);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await _settle(tester);
    expect(fake.isPlaying, isFalse);
    expect(fake.calls, contains('pause'));

    await _touchStage(tester);
    await _settle(tester);

    expect(fake.isPlaying, isTrue);

    await _tearDownTree(tester);
  });
}
