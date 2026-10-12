import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../features/video/video_import.dart' show storedFingerprintOf;
import 'prefs.dart';

/// 视频来源：网络链接 / 本机文件。
enum VideoKind { link, file }

/// 一个视频条目。[source] 对 [VideoKind.link] 是 http(s) 地址，
/// 对 [VideoKind.file] 是 App 私有目录下的本地绝对路径。
@immutable
class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    required this.source,
    required this.kind,
    this.fingerprint = '',
    this.hidden = false,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
        id: json['id'] as String,
        title: json['title'] as String? ?? '未命名视频',
        source: json['source'] as String? ?? '',
        kind: json['kind'] == 'file' ? VideoKind.file : VideoKind.link,
        fingerprint: json['fingerprint'] as String? ?? '',
        hidden: json['hidden'] == true,
      );

  final String id;
  final String title;
  final String source;
  final VideoKind kind;

  /// 查重指纹，只有本机视频才有：原文件名 + 字节数。
  ///
  /// 视频复制进 App 私有目录时会换名字（前面挂时间戳），光看 [source] 认不出
  /// 「同一个文件又选了一遍」，所以趁还在源路径上先记下这个特征。
  final String fingerprint;

  /// 家长把这个视频收起来了：分类列表里不给孩子看，家长模式下才显出来。
  /// 只是从列表里藏起来，视频本身没删。
  final bool hidden;

  bool get isLocal => kind == VideoKind.file;

  VideoItem copyWith({String? title, bool? hidden}) => VideoItem(
        id: id,
        title: title ?? this.title,
        source: source,
        kind: kind,
        fingerprint: fingerprint,
        hidden: hidden ?? this.hidden,
      );

  /// 查重用的键：有指纹的用指纹，没有的（链接、早先存下的数据）用 [source]。
  /// 链接的 source 本身就是地址；老的本机视频 source 是各自唯一的路径，
  /// 只会在同一条记录上撞到自己，不会把两个视频误判成一个。
  String get dedupKey => keyOf(source, fingerprint);

  static String keyOf(String source, String fingerprint) =>
      fingerprint.isNotEmpty ? fingerprint : source;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'source': source,
        'kind': kind.name,
        'fingerprint': fingerprint,
        // 没被收起来的就不写这个键，省得把老数据的格式搅乱。
        if (hidden) 'hidden': true,
      };
}

/// 一个视频分类，内含若干视频。
@immutable
class VideoCategory {
  const VideoCategory({
    required this.id,
    required this.name,
    this.videos = const [],
  });

  factory VideoCategory.fromJson(Map<String, dynamic> json) => VideoCategory(
        id: json['id'] as String,
        name: json['name'] as String? ?? '未命名分类',
        videos: [
          for (final v in (json['videos'] as List? ?? const []))
            VideoItem.fromJson((v as Map).cast<String, dynamic>()),
        ],
      );

  final String id;
  final String name;
  final List<VideoItem> videos;

  /// 给孩子看的那些：家长收起来的（[VideoItem.hidden]）不算。
  List<VideoItem> get visibleVideos =>
      [for (final v in videos) if (!v.hidden) v];

  /// 被家长收起来的有几个。
  int get hiddenCount => videos.length - visibleVideos.length;

  /// 分类里有没有撞上 [dedupKey] 的视频。
  VideoItem? findDuplicate(String dedupKey) {
    for (final v in videos) {
      if (v.dedupKey == dedupKey) return v;
    }
    return null;
  }

  /// 分类里重名时给 [title] 加编号：「小猪佩奇」→「小猪佩奇 (2)」。
  /// 名字本身就带编号的，从同一个根名字往上试，免得叠成「(2) (2)」。
  String freeTitle(String title) {
    final taken = {for (final v in videos) v.title};
    if (!taken.contains(title)) return title;
    final m = RegExp(r'^(.*?)\s*\((\d+)\)$').firstMatch(title);
    final root = (m?.group(1) ?? title).trim();
    for (var n = 2;; n++) {
      final candidate = '$root ($n)';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  VideoCategory copyWith({String? name, List<VideoItem>? videos}) =>
      VideoCategory(
        id: id,
        name: name ?? this.name,
        videos: videos ?? this.videos,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'videos': [for (final v in videos) v.toJson()],
      };
}

/// 整份视频库。
@immutable
class VideoLibrary {
  const VideoLibrary({this.categories = const []});

  factory VideoLibrary.fromJson(Map<String, dynamic> json) => VideoLibrary(
        categories: [
          for (final c in (json['categories'] as List? ?? const []))
            VideoCategory.fromJson((c as Map).cast<String, dynamic>()),
        ],
      );

  final List<VideoCategory> categories;

  bool get isEmpty => categories.isEmpty;

  /// 库里一共几个视频（家长收起来的也算）。
  int get totalVideos =>
      categories.fold(0, (sum, c) => sum + c.videos.length);

  /// 孩子能看到的几个（收起来的不算）。列表上露给孩子的数字用它，
  /// 「我的」那边报总数用 [totalVideos]。
  int get visibleCount =>
      categories.fold(0, (sum, c) => sum + c.visibleVideos.length);

  VideoCategory? byId(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'categories': [for (final c in categories) c.toJson()],
      };
}

/// [VideoLibraryController.addVideo] 的结果。
///
/// [added] 为 false 说明这次没加进去（撞上重复视频，或者分类已经不在了），
/// 此时 [title] 是已经在库里的那个视频的名字，正好拿去告诉家长为什么没加。
@immutable
class AddVideoResult {
  const AddVideoResult({required this.added, required this.title});

  final bool added;

  /// 最终用的名字。加进去了就是可能带了编号的新名字，没加进去就是原来的名字。
  final String title;
}

/// 家长在分类列表里怎么挪一个视频，见 [VideoLibraryController.moveVideo]。
enum VideoMove { up, down, top, bottom }

/// 视频库的增删改，落盘到 SharedPreferences（全机一份）。
class VideoLibraryController extends Notifier<VideoLibrary> {
  @override
  VideoLibrary build() => _load();

  VideoLibrary _load() {
    try {
      final raw = ref.read(prefsProvider).getString(kVideoLibraryKey);
      if (raw == null || raw.isEmpty) return const VideoLibrary();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const VideoLibrary();
      return VideoLibrary.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return const VideoLibrary();
    }
  }

  Future<void> _save(VideoLibrary next) async {
    state = next;
    await ref
        .read(prefsProvider)
        .setString(kVideoLibraryKey, jsonEncode(next.toJson()));
  }

  /// 新建分类，返回新分类的 id。
  Future<String> addCategory(String name) async {
    final id = 'vc${DateTime.now().microsecondsSinceEpoch}';
    await _save(VideoLibrary(categories: [
      ...state.categories,
      VideoCategory(id: id, name: name.trim()),
    ]));
    return id;
  }

  Future<void> renameCategory(String categoryId, String name) async {
    await _save(VideoLibrary(categories: [
      for (final c in state.categories)
        c.id == categoryId ? c.copyWith(name: name.trim()) : c,
    ]));
  }

  /// 删除分类（连同分类里的视频记录）。
  Future<void> removeCategory(String categoryId) async {
    await _save(VideoLibrary(
      categories: [
        for (final c in state.categories)
          if (c.id != categoryId) c,
      ],
    ));
  }

  /// 往 [categoryId] 里加一个视频，返回最后的结果。
  ///
  /// 查重只看这个分类（见 [findDuplicate]）：分类里已经有同一个视频就不加——
  /// 链接看地址，本机视频看 [fingerprint]（原文件名 + 字节数）。名字在这个分类
  /// 里重了则自动加编号（「小猪佩奇」→「小猪佩奇 (2)」），别的分类里叫什么名字
  /// 就不管了。
  Future<AddVideoResult> addVideo(
    String categoryId, {
    required String title,
    required String source,
    VideoKind kind = VideoKind.link,
    String fingerprint = '',
  }) async {
    final category = state.byId(categoryId);
    final trimmed = title.trim().isEmpty ? '未命名视频' : title.trim();
    if (category == null) return AddVideoResult(added: false, title: trimmed);

    final dup = await findDuplicate(
        categoryId, VideoItem.keyOf(source, fingerprint));
    if (dup != null) return AddVideoResult(added: false, title: dup.title);

    final item = VideoItem(
      id: 'v${DateTime.now().microsecondsSinceEpoch}',
      title: category.freeTitle(trimmed),
      source: source,
      kind: kind,
      fingerprint: fingerprint,
    );
    await _save(VideoLibrary(categories: [
      for (final c in state.categories)
        c.id == categoryId
            ? c.copyWith(videos: [...c.videos, item])
            : c,
    ]));
    return AddVideoResult(added: true, title: item.title);
  }

  /// 这个分类里已经有同一个视频了吗？有就返回库里那一条，没有返回 null。
  ///
  /// [dedupKey] 是新条目的查重键（[VideoItem.keyOf]）：链接是地址，本机视频是
  /// 「原文件名 + 字节数」。先按查重键直接比；比不出来再看本机视频那条老路——
  /// 早先版本的记录没存指纹，只能按它落盘的文件现推一个（[storedFingerprintOf]），
  /// 否则家长把同一个文件再选一遍就会被当成新视频又存一份。
  ///
  /// 批量导入时先问一句，省得为一个已经在库里的视频白拷一份几百兆的文件。
  Future<VideoItem?> findDuplicate(String categoryId, String dedupKey) async {
    final category = state.byId(categoryId);
    if (category == null || dedupKey.isEmpty) return null;
    final hit = category.findDuplicate(dedupKey);
    if (hit != null) return hit;
    for (final v in category.videos) {
      if (!v.isLocal) continue;
      if (await storedFingerprintOf(v.source) == dedupKey) return v;
    }
    return null;
  }

  Future<void> removeVideo(String categoryId, String videoId) async {
    await _save(VideoLibrary(categories: [
      for (final c in state.categories)
        c.id == categoryId
            ? c.copyWith(
                videos: [
                  for (final v in c.videos)
                    if (v.id != videoId) v,
                ],
              )
            : c,
    ]));
  }

  /// 家长把视频收起来 / 放出来。收起来的在分类列表里不给孩子看，视频本身没删。
  Future<void> setVideoHidden(
    String categoryId,
    String videoId, {
    required bool hidden,
  }) =>
      _updateVideo(categoryId, videoId, (v) => v.copyWith(hidden: hidden));

  /// 家长挪一个视频的位置：[VideoMove.up] 往前一位、[VideoMove.down] 往后一位、
  /// [VideoMove.top] / [VideoMove.bottom] 直接挪到最前 / 最后。
  ///
  /// 顺序就是分类里那个列表的顺序，收起来的视频也占着位置 —— 所以「向前排一位」
  /// 跨过一个藏起来的视频时，孩子那边看着可能没动。
  Future<void> moveVideo(
      String categoryId, String videoId, VideoMove move) async {
    final category = state.byId(categoryId);
    if (category == null) return;
    final videos = [...category.videos];
    final from = videos.indexWhere((v) => v.id == videoId);
    if (from < 0) return;
    final to = switch (move) {
      VideoMove.up => from - 1,
      VideoMove.down => from + 1,
      VideoMove.top => 0,
      VideoMove.bottom => videos.length - 1,
    };
    // 已经在头上 / 尾上再挪就什么也不做（界面上那几项也会置灰）。
    if (to == from || to < 0 || to >= videos.length) return;
    videos.insert(to, videos.removeAt(from));
    await _save(_withVideos(categoryId, videos));
  }

  /// 换掉一条视频的字段（隐藏 / 放出走这里）。视频或分类已经不在了就当没这回事。
  Future<void> _updateVideo(
    String categoryId,
    String videoId,
    VideoItem Function(VideoItem) change,
  ) async {
    final category = state.byId(categoryId);
    if (category == null) return;
    if (!category.videos.any((v) => v.id == videoId)) return;
    await _save(_withVideos(categoryId, [
      for (final v in category.videos) v.id == videoId ? change(v) : v,
    ]));
  }

  /// 复制一份库，把 [categoryId] 的视频列表换成 [videos]。
  VideoLibrary _withVideos(String categoryId, List<VideoItem> videos) =>
      VideoLibrary(categories: [
        for (final c in state.categories)
          c.id == categoryId ? c.copyWith(videos: videos) : c,
      ]);
}

final videoLibraryProvider =
    NotifierProvider<VideoLibraryController, VideoLibrary>(
        VideoLibraryController.new);
