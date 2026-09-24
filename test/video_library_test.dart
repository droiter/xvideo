import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xvideo/core/constants.dart';
import 'package:xvideo/features/video/video_category_screen.dart';
import 'package:xvideo/features/video/video_import.dart';
import 'package:xvideo/features/video/video_library_screen.dart';
import 'package:xvideo/features/video/video_manage_screen.dart';
import 'package:xvideo/features/video/video_player_screen.dart';
import 'package:xvideo/features/video/video_thumbnail.dart';
import 'package:xvideo/state/providers.dart';

/// 铺好内存版 SharedPreferences 的容器。
Future<ProviderContainer> _container(
    {Map<String, Object> seed = const {}}) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [prefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  return c;
}

/// 预置一份视频库（1 个分类 2 个视频），返回分类 id。
String _seedLibraryJson() => jsonEncode({
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
            {
              'id': 'v2',
              'title': '汪汪队 第 2 集',
              'source': '/data/user/0/com.xvideo.app/files/x.mp4',
              'kind': 'file',
            },
          ],
        },
      ],
    });

Future<Widget> _host(Widget child,
    {Map<String, Object> seed = const {}}) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(home: child),
  );
}

/// 页面里有入场动画，统一用显式 pump 推进，不用 pumpAndSettle。
/// 多推一帧是为了让路由真正从树上摘掉（动画跑完还要一帧才移除）。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 装一个 Android 选择器给回来的文件。[contentUri] 是 SAF 拿到的原始地址，
/// [path] 换掉选择器给的落盘路径（真拷过一遍的测试要用真文件）。
PlatformFile _pickedAndroid({required String name, String? contentUri, String? path}) =>
    AndroidPlatformFile.fromMap({
      'path': path ??
          '/data/user/0/com.xvideo.app/cache/file_picker/1757500000000/$name',
      'name': name,
      'size': 1024,
      if (contentUri != null)
        'safHandle': {'uri': contentUri, 'access': 'readOnly'},
    });

/// 顶掉真的系统选择器：照插件那边的规矩，先报一声「开始处理了」再给文件回来。
/// [gate] 非空时会卡在「处理中」，用来验证这一刻界面长什么样。
class _FakePicker extends FilePickerPlatform {
  _FakePicker(this.files, {this.gate});

  final List<PlatformFile> files;
  final Completer<void>? gate;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    onFileLoading?.call(FilePickerStatus.picking);
    if (gate != null) await gate!.future;
    onFileLoading?.call(FilePickerStatus.done);
    return files;
  }
}

/// 换成假选择器，测试结束再换回来。
void _useFakePicker(List<PlatformFile> files, {Completer<void>? gate}) {
  final original = FilePickerPlatform.instance;
  FilePickerPlatform.instance = _FakePicker(files, gate: gate);
  addTearDown(() => FilePickerPlatform.instance = original);
}

/// 把 path_provider 的两条路指到测试自己的临时目录（导入要往「文档目录」写）。
void _mockPathProvider({required String docs, required String tmp}) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
        return docs;
      case 'getTemporaryDirectory':
        return tmp;
    }
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// 导入流程里有真实的文件 I/O，widget 测试的假时钟等不到它——得开真事件循环
/// 转几圈：每圈给一点真实时间，再 pump 一帧让界面跟上。
Future<void> _pumpIo(WidgetTester tester, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// 把「问系统要文件名」那条通道换成固定答复；[answer] 为 null 表示问不出来。
void _mockNameChannel(String? answer) {
  const channel = MethodChannel('xvideo/picker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    expect(call.method, 'displayName');
    return answer;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

void main() {
  group('视频库状态', () {
    test('建分类、加视频、删视频、删分类都会落盘', () async {
      final c = await _container();
      final lib = c.read(videoLibraryProvider.notifier);

      expect(c.read(videoLibraryProvider).isEmpty, isTrue);

      final id = await lib.addCategory('动画片');
      await lib.addVideo(id, title: '小猪佩奇', source: 'https://a.com/1.mp4');
      await lib.addVideo(id,
          title: '汪汪队', source: '/tmp/x.mp4', kind: VideoKind.file);

      var snapshot = c.read(videoLibraryProvider);
      expect(snapshot.categories.single.name, '动画片');
      expect(snapshot.totalVideos, 2);
      expect(snapshot.categories.single.videos.last.isLocal, isTrue);

      await lib.removeVideo(id, snapshot.categories.single.videos.first.id);
      expect(c.read(videoLibraryProvider).totalVideos, 1);

      await lib.removeCategory(id);
      expect(c.read(videoLibraryProvider).isEmpty, isTrue);
    });

    test('重新读盘能还原分类与视频', () async {
      final c1 = await _container();
      final id = await c1.read(videoLibraryProvider.notifier).addCategory('儿歌');
      await c1.read(videoLibraryProvider.notifier).addVideo(id,
          title: '小星星', source: 'https://a.com/twinkle.mp4');

      // 同一份 prefs 换一个容器，相当于 App 重启后再读一次。
      final c2 = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
      ]);
      addTearDown(c2.dispose);

      final back = c2.read(videoLibraryProvider);
      expect(back.categories.single.name, '儿歌');
      expect(back.categories.single.videos.single.title, '小星星');
      expect(back.categories.single.videos.single.isLocal, isFalse);
    });

    test('空数据 / 脏数据不炸', () async {
      final c = await _container();
      expect(c.read(videoLibraryProvider).categories, isEmpty);

      SharedPreferences.setMockInitialValues({kVideoLibraryKey: '不是 json'});
      final dirty = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
      ]);
      addTearDown(dirty.dispose);
      expect(dirty.read(videoLibraryProvider).categories, isEmpty);
    });

    test('改名只动名字，视频还在', () async {
      final c = await _container();
      final lib = c.read(videoLibraryProvider.notifier);
      final id = await lib.addCategory('动画片');
      await lib.addVideo(id, title: '佩奇', source: 'https://a.com/1.mp4');

      await lib.renameCategory(id, '英文动画');
      final cat = c.read(videoLibraryProvider).categories.single;
      expect(cat.name, '英文动画');
      expect(cat.videos.single.title, '佩奇');
    });

    test('本分类里已有的视频不再加，别的分类照样能存一份', () async {
      final c = await _container();
      final lib = c.read(videoLibraryProvider.notifier);
      final cartoon = await lib.addCategory('动画片');
      final songs = await lib.addCategory('儿歌');

      final first = await lib.addVideo(cartoon,
          title: '小猪佩奇', source: 'https://a.com/1.mp4');
      expect(first.added, isTrue);
      expect(first.title, '小猪佩奇');

      // 同一个地址换个名字再添一次，还是同一个视频，不给加。
      final again = await lib.addVideo(cartoon,
          title: '佩奇第一集', source: 'https://a.com/1.mp4');
      expect(again.added, isFalse);
      expect(again.title, '小猪佩奇'); // 报的是已经在库里的那个名字
      expect(c.read(videoLibraryProvider).totalVideos, 1);

      // 别的分类里想再存一份是可以的。
      final other = await lib.addVideo(songs,
          title: '小猪佩奇', source: 'https://a.com/1.mp4');
      expect(other.added, isTrue);
      expect(c.read(videoLibraryProvider).totalVideos, 2);
    });

    test('分类里重名时自动加编号，不叠成「(2) (2)」', () async {
      final c = await _container();
      final lib = c.read(videoLibraryProvider.notifier);
      final id = await lib.addCategory('动画片');

      Future<String> add(String url) async =>
          (await lib.addVideo(id, title: '小猪佩奇', source: url)).title;

      expect(await add('https://a.com/1.mp4'), '小猪佩奇');
      expect(await add('https://a.com/2.mp4'), '小猪佩奇 (2)');
      expect(await add('https://a.com/3.mp4'), '小猪佩奇 (3)');

      // 名字本来就带编号时，从同一个根名字往上接着找。
      final fourth = await lib.addVideo(id,
          title: '小猪佩奇 (2)', source: 'https://a.com/4.mp4');
      expect(fourth.title, '小猪佩奇 (4)');
      expect(c.read(videoLibraryProvider).totalVideos, 4);
    });

    test('本机视频按「原文件名 + 大小」查重，指纹会落盘', () async {
      final c = await _container();
      final lib = c.read(videoLibraryProvider.notifier);
      final id = await lib.addCategory('动画片');
      const fp = '小猪佩奇 01.mp4|2048';

      final first = await lib.addVideo(id,
          title: '小猪佩奇 01',
          source: '/files/a1.mp4',
          kind: VideoKind.file,
          fingerprint: fp);
      expect(first.added, isTrue);
      expect(await lib.findDuplicate(id, fp), isNotNull);

      // 同一个文件再选一遍：复制进来的是另一个带时间戳的路径，只能靠指纹认出来。
      final again = await lib.addVideo(id,
          title: '小猪佩奇 01',
          source: '/files/a2.mp4',
          kind: VideoKind.file,
          fingerprint: fp);
      expect(again.added, isFalse);
      expect(c.read(videoLibraryProvider).totalVideos, 1);
      expect(
          c.read(videoLibraryProvider).categories.single.videos.single.fingerprint,
          fp);

      // 换个容器相当于 App 重启，指纹还在，照样认得出。
      final restarted = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
      ]);
      addTearDown(restarted.dispose);
      final back = restarted.read(videoLibraryProvider).categories.single;
      expect(back.videos.single.fingerprint, fp);
    });

    test('同名但大小不一样，算两个视频，第二个加编号', () async {
      final c = await _container();
      final lib = c.read(videoLibraryProvider.notifier);
      final id = await lib.addCategory('动画片');

      await lib.addVideo(id,
          title: '汪汪队',
          source: '/files/a.mp4',
          kind: VideoKind.file,
          fingerprint: '汪汪队.mp4|100');
      final second = await lib.addVideo(id,
          title: '汪汪队',
          source: '/files/b.mp4',
          kind: VideoKind.file,
          fingerprint: '汪汪队.mp4|200');

      expect(second.added, isTrue);
      expect(second.title, '汪汪队 (2)');
      expect(c.read(videoLibraryProvider).totalVideos, 2);
    });

    test('没有指纹（链接、老数据）不会互相误判', () async {
      final c = await _container(seed: {kVideoLibraryKey: _seedLibraryJson()});
      final lib = c.read(videoLibraryProvider.notifier);

      expect(await lib.findDuplicate('vc1', ''), isNull);
      // 老的本机视频没指纹，退回拿各自的路径当键：换个路径就是新的一份。
      final fresh = await lib.addVideo('vc1',
          title: '汪汪队 第 3 集',
          source: '/data/user/0/com.xvideo.app/files/y.mp4',
          kind: VideoKind.file);
      expect(fresh.added, isTrue);
      // 路径一模一样才算重复。
      final samePath = await lib.addVideo('vc1',
          title: '汪汪队 第 2 集',
          source: '/data/user/0/com.xvideo.app/files/x.mp4',
          kind: VideoKind.file);
      expect(samePath.added, isFalse);
      expect(c.read(videoLibraryProvider).totalVideos, 3);
    });
  });

  group('「我的」里的视频管理页', () {
    testWidgets('新建分类 + 添加链接视频，列表立刻更新', (tester) async {
      await tester.pumpWidget(await _host(const VideoManageScreen()));
      await tester.pump();

      expect(find.text('还没有视频分类'), findsOneWidget);

      // 新建分类
      await tester.tap(find.text('新建分类'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), '动画片');
      await tester.tap(find.text('创建'));
      await _settle(tester);

      expect(find.text('动画片'), findsOneWidget);
      expect(find.text('0 个视频'), findsOneWidget);

      // 添加一个链接视频
      await tester.tap(find.text('添加视频'));
      await _settle(tester);
      await tester.tap(find.text('粘贴视频链接'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField).at(0), '小猪佩奇 第 1 集');
      await tester.enterText(find.byType(TextField).at(1), 'https://a.com/p1.mp4');
      await tester.tap(find.text('添加'));
      await _settle(tester);

      expect(find.text('小猪佩奇 第 1 集'), findsOneWidget);
      expect(find.text('1 个视频'), findsOneWidget);
    });

    testWidgets('链接格式不对时不给加', (tester) async {
      await tester.pumpWidget(
          await _host(const VideoManageScreen(), seed: {kVideoLibraryKey: _seedLibraryJson()}));
      await tester.pump();

      await tester.tap(find.text('添加视频'));
      await _settle(tester);
      await tester.tap(find.text('粘贴视频链接'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField).at(1), '随便写点什么');
      await tester.tap(find.text('添加'));
      await _settle(tester);

      expect(find.text('请填以 http:// 或 https:// 开头的地址'), findsOneWidget);
    });

    testWidgets('建完一个分类后，列表里还能再建一个', (tester) async {
      await tester.pumpWidget(await _host(const VideoManageScreen(),
          seed: {kVideoLibraryKey: _seedLibraryJson()}));
      await tester.pump();

      // 只剩 AppBar 上一个小图标的话，家长会以为只能建一个分类。
      await tester.ensureVisible(find.text('新建分类'));
      await tester.pump();
      await tester.tap(find.text('新建分类'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), '儿歌');
      await tester.tap(find.text('创建'));
      await _settle(tester);

      expect(find.text('动画片'), findsOneWidget);
      expect(find.text('儿歌'), findsOneWidget);
    });

    testWidgets('重命名分类时预填原名，并整段选中', (tester) async {
      await tester.pumpWidget(await _host(const VideoManageScreen(),
          seed: {kVideoLibraryKey: _seedLibraryJson()}));
      await tester.pump();

      await tester.tap(find.byTooltip('分类操作'));
      await _settle(tester);
      await tester.tap(find.text('重命名'));
      await _settle(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '动画片');
      expect(field.controller!.selection,
          const TextSelection(baseOffset: 0, extentOffset: 3));
    });

    testWidgets('删掉视频后分类里就没了', (tester) async {
      await tester.pumpWidget(await _host(const VideoManageScreen(),
          seed: {kVideoLibraryKey: _seedLibraryJson()}));
      await tester.pump();

      expect(find.text('小猪佩奇 第 1 集'), findsOneWidget);
      await tester.tap(find.byTooltip('删除视频').first);
      await _settle(tester);
      await tester.tap(find.text('删除'));
      await _settle(tester);

      expect(find.text('小猪佩奇 第 1 集'), findsNothing);
      expect(find.text('汪汪队 第 2 集'), findsOneWidget);
      expect(find.text('1 个视频'), findsOneWidget);
    });

    testWidgets('链接已经在分类里时不再加，并告诉家长一声', (tester) async {
      await tester.pumpWidget(await _host(const VideoManageScreen(),
          seed: {kVideoLibraryKey: _seedLibraryJson()}));
      await tester.pump();

      await tester.tap(find.text('添加视频'));
      await _settle(tester);
      await tester.tap(find.text('粘贴视频链接'));
      await _settle(tester);

      // 名字换了，地址跟库里那条一模一样——是同一个视频，不该再存一份。
      await tester.enterText(find.byType(TextField).at(0), '佩奇第一集');
      await tester.enterText(
          find.byType(TextField).at(1), 'https://example.com/p1.mp4');
      await tester.tap(find.text('添加'));
      await _settle(tester);

      expect(find.textContaining('没有重复添加'), findsOneWidget);
      expect(find.text('佩奇第一集'), findsNothing);
      expect(find.text('小猪佩奇 第 1 集'), findsOneWidget);
      expect(find.text('2 个视频'), findsOneWidget);
    });

    testWidgets('链接重名时自动加编号', (tester) async {
      await tester.pumpWidget(await _host(const VideoManageScreen(),
          seed: {kVideoLibraryKey: _seedLibraryJson()}));
      await tester.pump();

      await tester.tap(find.text('添加视频'));
      await _settle(tester);
      await tester.tap(find.text('粘贴视频链接'));
      await _settle(tester);

      // 名字跟已有的撞了，地址是新的：该存成「(2)」，而不是被当成重复挡下来。
      await tester.enterText(find.byType(TextField).at(0), '小猪佩奇 第 1 集');
      await tester.enterText(
          find.byType(TextField).at(1), 'https://example.com/p9.mp4');
      await tester.tap(find.text('添加'));
      await _settle(tester);

      expect(find.text('小猪佩奇 第 1 集'), findsOneWidget);
      expect(find.text('小猪佩奇 第 1 集 (2)'), findsOneWidget);
      expect(find.text('3 个视频'), findsOneWidget);
    });
  });

  group('批量添加本机视频', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('xvideo_batch');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    /// 选择器缓存里的那份副本（插件拷进来的）。名字取了「汪汪队.mp4」。
    File cachedCopy({String name = '汪汪队.mp4', int size = 2048}) =>
        File('${root.path}/tmp/file_picker/1757500000000/$name')
          ..createSync(recursive: true)
          ..writeAsBytesSync(List.filled(size, 3));

    /// 一条老记录：本机视频，没存指纹，只能靠落盘的文件认。
    String seedOldLocal(String source) => jsonEncode({
          'categories': [
            {
              'id': 'vc1',
              'name': '动画片',
              'videos': [
                {
                  'id': 'v1',
                  'title': '汪汪队 第 2 集',
                  'source': source,
                  'kind': 'file',
                },
              ],
            },
          ],
        });

    test('老记录没有指纹，同一个文件再选一遍也拦得住', () async {
      final stored = File('${root.path}/1757500000000_汪汪队.mp4')
        ..writeAsBytesSync(List.filled(2048, 3));
      final picked = File('${root.path}/另外一份.mp4')
        ..writeAsBytesSync(List.filled(2048, 3));

      final c = await _container(
          seed: {kVideoLibraryKey: seedOldLocal(stored.path)});
      final lib = c.read(videoLibraryProvider.notifier);

      final fp = await videoFingerprint(
          PickedVideo(name: '汪汪队.mp4', path: picked.path));
      expect(fp, '汪汪队.mp4|2048');
      expect((await lib.findDuplicate('vc1', fp))?.title, '汪汪队 第 2 集');

      // 走一遍加视频：名字换了也没用，是同一个文件就不给加。
      final again = await lib.addVideo('vc1',
          title: '再存一遍',
          source: '${root.path}/又一份.mp4',
          kind: VideoKind.file,
          fingerprint: fp);
      expect(again.added, isFalse);
      expect(again.title, '汪汪队 第 2 集');
      expect(c.read(videoLibraryProvider).totalVideos, 1);

      // 大小不一样的还是另一个视频，照样能加。
      final other = await lib.addVideo('vc1',
          title: '汪汪队 第 3 集',
          source: '${root.path}/新的.mp4',
          kind: VideoKind.file,
          fingerprint: '汪汪队.mp4|4096');
      expect(other.added, isTrue);
      expect(c.read(videoLibraryProvider).totalVideos, 2);
    });

    test('从选择器缓存搬进 App 目录是搬，不是再拷一份', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      _mockPathProvider(docs: '${root.path}/docs', tmp: '${root.path}/tmp');

      final cached = cachedCopy();
      final dest = await importLocalVideo(
          PickedVideo(name: '汪汪队.mp4', path: cached.path));

      expect(dest, contains('xvideo_videos'));
      expect(File(dest).lengthSync(), 2048);
      // 缓存里那份被搬走了：不再整份拷一遍，几百兆的视频能少等好几秒。
      expect(cached.existsSync(), isFalse);

      // 不在缓存目录里的路径（家长自己的文件）绝不能搬走，只能老老实实拷。
      final real = File('${root.path}/我的电影.mp4')
        ..writeAsBytesSync(List.filled(100, 1));
      final dest2 = await importLocalVideo(
          PickedVideo(name: '我的电影.mp4', path: real.path));
      expect(real.existsSync(), isTrue);
      expect(File(dest2).lengthSync(), 100);
    });

    test('搬过去的还是原来那个文件，不是又拷一份', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      _mockPathProvider(docs: '${root.path}/docs', tmp: '${root.path}/tmp');

      // 缓存里那个是指向别处的软链：整份拷一遍会落成普通文件，直接改名搬过去
      // 则还是软链——正好用来看清到底是「搬」还是「拷」。
      final real = File('${root.path}/真的在这里.mp4')
        ..writeAsBytesSync(List.filled(2048, 7));
      final cachedDir = Directory('${root.path}/tmp/file_picker/1757500000000')
        ..createSync(recursive: true);
      final cached = Link('${cachedDir.path}/汪汪队.mp4')..createSync(real.path);

      final dest = await importLocalVideo(
          PickedVideo(name: '汪汪队.mp4', path: cached.path));

      expect(FileSystemEntity.isLinkSync(dest), isTrue);
      expect(File(dest).lengthSync(), 2048);
      expect(cached.existsSync(), isFalse);
      expect(real.existsSync(), isTrue); // 指向的真文件没被动过
    });

    testWidgets('选完文件马上盖进度框，界面点不动', (tester) async {
      final gate = Completer<void>();
      final cached = cachedCopy();
      _useFakePicker(
          [_pickedAndroid(name: '汪汪队.mp4', path: cached.path)],
          gate: gate);
      _mockPathProvider(docs: '${root.path}/docs', tmp: '${root.path}/tmp');

      await tester.pumpWidget(await _host(const VideoManageScreen(),
          seed: {kVideoLibraryKey: _seedLibraryJson()}));
      await tester.pump();

      await tester.tap(find.text('添加视频'));
      await _settle(tester);
      await tester.tap(find.text('从本机选择文件'));
      await tester.pump();

      // 插件这会儿还在后台拷文件（gate 卡着）。以前这一段界面上什么提示都没有，
      // 家长能随便乱点，进度条要等好久才出来。
      expect(find.text('正在读取你选中的视频…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // 盖着的时候点不动底下的按钮（能点的话会弹出「新建分类」的输入框）。
      await tester.tap(find.text('新建分类'), warnIfMissed: false);
      await _settle(tester);
      expect(find.byType(TextField), findsNothing);

      // 放行，导入跑完（也别留一个永远不返回的 future）。
      gate.complete();
      await _pumpIo(tester);

      expect(find.text('正在读取你选中的视频…'), findsNothing);
      expect(find.text('汪汪队'), findsOneWidget);
      expect(find.text('3 个视频'), findsOneWidget);
    });

    testWidgets('已经在库里的那个不再加，并把被挡下的列出来', (tester) async {
      final stored = File('${root.path}/docs/xvideo_videos/1757500000000_汪汪队.mp4')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(2048, 3));
      final fresh = File('${root.path}/tmp/file_picker/1757500000000/佩奇.mp4')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(4096, 5));

      _useFakePicker([
        _pickedAndroid(name: '汪汪队.mp4', path: cachedCopy().path),
        _pickedAndroid(name: '佩奇.mp4', path: fresh.path),
      ]);
      _mockPathProvider(docs: '${root.path}/docs', tmp: '${root.path}/tmp');

      await tester.pumpWidget(await _host(const VideoManageScreen(),
          seed: {kVideoLibraryKey: seedOldLocal(stored.path)}));
      await tester.pump();

      await tester.tap(find.text('添加视频'));
      await _settle(tester);
      await tester.tap(find.text('从本机选择文件'));
      await _pumpIo(tester);

      // 挡下的是哪一个，得一个一个列出来给家长看。
      expect(find.text('这些视频不能重复添加'), findsOneWidget);
      expect(find.textContaining('已经在「动画片」里了'), findsOneWidget);
      expect(find.text('· 汪汪队 第 2 集'), findsOneWidget);
      expect(find.text('1 个视频'), findsOneWidget); // 还没动手加

      await tester.tap(find.text('继续添加其余 1 个'));
      await _pumpIo(tester);

      // 只多了没重复的那一个。
      expect(find.text('佩奇'), findsOneWidget);
      expect(find.text('2 个视频'), findsOneWidget);
    });
  });

  group('「看视频」选项卡', () {
    testWidgets('没有视频时给引导，点按钮回「我的」', (tester) async {
      var jumped = false;
      await tester.pumpWidget(await _host(
        VideoLibraryScreen(onOpenManage: () => jumped = true),
      ));
      await tester.pump();

      expect(find.text('还没有视频'), findsOneWidget);
      await tester.tap(find.text('去添加视频'));
      await tester.pump();
      expect(jumped, isTrue);
    });

    testWidgets('看到「我的」里建好的分类，点进去看到视频', (tester) async {
      await tester.pumpWidget(await _host(
        VideoLibraryScreen(onOpenManage: () {}),
        seed: {kVideoLibraryKey: _seedLibraryJson()},
      ));
      await tester.pump();

      expect(find.text('动画片'), findsOneWidget);
      expect(find.text('2 个视频'), findsOneWidget);

      await tester.tap(find.text('动画片'));
      await _settle(tester);

      expect(find.byType(VideoCategoryScreen), findsOneWidget);
      expect(find.text('小猪佩奇 第 1 集'), findsOneWidget);
      expect(find.text('汪汪队 第 2 集'), findsOneWidget);
      expect(find.text('本机'), findsOneWidget); // 本地视频的标记
      expect(find.text('网络'), findsOneWidget);
    });

    testWidgets('手机窄屏下分类卡不溢出', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await _host(
        VideoLibraryScreen(onOpenManage: () {}),
        seed: {kVideoLibraryKey: _seedLibraryJson()},
      ));
      await tester.pump();

      expect(find.text('动画片'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('分类被删掉后列表不再显示它', (tester) async {
      final c = await _container(seed: {kVideoLibraryKey: _seedLibraryJson()});
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: VideoLibraryScreen(onOpenManage: () {})),
      ));
      await tester.pump();
      expect(find.text('动画片'), findsOneWidget);

      await c.read(videoLibraryProvider.notifier).removeCategory('vc1');
      await tester.pump();
      expect(find.text('动画片'), findsNothing);
    });
  });

  group('播放页', () {
    testWidgets('点视频进播放页，按返回键随时退回（没有家长验证）', (tester) async {
      await tester.pumpWidget(await _host(
        const VideoCategoryScreen(categoryId: 'vc1'),
        seed: {kVideoLibraryKey: _seedLibraryJson()},
      ));
      await tester.pump();

      await tester.tap(find.text('小猪佩奇 第 1 集'));
      await _settle(tester);

      expect(find.byType(VideoPlayerScreen), findsOneWidget);
      // 测试环境里没有真正的播放器实现，会落到「播放失败」兜底——这没关系，
      // 这里要确认的是返回键不被拦。
      expect(find.byType(PopScope), findsNothing);

      await tester.pageBack();
      await _settle(tester);

      expect(find.byType(VideoPlayerScreen), findsNothing);
      expect(find.byType(VideoCategoryScreen), findsOneWidget);
    });

    testWidgets('本地文件不存在时给出提示和重试', (tester) async {
      await tester.pumpWidget(await _host(
        const VideoPlayerScreen(
          video: VideoItem(
            id: 'v9',
            title: '丢了的视频',
            source: '/nowhere/none.mp4',
            kind: VideoKind.file,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('打不开了'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('视频名字（预填）', () {
    test('文件名去掉后缀；拿不到文件名就用「视频 N」占位', () {
      expect(videoNameFromFileName('小猪佩奇 01.mp4'), '小猪佩奇 01');
      expect(videoNameFromFileName('汪汪队'), '汪汪队');
      expect(defaultVideoName('小猪佩奇 01.mp4', 3), '小猪佩奇 01');
      expect(defaultVideoName('', 3), '视频 3');
    });

    test('选择器给的是编号时，自己再问一次系统', () async {
      _mockNameChannel('小猪佩奇 01.mp4');
      final f = _pickedAndroid(
        name: '1000000033',
        contentUri: 'content://media/external/video/media/1234',
      );
      expect(await resolveVideoName(f), '小猪佩奇 01.mp4');
    });

    test('问不到系统就退回选择器给的正常文件名', () async {
      _mockNameChannel(null);
      final f = _pickedAndroid(
        name: '汪汪队.mp4',
        contentUri: 'content://media/external/video/media/1234',
      );
      expect(await resolveVideoName(f), '汪汪队.mp4');
    });

    test('编号、unamed 这种都不算名字', () async {
      _mockNameChannel(null);
      expect(await resolveVideoName(_pickedAndroid(name: '1000000033')), '');
      expect(await resolveVideoName(_pickedAndroid(name: 'unamed')), '');
      expect(await resolveVideoName(_pickedAndroid(name: 'video:1234')), '');
    });

    test('平台上没接这条通道也不炸', () async {
      // 不设 mock：真机上没有对应实现时走的就是这条路。
      final f = _pickedAndroid(
        name: '汪汪队.mp4',
        contentUri: 'content://media/external/video/media/1234',
      );
      expect(await resolveVideoName(f), '汪汪队.mp4');
    });
  });

  group('本机视频指纹', () {
    test('原文件名 + 字节数；文件读不到就不给指纹', () async {
      final dir = await Directory.systemTemp.createTemp('xvideo_fp');
      addTearDown(() => dir.delete(recursive: true));

      final a = File('${dir.path}/佩奇.mp4')
        ..writeAsBytesSync(List.filled(2048, 7));
      expect(
        await videoFingerprint(PickedVideo(name: '佩奇.mp4', path: a.path)),
        '佩奇.mp4|2048',
      );

      // 同一个文件被选择器拷到别处（缓存副本），指纹得一样，才认得出是它。
      final b = File('${dir.path}/cache/佩奇.mp4')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(2048, 7));
      expect(
        await videoFingerprint(PickedVideo(name: '佩奇.mp4', path: b.path)),
        await videoFingerprint(PickedVideo(name: '佩奇.mp4', path: a.path)),
      );

      // 文件已经没了（系统清过缓存）就不给指纹：宁可漏判，也别把想加的挡在门外。
      expect(
        await videoFingerprint(
            PickedVideo(name: '佩奇.mp4', path: '${dir.path}/没有这个.mp4')),
        '',
      );
    });

    test('老记录按落盘的文件现推一个指纹出来', () async {
      final dir = await Directory.systemTemp.createTemp('xvideo_stored');
      addTearDown(() => dir.delete(recursive: true));

      // 导入时落盘的名字形如「<微秒时间戳>_<文件名>」，大小就是当初那份拷贝。
      final stored = File('${dir.path}/1757500000000_佩奇.mp4')
        ..writeAsBytesSync(List.filled(2048, 7));
      expect(await storedFingerprintOf(stored.path), '佩奇.mp4|2048');

      // 链接、不是我们命名的路径、文件已经被删掉：都推不出来。
      expect(await storedFingerprintOf('https://a.com/1.mp4'), isNull);
      expect(await storedFingerprintOf('${dir.path}/别的应用的文件.mp4'), isNull);
      expect(
          await storedFingerprintOf('${dir.path}/1757500000000_没了.mp4'), isNull);
    });

    test('名字里有落盘时会被换掉的字符，两边按同一套写法算才对得上', () {
      expect(safeVideoFileName('小猪:佩奇.mp4'), '小猪_佩奇.mp4');
      expect(safeVideoFileName('小猪佩奇.mp4'), '小猪佩奇.mp4');
    });
  });

  group('分类里的视频列表（方块网格）', () {
    /// 铺一个有 [count] 个视频的分类。
    String seedMany(int count) => jsonEncode({
          'categories': [
            {
              'id': 'vc1',
              'name': '动画片',
              'videos': [
                for (var i = 1; i <= count; i++)
                  {
                    'id': 'v$i',
                    'title': '第 $i 集',
                    'source': 'https://example.com/$i.mp4',
                    'kind': 'link',
                  },
              ],
            },
          ],
        });

    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await _host(
        const VideoCategoryScreen(categoryId: 'vc1'),
        seed: {kVideoLibraryKey: seedMany(6)},
      ));
      await tester.pump();
    }

    /// 第一行排了几个方块：左边缘 x 相同的算一行。
    int firstRowCount(WidgetTester tester) {
      final rects = [
        for (var i = 0; i < 6; i++)
          tester.getRect(find.byType(VideoThumb).at(i))
      ];
      final top = rects.first.top;
      return rects.where((r) => r.top == top).length;
    }

    testWidgets('手机窄屏一行两个，方块比原来的列表缩略图大', (tester) async {
      await pumpAt(tester, const Size(360, 640));

      expect(firstRowCount(tester), 2);
      final thumb = tester.getRect(find.byType(VideoThumb).first);
      expect(thumb.width, greaterThan(88)); // 老列表里的缩略图只有 88 宽
      expect(thumb.width, greaterThanOrEqualTo(140));
      expect(tester.takeException(), isNull);
    });

    testWidgets('平板上一行四个，方块左右铺满不留空', (tester) async {
      await pumpAt(tester, const Size(1024, 768));

      expect(firstRowCount(tester), 4);
      final thumb = tester.getRect(find.byType(VideoThumb).first);
      // 方块宽度 ÷ 高度是 16:9 的缩略图，底下再挂一块文字。
      expect(thumb.height, closeTo(thumb.width * 9 / 16, 1));
      // 一行排到最右：最后一列的右边缘贴着页边距，不再是一列窄条。
      expect(tester.getRect(find.byType(VideoThumb).at(3)).right,
          closeTo(1024 - 16, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('超宽屏也不把方块拉成一长条（最多四列）', (tester) async {
      await pumpAt(tester, const Size(1600, 900));

      expect(firstRowCount(tester), 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('方块还是能点开播放页', (tester) async {
      await pumpAt(tester, const Size(360, 640));

      await tester.tap(find.text('第 1 集'));
      await _settle(tester);
      expect(find.byType(VideoPlayerScreen), findsOneWidget);
    });
  });

  group('播放页布局', () {
    testWidgets('高视频不会把控制条顶出屏幕（那里会被系统导航条盖住）',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: PlayerStage(
              aspectRatio: 9 / 16,
              video: ColoredBox(
                key: ValueKey('stage-video'),
                color: Colors.blue,
              ),
              controls: SizedBox(
                height: 92,
                child: Center(child: Text('控制条')),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('控制条')).bottom, lessThanOrEqualTo(1000));
      // 竖屏画面按剩下的高度缩下来，整幅都在屏幕里。
      final video = tester.getRect(find.byKey(const ValueKey('stage-video')));
      expect(video.height, greaterThan(400));
      expect(video.bottom, lessThanOrEqualTo(1000));
    });
  });
}
