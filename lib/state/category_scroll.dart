import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 每个分类列表上次退出时滚到哪儿（像素）。
///
/// 只放内存里：从分类退回「看视频」、再点进去能接着看，关掉 App 就从头开始。
class CategoryScroll extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  double offsetOf(String categoryId) => state[categoryId] ?? 0;

  void save(String categoryId, double offset) {
    if (state[categoryId] == offset) return;
    state = {...state, categoryId: offset};
  }
}

final categoryScrollProvider =
    NotifierProvider<CategoryScroll, Map<String, double>>(CategoryScroll.new);
