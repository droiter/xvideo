import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xvideo/core/constants.dart';
import 'package:xvideo/features/profile/profile_screen.dart';
import 'package:xvideo/features/video/video_category_screen.dart';
import 'package:xvideo/features/video/video_player_screen.dart';
import 'package:xvideo/state/providers.dart';

/// 1 个分类、1 个视频，够验证「锁一个视频」这件事了。
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

/// 一条已有的观看记录（[locked] 时锁到 [until]）。
Map<String, Object> _seed({
  Map<String, Object> extra = const {},
  int? count,
  DateTime? until,
  bool? enabled,
}) =>
    {
      kVideoLibraryKey: _libraryJson(),
      if (count != null)
        kViewLimitStateKey: jsonEncode({
          'v1': {
            'count': count,
            if (until != null) 'until': until.millisecondsSinceEpoch,
          },
        }),
      if (enabled != null) kViewLimitOnKey: enabled,
      ...extra,
    };

Future<SharedPreferences> _prefs(Map<String, Object> seed) async {
  SharedPreferences.setMockInitialValues(seed);
  return SharedPreferences.getInstance();
}

/// 铺好 prefs（和可选的假时钟）的容器。
Future<ProviderContainer> _container(
  Map<String, Object> seed, {
  DateTime Function()? now,
}) async {
  final prefs = await _prefs(seed);
  final c = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(prefs),
    if (now != null) nowProvider.overrideWithValue(now),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// 把某台「设备」的假时钟包一层，测试里随手往前拨。
class _Clock {
  _Clock(this.now);

  DateTime now;

  void advance(Duration d) => now = now.add(d);
}

/// 页面里有入场动画，统一用显式 pump 推进，不用 pumpAndSettle。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 打开分类页（[clock] 非空就把时间换成假的）。
Future<void> _pumpCategory(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: VideoCategoryScreen(categoryId: 'vc1')),
  ));
  await tester.pump();
}

/// 点开视频再退出来——「看过一遍」就是点开这一下。
Future<void> _openAndBack(WidgetTester tester) async {
  await tester.tap(find.text('小猪佩奇 第 1 集'));
  await _settle(tester);
  await tester.pageBack();
  await _settle(tester);
}

void main() {
  group('观看计数（点开就算一遍）', () {
    testWidgets('点开播放页就记一遍，连看够 N 遍后锁住', (tester) async {
      final c = await _container(_seed());
      await _pumpCategory(tester, c);

      await _openAndBack(tester);
      expect(c.read(viewLimitProvider)['v1']!.count, 1);
      expect(c.read(viewLimitProvider)['v1']!.lockedUntil, isNull);

      await _openAndBack(tester);
      await _openAndBack(tester);

      // 缺省连看 3 遍就锁 30 分钟。
      final rec = c.read(viewLimitProvider)['v1']!;
      expect(rec.count, 3);
      expect(rec.lockedUntil, isNotNull);
      expect(c.read(viewLimitProvider.notifier).minutesLeft('v1'), 30);

      // 落盘了：换一个容器读回来还是锁着的。
      final again = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
      ]);
      addTearDown(again.dispose);
      expect(again.read(viewLimitProvider)['v1']!.count, 3);
      expect(again.read(viewLimitProvider)['v1']!.lockedUntil, isNotNull);
    });

    testWidgets('锁满 M 分钟后自动解锁，计数清零', (tester) async {
      final clock = _Clock(DateTime(2026, 10, 11, 9, 0));
      final c = await _container(
        _seed(count: 3, until: DateTime(2026, 10, 11, 9, 30)),
        now: () => clock.now,
      );
      await _pumpCategory(tester, c);

      expect(find.byType(ColorFiltered), findsOneWidget);
      expect(c.read(viewLimitProvider.notifier).isLocked('v1'), isTrue);

      // 时间拨到锁满之后，界面上的定时器自己醒过来放行。
      clock.advance(const Duration(minutes: 31));
      await tester.pump(const Duration(minutes: 31));
      await tester.pump();

      expect(c.read(viewLimitProvider), isEmpty);
      expect(find.byType(ColorFiltered), findsNothing);

      // 解锁后从头算：再点开是第 1 遍，不接着上次的 3 遍往上加。
      await _openAndBack(tester);
      expect(c.read(viewLimitProvider)['v1']!.count, 1);
      expect(c.read(viewLimitProvider)['v1']!.lockedUntil, isNull);
    });

    testWidgets('关掉开关就不计数，已经在锁里的也立刻能看', (tester) async {
      final clock = _Clock(DateTime(2026, 10, 11, 9, 0));
      final c = await _container(
        _seed(
          count: 3,
          until: DateTime(2026, 10, 11, 9, 30),
          enabled: false,
        ),
        now: () => clock.now,
      );
      await _pumpCategory(tester, c);

      expect(find.byType(ColorFiltered), findsNothing);

      await tester.tap(find.text('小猪佩奇 第 1 集'));
      await _settle(tester);
      expect(find.byType(VideoPlayerScreen), findsOneWidget);
      // 开关关着就不再记账。
      expect(c.read(viewLimitProvider)['v1']!.count, 3);
    });

    test('脏数据当没记录，不炸', () async {
      final c = await _container({kViewLimitStateKey: '不是 json'});
      expect(c.read(viewLimitProvider), isEmpty);
      expect(c.read(viewLimitSettingsProvider).maxViews, kDefaultViewLimit);
    });

    test('设置里的脏数字（0、负数）退回缺省值', () async {
      final c = await _container({kViewLimitCountKey: 0, kViewLimitMinutesKey: -5});
      final s = c.read(viewLimitSettingsProvider);
      expect(s.maxViews, kDefaultViewLimit);
      expect(s.lockMinutes, kDefaultLockMinutes);
    });
  });

  group('锁住的视频在列表里', () {
    testWidgets('缩略图变灰、点了不进播放页，只给一句解释', (tester) async {
      final clock = _Clock(DateTime(2026, 10, 11, 9, 0));
      final c = await _container(
        _seed(count: 3, until: DateTime(2026, 10, 11, 9, 20)),
        now: () => clock.now,
      );
      await _pumpCategory(tester, c);

      expect(find.byType(ColorFiltered), findsOneWidget);
      expect(find.text('已看 3 遍'), findsOneWidget);
      expect(find.text('20 分钟后'), findsOneWidget);
      expect(find.text('歇 20 分钟'), findsOneWidget);

      await tester.tap(find.text('小猪佩奇 第 1 集'));
      await _settle(tester);

      expect(find.byType(VideoPlayerScreen), findsNothing);
      expect(find.textContaining('连着看了 3 遍'), findsOneWidget);
      // 没进播放页，就不该再记一遍。
      expect(c.read(viewLimitProvider)['v1']!.count, 3);
    });

    testWidgets('锁着的时候不会把别的视频一起变灰', (tester) async {
      final clock = _Clock(DateTime(2026, 10, 11, 9, 0));
      final c = await _container(
        {
          kVideoLibraryKey: jsonEncode({
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
                    'source': 'https://example.com/p2.mp4',
                    'kind': 'link',
                  },
                ],
              },
            ],
          }),
          kViewLimitStateKey: jsonEncode({
            'v1': {
              'count': 3,
              'until': DateTime(2026, 10, 11, 9, 20).millisecondsSinceEpoch,
            },
          }),
        },
        now: () => clock.now,
      );
      await _pumpCategory(tester, c);

      expect(find.byType(ColorFiltered), findsOneWidget);
      await tester.tap(find.text('汪汪队 第 2 集'));
      await _settle(tester);
      expect(find.byType(VideoPlayerScreen), findsOneWidget);
    });
  });

  group('「我的 → 偏好设置」里的开关', () {
    Future<ProviderContainer> pumpProfile(WidgetTester tester,
        {Map<String, Object> seed = const {}}) async {
      final c = await _container(seed);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: ProfileScreen())),
      ));
      await tester.pump();
      return c;
    }

    testWidgets('缺省开着，说明里写着当前的遍数和分钟数', (tester) async {
      await pumpProfile(tester);

      expect(find.text('限制反复观看'), findsOneWidget);
      expect(find.textContaining('连看 3 遍就锁 30 分钟'), findsOneWidget);
      expect(find.text('连看几遍就锁住'), findsOneWidget);
      expect(find.text('3 遍'), findsOneWidget);
      expect(find.text('锁住多久'), findsOneWidget);
      expect(find.text('30 分钟'), findsOneWidget);
    });

    testWidgets('改遍数和分钟数会落盘并立刻生效', (tester) async {
      final c = await pumpProfile(tester);

      await tester.tap(find.text('连看几遍就锁住'));
      await _settle(tester);
      await tester.tap(find.text('5 遍'));
      await _settle(tester);

      await tester.tap(find.text('锁住多久'));
      await _settle(tester);
      await tester.tap(find.text('10 分钟'));
      await _settle(tester);

      final s = c.read(viewLimitSettingsProvider);
      expect(s.maxViews, 5);
      expect(s.lockMinutes, 10);
      expect(find.textContaining('连看 5 遍就锁 10 分钟'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(kViewLimitCountKey), 5);
      expect(prefs.getInt(kViewLimitMinutesKey), 10);
    });

    testWidgets('关掉开关后两个数字项收起来，开关状态落盘', (tester) async {
      final c = await pumpProfile(tester);

      await tester.tap(find.text('限制反复观看'));
      await _settle(tester);

      expect(c.read(viewLimitSettingsProvider).enabled, isFalse);
      expect(find.textContaining('想看几遍看几遍'), findsOneWidget);
      expect(find.text('连看几遍就锁住'), findsNothing);
      expect(find.text('锁住多久'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kViewLimitOnKey), isFalse);
      // 关开关不动已经调好的数字。
      expect(c.read(viewLimitSettingsProvider).maxViews, kDefaultViewLimit);
    });

    testWidgets('关掉后重新打开，还是上次调好的数字', (tester) async {
      final c = await pumpProfile(tester, seed: {
        kViewLimitCountKey: 5,
        kViewLimitMinutesKey: 60,
      });

      expect(find.textContaining('连看 5 遍就锁 60 分钟'), findsOneWidget);

      await tester.tap(find.text('限制反复观看'));
      await _settle(tester);
      await tester.tap(find.text('限制反复观看'));
      await _settle(tester);

      expect(c.read(viewLimitSettingsProvider).enabled, isTrue);
      expect(find.textContaining('连看 5 遍就锁 60 分钟'), findsOneWidget);
    });
  });
}
