import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xvideo/core/constants.dart';
import 'package:xvideo/features/video/video_category_screen.dart';
import 'package:xvideo/features/video/video_thumbnail.dart';
import 'package:xvideo/state/providers.dart';

const MethodChannel _videoChannel = MethodChannel('xvideo/video');

/// 一张真的 1×1 PNG，当作「抽出来的那一帧」。
final Uint8List _frameBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQAB'
  'DQottAAAAABJRU5ErkJggg==',
);

int _thumbCalls = 0;

/// 把「抽帧」这条通道换成固定答复；[bytes] 为 null 表示抽不出来。
void _mockThumbChannel({Uint8List? bytes}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_videoChannel, (call) async {
    _thumbCalls++;
    expect(call.method, 'thumbnail');
    return bytes;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_videoChannel, null));
}

VideoItem _local(String id) => VideoItem(
      id: id,
      title: '本机视频 $id',
      source: '/data/user/0/com.xvideo.app/files/xvideo_videos/$id.mp4',
      kind: VideoKind.file,
    );

VideoItem _link(String id) => VideoItem(
      id: id,
      title: '网络视频 $id',
      source: 'https://example.com/$id.mp4',
      kind: VideoKind.link,
    );

String _seedJson(List<VideoItem> videos) => jsonEncode({
      'categories': [
        {
          'id': 'vc1',
          'name': '动画片',
          'videos': [for (final v in videos) v.toJson()],
        },
      ],
    });

Future<Widget> _host(
  Widget child, {
  Map<String, Object> seed = const {},
  VideoThumbCache? cache,
}) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      if (cache != null) videoThumbCacheProvider.overrideWithValue(cache),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late VideoThumbCache cache;

  setUp(() async {
    _thumbCalls = 0;
    tmp = await Directory.systemTemp.createTemp('xvideo_thumb');
    addTearDown(() => tmp.delete(recursive: true));
    // 真机上缩略图放在 App 私有目录里，测试里换成临时目录。
    cache = VideoThumbCache(dirProvider: () async => tmp);
  });

  group('缩略图缓存', () {
    test('本机视频抽一帧存成文件，第二次直接用文件', () async {
      _mockThumbChannel(bytes: _frameBytes);
      final v = _local('v1');

      final file = await cache.ensure(v);
      expect(file, isNotNull);
      expect(file!.path, '${tmp.path}/v1.jpg');
      expect(file.existsSync(), isTrue);
      expect(await file.readAsBytes(), _frameBytes);
      expect(_thumbCalls, 1);

      // 再来一次不再抽帧，也不重新写盘。
      expect((await cache.ensure(v))!.path, file.path);
      expect(_thumbCalls, 1);
    });

    test('同一个视频同时被问两次，只抽一次', () async {
      _mockThumbChannel(bytes: _frameBytes);
      final v = _local('v1');

      final files = await Future.wait([cache.ensure(v), cache.ensure(v)]);
      expect(files[0], isNotNull);
      expect(files[0]!.path, files[1]!.path);
      expect(_thumbCalls, 1);
    });

    test('抽不出来就返回空，且不再反复试', () async {
      _mockThumbChannel();
      final v = _local('v1');

      expect(await cache.ensure(v), isNull);
      expect(await cache.ensure(v), isNull);
      expect(_thumbCalls, 1);
      expect(File('${tmp.path}/v1.jpg').existsSync(), isFalse);
    });

    test('链接视频不去抽帧', () async {
      _mockThumbChannel(bytes: _frameBytes);
      expect(await cache.ensure(_link('v9')), isNull);
      expect(_thumbCalls, 0);
    });

    test('视频删掉时缩略图文件也一起清理', () async {
      _mockThumbChannel(bytes: _frameBytes);
      final v = _local('v1');
      final file = (await cache.ensure(v))!;
      expect(file.existsSync(), isTrue);

      await cache.remove(v.id);
      expect(file.existsSync(), isFalse);
    });

    test('平台上没接这条通道也不炸', () async {
      // 不设 mock：桌面、测试环境走的都是这条路。
      expect(await cache.ensure(_local('v1')), isNull);
    });
  });

  group('列表里的缩略图', () {
    testWidgets('抽到帧的分类列表显示缩略图', (tester) async {
      _mockThumbChannel(bytes: _frameBytes);
      await tester.pumpWidget(await _host(
        const VideoCategoryScreen(categoryId: 'vc1'),
        seed: {kVideoLibraryKey: _seedJson([_local('v1')])},
        cache: cache,
      ));
      await tester.pump();

      // 抽帧、落盘都是真 I/O：每次 await 都要一圈真实事件循环 + 一次刷微任务，
      // 所以这里是「转一圈真实的、pump 一下」重复几轮，而不是一次 pumpAndSettle。
      // 上限给足、出现就收：整包测试并行跑时 I/O 会被别的用例抢，写死轮数会假失败。
      for (var i = 0; i < 80 && find.byType(Image).evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }

      expect(find.text('本机视频 v1'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(_thumbCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('抽不到帧时退回渐变占位块', (tester) async {
      // 不设 mock：真机上文件坏了、不是视频时走的就是这条路。
      await tester.pumpWidget(await _host(
        const VideoCategoryScreen(categoryId: 'vc1'),
        seed: {kVideoLibraryKey: _seedJson([_local('v1')])},
        cache: cache,
      ));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      // 占位块中间还是那个播放按钮，按钮还能进去。
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('链接视频在列表里不联网抽帧', (tester) async {
      _mockThumbChannel(bytes: _frameBytes);
      await tester.pumpWidget(await _host(
        const VideoCategoryScreen(categoryId: 'vc1'),
        seed: {kVideoLibraryKey: _seedJson([_link('v9')])},
        cache: cache,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('网络视频 v9'), findsOneWidget);
      expect(_thumbCalls, 0);
      expect(find.byType(Image), findsNothing);
    });
  });
}
