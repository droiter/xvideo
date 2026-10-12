import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/empty_hint.dart';
import '../../state/providers.dart';
import 'video_import.dart';
import 'video_thumbnail.dart';

/// 「我的 → 我的视频」：建分类、往分类里加视频（链接或本机文件）。
class VideoManageScreen extends ConsumerStatefulWidget {
  const VideoManageScreen({super.key});

  @override
  ConsumerState<VideoManageScreen> createState() => _VideoManageScreenState();
}

class _VideoManageScreenState extends ConsumerState<VideoManageScreen> {
  VideoLibraryController get _lib => ref.read(videoLibraryProvider.notifier);

  VideoThumbCache get _thumbs => ref.read(videoThumbCacheProvider);

  /// 本机视频和链接在列表里用不同的小图标区分。
  IconData _kindIcon(VideoItem v) =>
      v.isLocal ? Icons.smartphone_rounded : Icons.link_rounded;

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(videoLibraryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的视频'),
        actions: [
          IconButton(
            tooltip: '新建分类',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _newCategory,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          Text(
            '这里的分类会出现在「看视频」选项卡里，点分类就能看到里面的视频。',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (lib.isEmpty)
            Column(
              children: [
                const EmptyHint(
                  icon: Icons.video_library_outlined,
                  text: '还没有视频分类',
                  detail: '先建一个分类，比如「动画片」「儿歌」「英语启蒙」',
                ),
                FilledButton.icon(
                  onPressed: _newCategory,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新建分类'),
                ),
              ],
            )
          else ...[
            for (final c in lib.categories) ...[
              _categoryCard(c),
              const SizedBox(height: 14),
            ],
            // 建完第一个分类后，只剩 AppBar 上那个小图标能再建一个，
            // 家长多半找不到，所以在列表里也放一个看得见的入口。
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: _newCategory,
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                label: const Text('新建分类'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryCard(VideoCategory c) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_rounded, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      // 这里是家长在管，报的是真数：藏起来的也数上，另标一句。
                      Text(
                          '${c.videos.length} 个视频'
                          '${c.hiddenCount > 0 ? ' · 已隐藏 ${c.hiddenCount} 个' : ''}',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '分类操作',
                  onSelected: (v) {
                    if (v == 'rename') _renameCategory(c);
                    if (v == 'delete') _deleteCategory(c);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除分类')),
                  ],
                ),
              ],
            ),
            if (c.videos.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 6, bottom: 2),
                child: Text('还没有视频',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant)),
              )
            else
              for (final v in c.videos)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 30, right: 4),
                  // 有缩略图就显示缩略图，来源（本机 / 链接）用小角标接着标，
                  // 没有缩略图时那个图标就是占位块本身。
                  leading: VideoThumb(
                    video: v,
                    width: 46,
                    height: 34,
                    radius: 8,
                    placeholderIcon: _kindIcon(v),
                    badgeIcon: _kindIcon(v),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(v.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14)),
                      ),
                      if (v.hidden) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text('已隐藏',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: scheme.onSurfaceVariant)),
                        ),
                      ],
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: '删除视频',
                    icon: Icon(Icons.close_rounded,
                        size: 20, color: scheme.outline),
                    onPressed: () => _deleteVideo(c, v),
                  ),
                ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addVideo(c),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('添加视频'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 分类 ----

  Future<void> _newCategory() async {
    final name = await _askText(
      title: '新建分类',
      hint: '例如：动画片、儿歌、英语启蒙',
      confirmText: '创建',
    );
    if (name == null) return;
    await _lib.addCategory(name);
  }

  Future<void> _renameCategory(VideoCategory c) async {
    final name = await _askText(
      title: '重命名分类',
      hint: '分类名称',
      initial: c.name,
      confirmText: '保存',
    );
    if (name == null) return;
    await _lib.renameCategory(c.id, name);
  }

  Future<void> _deleteCategory(VideoCategory c) async {
    final n = c.videos.length;
    final ok = await _confirm(
      title: '删除「${c.name}」',
      message: n == 0
          ? '这个分类会被删除。'
          : '分类和里面的 $n 个视频都会被删除，本机视频文件也会一起清理。',
    );
    if (ok != true) return;
    final locals = [
      for (final v in c.videos)
        if (v.isLocal) v,
    ];
    await _lib.removeCategory(c.id);
    for (final v in locals) {
      await deleteLocalVideoFile(v.source);
      await _thumbs.remove(v.id);
    }
  }

  // ---- 视频 ----

  Future<void> _addVideo(VideoCategory c) async {
    final mode = await showModalBottomSheet<_AddMode>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('粘贴视频链接'),
              subtitle: const Text('http / https 地址'),
              onTap: () => Navigator.pop(ctx, _AddMode.link),
            ),
            ListTile(
              leading: const Icon(Icons.smartphone_rounded),
              title: const Text('从本机选择文件'),
              subtitle: const Text('可一次勾多个，名字自动用文件名，会复制进 App'),
              onTap: () => Navigator.pop(ctx, _AddMode.file),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (mode == null || !mounted) return;
    if (mode == _AddMode.link) {
      await _addByLink(c);
    } else {
      await _addFromFile(c);
    }
  }

  Future<void> _addByLink(VideoCategory c) async {
    final input = await showDialog<({String title, String url})>(
      context: context,
      builder: (_) => const _LinkVideoDialog(),
    );
    if (input == null || !mounted) return;
    final r = await _lib.addVideo(c.id, title: input.title, source: input.url);
    if (!mounted) return;
    // 正常加进去不用吭声，列表里已经看得见了；只有被挡下来和改了名字才说一句。
    if (!r.added) {
      _toast('「${r.title}」已经在「${c.name}」里了，没有重复添加');
    } else if (r.title != input.title) {
      _toast('「${input.title}」重名了，已存为「${r.title}」');
    }
  }

  Future<void> _addFromFile(VideoCategory c) async {
    List<PickedVideo> picked;
    try {
      picked = await pickLocalVideos(
        // 家长点完「选择」，插件要先在后台把选中的文件拷进缓存目录，这期间
        // Dart 侧什么都收不到。先把界面盖住：家长不用干等着猜发生了什么，
        // 也点不动别处（以前这段是空白的，能随便乱点）。
        onPicking: () => _showBusy(const _BusyState('正在读取你选中的视频…')),
      );
    } catch (e) {
      _hideBusy();
      if (!mounted) return;
      _toast('打开文件选择器失败：$e');
      return;
    }
    if (picked.isEmpty) {
      _hideBusy();
      return;
    }
    if (!mounted) return;

    // 一次可能勾十几个，名字直接取文件名，不再一个个弹框问。
    // 先把指纹和重复都查完再动手：已经在库里的不该白拷一份几百兆的文件。
    final ready = <({PickedVideo picked, String title, String fingerprint})>[];
    final blocked = <String>[];
    final fresh = <String>[];
    for (var i = 0; i < picked.length; i++) {
      final p = picked[i];
      _showBusy(_BusyState(
        '正在检查有没有重复（${i + 1}/${picked.length}）…',
        value: i / picked.length,
      ));
      final fingerprint = await videoFingerprint(p);
      final title = defaultVideoName(p.name, c.videos.length + ready.length + 1);
      final dup = fingerprint.isEmpty
          ? null
          : await _lib.findDuplicate(c.id, fingerprint);
      if (dup != null) {
        blocked.add(dup.title);
        continue;
      }
      // 同一批里把同一个文件勾了两遍，也算重复。
      if (fingerprint.isNotEmpty && fresh.contains(fingerprint)) {
        blocked.add(title);
        continue;
      }
      if (fingerprint.isNotEmpty) fresh.add(fingerprint);
      ready.add((picked: p, title: title, fingerprint: fingerprint));
    }

    if (blocked.isNotEmpty) {
      _hideBusy();
      final go = await _blockedDialog(c, blocked, ready.length);
      if (!mounted || go != true) return;
      _showBusy(const _BusyState('正在导入…'));
    }
    if (ready.isEmpty) {
      _hideBusy();
      return;
    }

    final failed = <String>[];
    final skipped = <String>[];
    var added = 0;
    for (var i = 0; i < ready.length; i++) {
      final r = ready[i];
      _showBusy(_BusyState(
        '正在导入 ${i + 1}/${ready.length}：${r.title}',
        value: i / ready.length,
      ));
      String? dest;
      try {
        // 查重再拦一道：这一批拷完之前库里可能又有变化。
        if (r.fingerprint.isNotEmpty &&
            await _lib.findDuplicate(c.id, r.fingerprint) != null) {
          skipped.add(r.title);
          continue;
        }
        // 搬进 App 私有目录再记录，缓存里的临时路径迟早会被系统清掉。
        dest = await importLocalVideo(r.picked);
        await _lib.addVideo(c.id,
            title: r.title,
            source: dest,
            kind: VideoKind.file,
            fingerprint: r.fingerprint);
        added++;
      } catch (e) {
        // 一个失败不影响后面几个，最后一起报。已经搬进来的文件别留下当孤儿。
        if (dest != null) await deleteLocalVideoFile(dest);
        failed.add(r.title);
      }
    }
    _hideBusy();
    if (!mounted) return;
    if (skipped.isNotEmpty || failed.isNotEmpty) {
      await _resultDialog(c, added: added, skipped: skipped, failed: failed);
    }
  }

  Future<void> _deleteVideo(VideoCategory c, VideoItem v) async {
    final ok = await _confirm(
      title: '删除视频',
      message: v.isLocal
          ? '「${v.title}」会从列表里移除，本机文件也会一起删除。'
          : '「${v.title}」会从列表里移除。',
    );
    if (ok != true) return;
    await _lib.removeVideo(c.id, v.id);
    if (v.isLocal) {
      await deleteLocalVideoFile(v.source);
      await _thumbs.remove(v.id);
    }
  }

  // ---- 小工具 ----

  Future<String?> _askText({
    required String title,
    required String hint,
    required String confirmText,
    String initial = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: title,
        hint: hint,
        initial: initial,
        confirmText: confirmText,
      ),
    );
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
  }

  // ---- 进度框 ----

  /// 导入期间盖在界面上的进度框内容。
  final ValueNotifier<_BusyState> _busy = ValueNotifier(const _BusyState(''));
  bool _busyShown = false;

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  /// 盖上（或者就地更新）进度框。
  ///
  /// 盖的时机很关键：从选择器开始拷文件那一刻就盖，一直盖到写完库里，中途不闪
  /// 断；框不可取消、返回键也按不动，家长只能等它自己收掉。以前这段是空白的，
  /// 界面上一点动静都没有，家长能随便乱点、还能再发起一次导入。
  void _showBusy(_BusyState state) {
    if (!mounted) return;
    _busy.value = state;
    if (_busyShown) return;
    _busyShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: ValueListenableBuilder<_BusyState>(
          valueListenable: _busy,
          builder: (_, state, __) =>
              AlertDialog(content: _BusyBody(state: state)),
        ),
      ),
    );
  }

  void _hideBusy() {
    if (!_busyShown) return;
    _busyShown = false;
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  /// 被挡下来的那些视频：一个一个列出来，别让家长只看到一句「有 3 个重复」。
  ///
  /// 返回 true 表示「其余那些继续加」，false / null 表示整批都不加了。
  Future<bool?> _blockedDialog(
      VideoCategory c, List<String> blocked, int ready) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(ready > 0 ? '这些视频不能重复添加' : '这些视频都已经在库里了'),
        content: _NameList(
          head: '下面 ${blocked.length} 个视频已经在「${c.name}」里了：',
          names: blocked,
          tail: ready > 0 ? '其余 $ready 个可以继续添加。' : null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ready > 0 ? '都取消' : '知道了'),
          ),
          if (ready > 0)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('继续添加其余 $ready 个'),
            ),
        ],
      ),
    );
  }

  /// 收尾：有没加进去的（重复 / 失败）才弹，全加进去就不用打扰家长。
  Future<void> _resultDialog(
    VideoCategory c, {
    required int added,
    required List<String> skipped,
    required List<String> failed,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('导入完成'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (added > 0) Text('已经加入 $added 个视频。'),
            if (skipped.isNotEmpty) ...[
              if (added > 0) const SizedBox(height: 10),
              _NameList(
                head: '这 ${skipped.length} 个已经在「${c.name}」里了，没有重复添加：',
                names: skipped,
              ),
            ],
            if (failed.isNotEmpty) ...[
              if (added > 0 || skipped.isNotEmpty) const SizedBox(height: 10),
              _NameList(
                head: '这 ${failed.length} 个没能导入：',
                names: failed,
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// 进度框里显示什么。
@immutable
class _BusyState {
  const _BusyState(this.text, {this.value});

  final String text;

  /// 0~1 的进度；null 表示这会儿还算不出比例（比如选择器正在后台拷文件）。
  final double? value;
}

/// 进度框的样子：一句话 + 进度条（算得出比例时连百分比一起给）。
class _BusyBody extends StatelessWidget {
  const _BusyBody({required this.state});

  final _BusyState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(state.text),
        const SizedBox(height: 16),
        LinearProgressIndicator(value: state.value, minHeight: 6),
        if (state.value != null) ...[
          const SizedBox(height: 8),
          Text('${(state.value! * 100).round()}%',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

/// 一串名字的清单：一句开头 + 逐个列出来的名字 + 可选的收尾。
class _NameList extends StatelessWidget {
  const _NameList({required this.head, required this.names, this.tail});

  final String head;
  final List<String> names;
  final String? tail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(head),
        const SizedBox(height: 8),
        for (final n in names)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Text('· $n'),
          ),
        if (tail != null) ...[
          const SizedBox(height: 4),
          Text(tail!),
        ],
      ],
    );
  }
}

enum _AddMode { link, file }

/// 单个输入框的对话框：确定返回文本，取消返回 null。
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.confirmText,
  });

  final String title;
  final String hint;
  final String initial;
  final String confirmText;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  // 预填的内容整段选中，想改的直接打字就换掉了。
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  )..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }
}

/// 链接视频：名称 + 网址。
class _LinkVideoDialog extends StatefulWidget {
  const _LinkVideoDialog();

  @override
  State<_LinkVideoDialog> createState() => _LinkVideoDialogState();
}

class _LinkVideoDialogState extends State<_LinkVideoDialog> {
  final _title = TextEditingController();
  final _url = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    final looksLikeUrl =
        url.startsWith('http://') || url.startsWith('https://');
    if (!looksLikeUrl) {
      setState(() => _error = '请填以 http:// 或 https:// 开头的地址');
      return;
    }
    Navigator.pop(context, (
      title: _title.text.trim().isEmpty ? '未命名视频' : _title.text.trim(),
      url: url,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('添加视频链接'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: '视频名称', hintText: '例如：小猪佩奇 第 1 集'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '视频链接',
              hintText: 'https://…',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('添加')),
      ],
    );
  }
}
