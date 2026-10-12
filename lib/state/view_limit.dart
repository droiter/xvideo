import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import 'prefs.dart';

/// 取当前时间。测试里覆盖它，就能把「M 分钟」拨快。
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 一个视频的观看记录：连着看过几遍、锁到什么时候。
@immutable
class ViewRecord {
  const ViewRecord({this.count = 0, this.lockedUntil});

  factory ViewRecord.fromJson(Map<String, dynamic> json) {
    final until = (json['until'] as num?)?.toInt();
    return ViewRecord(
      count: (json['count'] as num?)?.toInt() ?? 0,
      lockedUntil:
          until == null ? null : DateTime.fromMillisecondsSinceEpoch(until),
    );
  }

  /// 连着看过几遍（到上限时锁住，解锁后整条记录丢掉、从头算）。
  final int count;

  /// 锁到什么时候；没锁是 null。
  final DateTime? lockedUntil;

  Map<String, dynamic> toJson() => {
        'count': count,
        if (lockedUntil != null) 'until': lockedUntil!.millisecondsSinceEpoch,
      };

  bool lockedAt(DateTime now) =>
      lockedUntil != null && now.isBefore(lockedUntil!);

  /// 还有几分钟能看。向上取整（还剩 20 秒也报「1 分钟」），没锁就是 0。
  int minutesLeft(DateTime now) {
    if (!lockedAt(now)) return 0;
    return (lockedUntil!.difference(now).inSeconds / 60).ceil().clamp(1, 9999);
  }
}

/// 防反复观看的设置：开关 + 连看几遍 + 锁多少分钟。
@immutable
class ViewLimitSettings {
  const ViewLimitSettings({
    this.enabled = true,
    this.maxViews = kDefaultViewLimit,
    this.lockMinutes = kDefaultLockMinutes,
  });

  final bool enabled;

  /// 连着看够这么多遍就锁住。
  final int maxViews;

  /// 锁住多少分钟。
  final int lockMinutes;

  ViewLimitSettings copyWith({bool? enabled, int? maxViews, int? lockMinutes}) =>
      ViewLimitSettings(
        enabled: enabled ?? this.enabled,
        maxViews: maxViews ?? this.maxViews,
        lockMinutes: lockMinutes ?? this.lockMinutes,
      );
}

class ViewLimitSettingsController extends Notifier<ViewLimitSettings> {
  @override
  ViewLimitSettings build() {
    final prefs = ref.watch(prefsProvider);
    return ViewLimitSettings(
      // 没存过就是开的：这是家长要的功能，缺省打开。
      enabled: prefs.getBool(kViewLimitOnKey) ?? true,
      maxViews: _positive(prefs.getInt(kViewLimitCountKey), kDefaultViewLimit),
      lockMinutes:
          _positive(prefs.getInt(kViewLimitMinutesKey), kDefaultLockMinutes),
    );
  }

  /// 存过脏数字（0、负数）就当没存过。
  static int _positive(int? value, int fallback) =>
      value != null && value > 0 ? value : fallback;

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    await ref.read(prefsProvider).setBool(kViewLimitOnKey, value);
  }

  Future<void> setMaxViews(int value) async {
    state = state.copyWith(maxViews: value);
    await ref.read(prefsProvider).setInt(kViewLimitCountKey, value);
  }

  Future<void> setLockMinutes(int value) async {
    state = state.copyWith(lockMinutes: value);
    await ref.read(prefsProvider).setInt(kViewLimitMinutesKey, value);
  }
}

/// 每个视频连着看了几遍、锁没锁。全机一份，落盘到 SharedPreferences。
///
/// 一遍是这么算的：**点开播放页就算**（点进去马上退也算），不看到播完。
/// 连着看够 N 遍就把这个视频锁 M 分钟——列表里缩略图变灰、点了不播；
/// 锁满之后记录整条丢掉，计数从头开始。
class ViewLimitController extends Notifier<Map<String, ViewRecord>> {
  @override
  Map<String, ViewRecord> build() => _load();

  DateTime _now() => ref.read(nowProvider)();

  /// 开了开关才计数、才锁；关掉后已经在锁里的视频也立刻能看。
  bool _enabled() => ref.read(viewLimitSettingsProvider).enabled;

  /// 打开播放页记一遍。到 N 遍就锁 M 分钟。
  Future<void> recordView(String videoId) async {
    if (!_enabled()) return;
    final settings = ref.read(viewLimitSettingsProvider);
    final now = _now();

    final next = _live(state, now);
    final count = (next[videoId]?.count ?? 0) + 1;
    next[videoId] = count >= settings.maxViews
        ? ViewRecord(
            count: count,
            lockedUntil: now.add(Duration(minutes: settings.lockMinutes)))
        : ViewRecord(count: count);

    await _save(next);
  }

  /// 时间到了就把过期的锁丢掉（计数也跟着清零）。界面上的定时器到点喊一声，
  /// 省得库里一直留着一把早就过点的锁。
  void pruneExpired() {
    final next = _live(state, _now());
    if (next.length != state.length) unawaited(_save(next));
  }

  /// 这个视频现在锁着吗？锁着就返回剩下的分钟数，否则返回 0。
  int minutesLeft(String videoId) =>
      _enabled() ? (state[videoId]?.minutesLeft(_now()) ?? 0) : 0;

  bool isLocked(String videoId) => minutesLeft(videoId) > 0;

  /// 丢掉过期的锁（并把它们的计数清零）。
  Map<String, ViewRecord> _live(Map<String, ViewRecord> records, DateTime now) =>
      Map<String, ViewRecord>.from(records)
        ..removeWhere((_, r) => r.lockedUntil != null && !r.lockedAt(now));

  Map<String, ViewRecord> _load() {
    try {
      final raw = ref.read(prefsProvider).getString(kViewLimitStateKey);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return _live(
        {
          for (final e in decoded.entries)
            '${e.key}': ViewRecord.fromJson(
                (e.value as Map).cast<String, dynamic>()),
        },
        _now(),
      );
    } catch (_) {
      // 脏数据当没记录。
      return const {};
    }
  }

  Future<void> _save(Map<String, ViewRecord> next) async {
    state = next;
    await ref
        .read(prefsProvider)
        .setString(kViewLimitStateKey, _encode(next));
  }

  static String _encode(Map<String, ViewRecord> records) => jsonEncode({
        for (final e in records.entries) e.key: e.value.toJson(),
      });
}

final viewLimitSettingsProvider =
    NotifierProvider<ViewLimitSettingsController, ViewLimitSettings>(
        ViewLimitSettingsController.new);

final viewLimitProvider =
    NotifierProvider<ViewLimitController, Map<String, ViewRecord>>(
        ViewLimitController.new);
