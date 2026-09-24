import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 根据分类 / 视频 id 生成稳定的封面渐变色。
List<Color> coverGradient(String id) {
  final sum = id.codeUnits.fold<int>(0, (a, b) => a + b);
  return kCoverPalette[sum % kCoverPalette.length];
}
