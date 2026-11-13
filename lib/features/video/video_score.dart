import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 分数对应的文字颜色：5 分及以下就用 [base]；超过 5 分往红色走，10 分最红。
Color scoreColor(int score, {Color base = Colors.white}) {
  final t = ((score - kDefaultVideoScore) /
          (kMaxVideoScore - kDefaultVideoScore))
      .clamp(0.0, 1.0);
  return Color.lerp(base, const Color(0xFFFF1744), t)!;
}
