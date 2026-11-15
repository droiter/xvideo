import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xvideo/core/constants.dart';
import 'package:xvideo/features/video/video_category_screen.dart';
import 'package:xvideo/features/video/video_library_screen.dart';
import 'package:xvideo/state/providers.dart';

/// 一个分类放 [count] 个视频，够滚起来。
String _libraryJson({required int count}) => jsonEncode({
      'categories': [
        {
          'id': 'vc1',
          'name': '动画片',
          'videos': [
            for (var i = 0; i < count; i++)
              {
                'id': 'v$i',
                'title': '视频 $i',
                'source': 'https://example.com/v$i.mp4',
                'kind': 'link',
              },
          ],
        },
      ],
    });

Future<ProviderContainer> _container({int count = 30}) async {
  SharedPreferences.setMockInitialValues({
    kVideoLibraryKey: _libraryJson(count: count),
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

Future<void> _pumpLibrary(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(body: VideoLibraryScreen(onOpenManage: () {})),
    ),
  ));
  await tester.pump();
}

/// 手机视口：默认 800×600 太宽，卡片一行三个，滚不了多少。
void _usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 分类页里那个网格（「看视频」首页自己也有一个网格，别拿错）。
Finder _categoryGrid() => find.descendant(
      of: find.byType(VideoCategoryScreen),
      matching: find.byType(GridView),
    );

double _offset(WidgetTester tester) =>
    tester.widget<GridView>(_categoryGrid()).controller!.offset;

Future<void> _openCategory(WidgetTester tester) async {
  await tester.tap(find.text('动画片'));
  await _settle(tester);
}

void main() {
  testWidgets('退回「看视频」再点进同一个分类，接着上次的位置往下看', (tester) async {
    _usePhone(tester);
    final c = await _container();
    await _pumpLibrary(tester, c);

    await _openCategory(tester);
    expect(find.byType(VideoCategoryScreen), findsOneWidget);

    await tester.drag(_categoryGrid(), const Offset(0, -500));
    await tester.pump();
    final scrolled = _offset(tester);
    expect(scrolled, greaterThan(0));

    // 按返回键退回「看视频」。
    await tester.pageBack();
    await _settle(tester);
    expect(find.byType(VideoCategoryScreen), findsNothing);

    // 再点同一个分类：应该停在刚才那儿，而不是从头开始。
    await _openCategory(tester);
    expect(_offset(tester), scrolled);
  });

  testWidgets('换个分类还是从顶上开始（位置按分类各记各的）', (tester) async {
    _usePhone(tester);
    final c = await _container();
    await _pumpLibrary(tester, c);

    await _openCategory(tester);
    await tester.drag(_categoryGrid(), const Offset(0, -500));
    await tester.pump();
    expect(_offset(tester), greaterThan(0));

    // 记下来的位置只属于 vc1。
    expect(c.read(categoryScrollProvider)['vc1'], greaterThan(0));
    expect(c.read(categoryScrollProvider)['vc2'], isNull);
  });
}
