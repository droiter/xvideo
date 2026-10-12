import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xvideo/core/constants.dart';
import 'package:xvideo/features/profile/profile_screen.dart';
import 'package:xvideo/features/shell/parent_password.dart';
import 'package:xvideo/features/video/video_category_screen.dart';
import 'package:xvideo/features/video/video_library_screen.dart';
import 'package:xvideo/features/video/video_player_screen.dart';
import 'package:xvideo/state/providers.dart';

Map<String, Object> _video(String id, String title, {bool hidden = false}) => {
      'id': id,
      'title': title,
      'source': 'https://example.com/$id.mp4',
      'kind': 'link',
      if (hidden) 'hidden': true,
    };

/// 1 个分类 3 个视频；[hidden] 里列到的那些标成家长收起来了。
String _libraryJson({Set<String> hidden = const {}}) => jsonEncode({
      'categories': [
        {
          'id': 'vc1',
          'name': '动画片',
          'videos': [
            _video('v1', '小猪佩奇 第 1 集', hidden: hidden.contains('v1')),
            _video('v2', '汪汪队 第 2 集', hidden: hidden.contains('v2')),
            _video('v3', '海底小纵队', hidden: hidden.contains('v3')),
          ],
        },
      ],
    });

Future<ProviderContainer> _container({
  Set<String> hidden = const {},
  Map<String, Object> extra = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    kVideoLibraryKey: _libraryJson(hidden: hidden),
    ...extra,
  });
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [prefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  return c;
}

/// 页面里有入场动画，统一用显式 pump 推进，不用 pumpAndSettle。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pump(WidgetTester tester, ProviderContainer c, Widget child) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(home: child),
  ));
  await tester.pump();
}

Future<void> _pumpCategory(WidgetTester tester, ProviderContainer c) =>
    _pump(tester, c, const VideoCategoryScreen(categoryId: 'vc1'));

/// 「我的」页挺长，默认 600 高的视口会把下面那几条挡在懒加载外面。
void _useTablet(WidgetTester tester) {
  tester.view.physicalSize = const Size(1024, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 点「家长设置」→ 输密码 → 进家长模式。
Future<void> _enterParentMode(WidgetTester tester,
    {String password = kDefaultParentPassword}) async {
  await tester.tap(find.byKey(const ValueKey('parent-mode-button')));
  await _settle(tester);
  await tester.enterText(
      find.byKey(const ValueKey('parent-password-input')), password);
  await tester.tap(find.byKey(const ValueKey('parent-password-ok')));
  await _settle(tester);
}

/// 分类里视频的先后顺序（按 id）。
List<String> _order(ProviderContainer c) =>
    c.read(videoLibraryProvider).byId('vc1')!.videos.map((v) => v.id).toList();

void main() {
  group('家长收起来 / 放出来', () {
    test('收起来的视频还在库里，只是不给孩子看', () async {
      final c = await _container();
      final lib = c.read(videoLibraryProvider.notifier);

      await lib.setVideoHidden('vc1', 'v2', hidden: true);

      final category = c.read(videoLibraryProvider).byId('vc1')!;
      expect(category.videos.length, 3, reason: '视频本身没删');
      expect(category.hiddenCount, 1);
      expect([for (final v in category.visibleVideos) v.id], ['v1', 'v3']);
    });

    test('放出来之后又回到孩子那边', () async {
      final c = await _container(hidden: {'v2'});
      expect(c.read(videoLibraryProvider).byId('vc1')!.visibleVideos.length, 2);

      await c
          .read(videoLibraryProvider.notifier)
          .setVideoHidden('vc1', 'v2', hidden: false);

      expect(c.read(videoLibraryProvider).byId('vc1')!.visibleVideos.length, 3);
    });

    test('hide 标记落盘，重开 App 照样藏着', () async {
      final c = await _container();
      await c
          .read(videoLibraryProvider.notifier)
          .setVideoHidden('vc1', 'v2', hidden: true);

      final raw = c.read(prefsProvider).getString(kVideoLibraryKey)!;
      expect(raw.contains('"hidden":true'), isTrue);

      // 拿同一份 prefs 再铺一个容器，当重新打开 App。
      final again = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(c.read(prefsProvider))],
      );
      addTearDown(again.dispose);
      expect(again.read(videoLibraryProvider).byId('vc1')!.hiddenCount, 1);
    });

    test('老数据没有 hidden 字段，当没藏', () {
      expect(
        VideoLibrary.fromJson(jsonDecode(_libraryJson()) as Map<String, dynamic>)
            .byId('vc1')!
            .hiddenCount,
        0,
      );
    });

    test('分类和视频都不在了就什么也不做', () async {
      final c = await _container();
      final lib = c.read(videoLibraryProvider.notifier);

      await lib.setVideoHidden('没有这个分类', 'v1', hidden: true);
      await lib.setVideoHidden('vc1', '没有这个视频', hidden: true);

      expect(c.read(videoLibraryProvider).byId('vc1')!.hiddenCount, 0);
    });
  });

  group('往前排 / 往后排 / 置顶 / 置尾', () {
    test('往前挪一位、往后挪一位', () async {
      final c = await _container();
      final lib = c.read(videoLibraryProvider.notifier);

      await lib.moveVideo('vc1', 'v3', VideoMove.up);
      expect(_order(c), ['v1', 'v3', 'v2']);

      await lib.moveVideo('vc1', 'v1', VideoMove.down);
      expect(_order(c), ['v3', 'v1', 'v2']);
    });

    test('置顶和置尾', () async {
      final c = await _container();
      final lib = c.read(videoLibraryProvider.notifier);

      await lib.moveVideo('vc1', 'v3', VideoMove.top);
      expect(_order(c), ['v3', 'v1', 'v2']);

      await lib.moveVideo('vc1', 'v3', VideoMove.bottom);
      expect(_order(c), ['v1', 'v2', 'v3']);
    });

    test('已经在头 / 尾上再挪就不动', () async {
      final c = await _container();
      final lib = c.read(videoLibraryProvider.notifier);

      await lib.moveVideo('vc1', 'v1', VideoMove.up);
      await lib.moveVideo('vc1', 'v1', VideoMove.top);
      expect(_order(c), ['v1', 'v2', 'v3']);

      await lib.moveVideo('vc1', 'v3', VideoMove.down);
      await lib.moveVideo('vc1', 'v3', VideoMove.bottom);
      expect(_order(c), ['v1', 'v2', 'v3']);
    });

    test('顺序落盘', () async {
      final c = await _container();
      await c.read(videoLibraryProvider.notifier).moveVideo('vc1', 'v2', VideoMove.top);

      final again = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(c.read(prefsProvider))],
      );
      addTearDown(again.dispose);
      expect(again.read(videoLibraryProvider).byId('vc1')!.videos.first.id, 'v2');
    });
  });

  group('家长密码', () {
    test('没改过就是缺省的 123456', () async {
      final c = await _container();
      expect(c.read(parentPasswordProvider), kDefaultParentPassword);
    });

    test('改过之后落盘', () async {
      final c = await _container();
      await c.read(parentPasswordProvider.notifier).set('246810');

      expect(c.read(parentPasswordProvider), '246810');
      expect(c.read(prefsProvider).getString(kParentPasswordKey), '246810');
    });

    testWidgets('「我的 → 偏好设置」里有家长密码，点开先要当前密码', (tester) async {
      _useTablet(tester);
      final c = await _container();
      await _pump(tester, c, const Scaffold(body: ProfileScreen()));

      expect(find.text('家长密码'), findsOneWidget);
      await tester.tap(find.text('家长密码'));
      await _settle(tester);

      expect(find.byKey(const ValueKey('parent-password-old')), findsOneWidget);
      expect(find.byKey(const ValueKey('parent-password-new')), findsOneWidget);
    });
  });

  group('孩子看到的分类列表', () {
    testWidgets('藏起来的视频不出现，也不占编号', (tester) async {
      final c = await _container(hidden: {'v2'});
      await _pumpCategory(tester, c);

      expect(find.text('小猪佩奇 第 1 集'), findsOneWidget);
      expect(find.text('汪汪队 第 2 集'), findsNothing);
      expect(find.text('海底小纵队'), findsOneWidget);
      expect(find.text('第 1 个'), findsOneWidget);
      expect(find.text('第 2 个'), findsOneWidget);
      expect(find.text('第 3 个'), findsNothing);
      expect(find.textContaining('共 2 个视频'), findsOneWidget);
    });

    testWidgets('全被收起来时只说一声，不给「去添加视频」', (tester) async {
      final c = await _container(hidden: {'v1', 'v2', 'v3'});
      await _pumpCategory(tester, c);

      expect(find.text('这个分类里暂时没有视频'), findsOneWidget);
      expect(find.text('家长把里面的视频都收起来了'), findsOneWidget);
      expect(find.text('去添加视频'), findsNothing);
    });

    testWidgets('首页和分类卡上的视频数只算孩子看得到的', (tester) async {
      final c = await _container(hidden: {'v2'});
      await _pump(tester, c, VideoLibraryScreen(onOpenManage: () {}));

      expect(find.text('共 1 个分类 · 2 个视频'), findsOneWidget);
      expect(find.text('2 个视频'), findsOneWidget);
    });

    testWidgets('「我的视频」那边照旧报真数，并标出藏了几个', (tester) async {
      final c = await _container(hidden: {'v2'});
      expect(c.read(videoLibraryProvider).totalVideos, 3);
      expect(c.read(videoLibraryProvider).visibleCount, 2);
    });
  });

  group('家长模式', () {
    testWidgets('点「家长设置」要密码，密码不对进不去', (tester) async {
      final c = await _container();
      await _pumpCategory(tester, c);

      await _enterParentMode(tester, password: '000000');

      expect(find.text('密码不对'), findsOneWidget, reason: '就地提示，框不关');
      expect(find.byKey(const ValueKey('arrange-v1')), findsNothing);
    });

    testWidgets('取消就还是孩子视角', (tester) async {
      final c = await _container();
      await _pumpCategory(tester, c);

      await tester.tap(find.byKey(const ValueKey('parent-mode-button')));
      await _settle(tester);
      await tester.tap(find.text('取消'));
      await _settle(tester);

      expect(find.byKey(const ValueKey('arrange-v1')), findsNothing);
    });

    testWidgets('密码对了，每张卡上多一个「⋮」，藏起来的也摆出来', (tester) async {
      final c = await _container(hidden: {'v2'});
      await _pumpCategory(tester, c);
      expect(find.text('汪汪队 第 2 集'), findsNothing);

      await _enterParentMode(tester);

      expect(find.byKey(const ValueKey('arrange-v1')), findsOneWidget);
      expect(find.byKey(const ValueKey('arrange-v3')), findsOneWidget);
      expect(find.text('汪汪队 第 2 集'), findsOneWidget, reason: '家长要看得到');
      expect(find.text('已隐藏'), findsOneWidget);
      expect(find.textContaining('已隐藏 1 个'), findsOneWidget);
    });

    testWidgets('家长模式里点卡片是「调整」，不是播放', (tester) async {
      final c = await _container();
      await _pumpCategory(tester, c);
      await _enterParentMode(tester);

      await tester.tap(find.text('小猪佩奇 第 1 集'));
      await _settle(tester);

      expect(find.byType(VideoPlayerScreen), findsNothing);
      expect(find.text('向前排'), findsOneWidget);
    });

    testWidgets('菜单里选「隐藏」→ 卡片标灰，退出家长模式就没了', (tester) async {
      final c = await _container();
      await _pumpCategory(tester, c);
      await _enterParentMode(tester);

      await tester.tap(find.byKey(const ValueKey('arrange-v2')));
      await _settle(tester);
      await tester.tap(find.text('隐藏（孩子看不到）'));
      await _settle(tester);

      expect(c.read(videoLibraryProvider).byId('vc1')!.hiddenCount, 1);
      expect(find.text('已隐藏'), findsOneWidget);

      // 「完成」退回孩子视角。
      await tester.tap(find.byKey(const ValueKey('parent-mode-button')));
      await _settle(tester);

      expect(find.text('汪汪队 第 2 集'), findsNothing);
      expect(find.byKey(const ValueKey('arrange-v2')), findsNothing);
    });

    testWidgets('菜单里选「置顶」→ 顺序变了', (tester) async {
      final c = await _container();
      await _pumpCategory(tester, c);
      await _enterParentMode(tester);

      await tester.tap(find.byKey(const ValueKey('arrange-v3')));
      await _settle(tester);
      await tester.tap(find.text('置顶'));
      await _settle(tester);

      expect(_order(c), ['v3', 'v1', 'v2']);
    });

    testWidgets('已经在头上时「向前排」和「置顶」点不动', (tester) async {
      final c = await _container();
      await _pumpCategory(tester, c);
      await _enterParentMode(tester);

      await tester.tap(find.byKey(const ValueKey('arrange-v1')));
      await _settle(tester);

      final up = tester.widget<ListTile>(
          find.ancestor(of: find.text('向前排'), matching: find.byType(ListTile)));
      final top = tester.widget<ListTile>(
          find.ancestor(of: find.text('置顶'), matching: find.byType(ListTile)));
      final down = tester.widget<ListTile>(
          find.ancestor(of: find.text('向后排'), matching: find.byType(ListTile)));
      expect(up.enabled, isFalse);
      expect(top.enabled, isFalse);
      expect(down.enabled, isTrue);
    });

    testWidgets('藏起来的那个，菜单里给的是「放出来给孩子看」', (tester) async {
      final c = await _container(hidden: {'v2'});
      await _pumpCategory(tester, c);
      await _enterParentMode(tester);

      await tester.tap(find.byKey(const ValueKey('arrange-v2')));
      await _settle(tester);

      expect(find.text('放出来给孩子看'), findsOneWidget);

      await tester.tap(find.text('放出来给孩子看'));
      await _settle(tester);

      expect(c.read(videoLibraryProvider).byId('vc1')!.hiddenCount, 0);
    });
  });
}
