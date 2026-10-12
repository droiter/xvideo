import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xvideo/app.dart';
import 'package:xvideo/core/constants.dart';
import 'package:xvideo/state/providers.dart';

Future<Widget> _app({Map<String, Object> seed = const {}}) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const XVideoApp(),
  );
}

/// 看过引导页（[loggedIn] 决定本机有没有登录态）。
Map<String, Object> _seed({bool dark = false, bool loggedIn = true}) => {
      kSeenOnboardingKey: true,
      kDarkModeKey: dark,
      if (loggedIn)
        kSessionKey: jsonEncode(
            {'id': 'u1', 'name': '小明', 'email': 'demo@xvideo.app'}),
    };

int _tabIndex(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack).first).index!;

/// 「我的」页内容一屏放不下（最底下那张卡在 600 高的默认视口里会被 ListView
/// 懒加载挡住），要连着看底下几项的用例按平板尺寸跑。
void _useTablet(WidgetTester tester) {
  tester.view.physicalSize = const Size(1024, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('首次启动看引导页，跳过就进主界面，不用先登录', (tester) async {
    await tester.pumpWidget(await _app());

    expect(find.text('手机和平板都能看'), findsOneWidget);
    expect(find.text('开始看视频'), findsNothing);

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(_tabIndex(tester), kVideoTab);
    // 没有账号也直接进得来：登录页一个字都不该出现。
    expect(find.text('还没有账号？立即注册'), findsNothing);
    expect(find.text('登录'), findsNothing);
  });

  testWidgets('没有账号也能进主界面，只有「看视频」和「我的」两格', (tester) async {
    await tester.pumpWidget(await _app(seed: _seed(loggedIn: false)));

    expect(_tabIndex(tester), kVideoTab);
    expect(find.byKey(const ValueKey('tab-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-1')), findsOneWidget);
    // 课程、进度、答题这些都不在这个 App 里。
    for (final gone in ['课程', '进度', '看图找规律', '看图问答']) {
      expect(find.text(gone), findsNothing, reason: '$gone 不该出现');
    }
  });

  testWidgets('未登录时「我的」有登录入口，注册完回到「我的」显示账号', (tester) async {
    _useTablet(tester);
    await tester.pumpWidget(await _app(seed: _seed(loggedIn: false)));
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();

    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('退出登录'), findsNothing);

    await tester.tap(find.text('未登录'));
    await tester.pumpAndSettle();
    expect(find.text('还没有账号？立即注册'), findsOneWidget);

    await tester.tap(find.text('还没有账号？立即注册'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '小明');
    await tester.enterText(find.byType(TextField).at(1), 'demo@xvideo.app');
    await tester.enterText(find.byType(TextField).at(2), '1234');
    await tester.tap(find.text('注册并登录'));
    await tester.pumpAndSettle();

    // 注册完自动退回「我的」，未登录卡片换成账号卡。
    expect(find.text('未登录'), findsNothing);
    expect(find.text('小明'), findsOneWidget);
    expect(find.text('demo@xvideo.app'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(_tabIndex(tester), kProfileTab);
  });

  testWidgets('登录页点返回不改登录态，直接回到「我的」', (tester) async {
    await tester.pumpWidget(await _app(seed: _seed(loggedIn: false)));
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('未登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('还没有账号？立即注册'), findsNothing);
    expect(find.text('未登录'), findsOneWidget);
    expect(_tabIndex(tester), kProfileTab);
  });

  testWidgets('退出登录后还在主界面，账号卡变回未登录', (tester) async {
    _useTablet(tester);
    await tester.pumpWidget(await _app(seed: _seed()));
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();

    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('demo@xvideo.app'), findsNothing);
    expect(_tabIndex(tester), kProfileTab);
  });

  testWidgets('「我的」里有账号、我的视频、深色模式，没有课程那套设置', (tester) async {
    _useTablet(tester);
    await tester.pumpWidget(await _app(seed: _seed()));

    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();

    expect(_tabIndex(tester), kProfileTab);
    expect(find.text('demo@xvideo.app'), findsOneWidget);
    expect(find.text('我的视频'), findsOneWidget);
    expect(find.text('深色模式'), findsOneWidget);
    expect(find.text('关于 xVideo'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    // 跟着课程 / 答题走的那两项设置不该搬过来。
    expect(find.text('学习提醒'), findsNothing);
    expect(find.text('朗读语速'), findsNothing);
  });

  testWidgets('点开「我的视频」进到视频管理页', (tester) async {
    await tester.pumpWidget(await _app(seed: _seed()));
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的视频'));
    await tester.pumpAndSettle();

    expect(find.text('新建分类'), findsOneWidget);
  });

  testWidgets('深色模式开关写进本机设置', (tester) async {
    await tester.pumpWidget(await _app(seed: _seed()));
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kDarkModeKey), isTrue);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });
}
