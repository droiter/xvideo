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

/// 视频库：分类 + 视频。全机共用一份（家长加片，孩子看）。
const String kVideoLibraryKey = 'xvideo_video_lib';

// 底部选项卡下标
const int kVideoTab = 0;
const int kProfileTab = 1;

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
