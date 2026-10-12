/// xVideo 应用级常量。
library;

import 'package:flutter/material.dart' show Color;

const String kAppName = 'xVideo';
const String kAppTagline = '家庭视频库 · 平板 / 手机';
const String kVersion = '0.1.0';

// SharedPreferences 存储键
const String kUsersKey = 'xvideo_users'; // email -> {id,name,password}
const String kSessionKey = 'xvideo_session'; // 当前登录用户
const String kSeenOnboardingKey = 'xvideo_seen_onboarding';
const String kDarkModeKey = 'xvideo_dark';

/// 播放页的「循环播放」开关。全机共用一份，下次进播放页照旧。
const String kVideoLoopKey = 'xvideo_video_loop';

/// 视频库：分类 + 视频。全机共用一份（家长加片，孩子看）。
const String kVideoLibraryKey = 'xvideo_video_lib';

/// 防反复观看的设置：总开关 / 连看几遍后锁住 / 锁住多少分钟。
/// 全机共用一份，缺省是开的。
const String kViewLimitOnKey = 'xvideo_view_limit_on';
const String kViewLimitCountKey = 'xvideo_view_limit_n';
const String kViewLimitMinutesKey = 'xvideo_view_limit_m';

/// 每个视频各自「连着看了几遍、锁到什么时候」。全机共用一份。
const String kViewLimitStateKey = 'xvideo_view_limit_state';

/// 防反复观看的缺省值：连看 3 遍锁 30 分钟。
const int kDefaultViewLimit = 3;
const int kDefaultLockMinutes = 30;

/// 设置里能挑的「看几遍」和「锁多久」，家长不用手打数字。
const List<int> kViewLimitChoices = [1, 2, 3, 4, 5, 6, 8, 10, 15];
const List<int> kLockMinuteChoices = [1, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180];

// 底部选项卡下标
const int kVideoTab = 0;
const int kProfileTab = 1;

/// 家长密码。分类列表里「隐藏视频 / 调整顺序」要输它，孩子猜不出来就改不动。
/// 没改过就是 [kDefaultParentPassword]。
const String kParentPasswordKey = 'xvideo_parent_password';

/// 家长密码的缺省值（跟 xedu 一致，家长可以改成自己的）。
const String kDefaultParentPassword = '123456';

/// 家长密码最少几位。
const int kMinParentPasswordLength = 4;

// 分类封面渐变调色板（seed 取模得到稳定配色）
const List<List<Color>> kCoverPalette = [
  [Color(0xFF4F6BFF), Color(0xFF9A5CFF)], // 靛紫
  [Color(0xFF00B8A9), Color(0xFF0F8B8D)], // 青绿
  [Color(0xFFFF7043), Color(0xFFFF3D6E)], // 橙红
  [Color(0xFF7E57C2), Color(0xFF4A148C)], // 深紫
  [Color(0xFF26A69A), Color(0xFF00897B)], // 绿松
  [Color(0xFFFFA726), Color(0xFFF57C00)], // 琥珀
  [Color(0xFF42A5F5), Color(0xFF1565C0)], // 天蓝
  [Color(0xFFEC407A), Color(0xFFAD1457)], // 玫红
];
