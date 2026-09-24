import 'dart:io';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 本机视频复制到 App 私有目录后存放的子目录名。
///
/// 不直接用选择器返回的缓存路径：缓存会被系统清掉，孩子过几天就打不开了。
const String kVideoDirName = 'xvideo_videos';

/// 问系统要文件显示名的通道，实现在 android/.../MainActivity.kt。
const MethodChannel _nameChannel = MethodChannel('xvideo/picker');

/// 用户挑中的一个本机视频。[name] 是能问到的显示名，问不到时是空串。
class PickedVideo {
  const PickedVideo({required this.name, required this.path});

  final String name;
  final String path;
}

/// 打开系统文件选择器挑视频，可以一次多选；取消或一个路径都拿不到时返回空列表。
///
/// [onPicking] 在家长点完「选择」的那一刻回调一次。插件接下来要在自己的线程上
/// 把选中的文件逐个拷进缓存目录，这期间 Dart 侧收不到任何东西（几百兆的视频要
/// 等很久）——界面得靠这一声先把进度盖上去，家长才不会以为没点中、随手乱点。
Future<List<PickedVideo>> pickLocalVideos({void Function()? onPicking}) async {
  // 带上 SAF 选项，选择器才会把原始 content:// 地址一起给回来，
  // 后面自己查文件名要靠它。
  final files = await FilePicker.pickFiles(
    type: FileType.video,
    androidOptions: const FilePickerAndroidOptions(),
    onFileLoading: (status) {
      if (status == FilePickerStatus.picking) onPicking?.call();
    },
  );
  final picked = <PickedVideo>[];
  for (final f in files) {
    final path =
        f.path ?? (f.uri.scheme == 'file' ? f.uri.toFilePath() : null);
    if (path == null) continue;
    picked.add(PickedVideo(name: await resolveVideoName(f), path: path));
  }
  return picked;
}

/// 文件名去掉后缀，当视频名字的默认值。
String videoNameFromFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  return base.trim();
}

/// 视频名字的默认值：文件名去掉后缀；实在问不到就用「视频 N」占位。
String defaultVideoName(String pickedName, int index) {
  final name = videoNameFromFileName(pickedName);
  return name.isEmpty ? '视频 $index' : name;
}

/// 挑中的文件 → 记进视频库的名字。
///
/// 先问自己写的系统查询，再退回选择器给的 [PlatformFile.name]：选择器给的名字
/// 在有些机器上并不是文件名，而是内容提供者那边的编号
/// （`content://media/.../1234` 的最后一段），家长看了完全对不上。
Future<String> resolveVideoName(PlatformFile f) async {
  final safUri = f is AndroidPlatformFile ? f.safHandle?.uri : null;
  if (safUri != null) {
    final system = await _systemDisplayName(safUri);
    if (system != null) return system;
  }
  return _meaningful(f.name) ? f.name.trim() : '';
}

Future<String?> _systemDisplayName(Uri uri) async {
  try {
    final name = await _nameChannel
        .invokeMethod<String>('displayName', {'uri': uri.toString()});
    return _meaningful(name) ? name!.trim() : null;
  } catch (_) {
    // 平台上没接这个通道（测试、桌面）或者查询出错，都当没问到。
    return null;
  }
}

/// 内部编号、`unamed` 这类名字对家长没有意义，当成没拿到。
bool _meaningful(String? raw) {
  final name = raw?.trim() ?? '';
  if (name.isEmpty || name.contains(':')) return false;
  final lower = name.toLowerCase();
  if (lower == 'unamed' || lower == 'unnamed') return false;
  // 纯数字的一长串多半是编号或时间戳，不是家长认得的文件名。
  return !RegExp(r'^\d{6,}$').hasMatch(videoNameFromFileName(name));
}

/// 本机视频的查重指纹：原文件名 + 字节数；认不出来时返回空串。
///
/// 得赶在 [importLocalVideo] 之前算：那一步会把源文件清掉（选择器的缓存副本），
/// 之后再想问大小就问不到了。
///
/// 名字问不到时只剩字节数可用——两个不同的视频撞上同一个字节数几乎不可能，
/// 总比认不出「同一个文件又选了一遍」强。反过来，文件读不到就干脆不给指纹：
/// 让家长自己删多出来的那份，也好过把想加的挡在门外。
///
/// 名字按落盘时的写法（[safeVideoFileName]）算，才跟 [storedFingerprintOf] 从
/// 库里那条记录的路径里推出来的一致。
Future<String> videoFingerprint(PickedVideo picked) async {
  int size;
  try {
    size = await File(picked.path).length();
  } catch (_) {
    return '';
  }
  return size <= 0 ? '' : '${safeVideoFileName(picked.name)}|$size';
}

/// 库里一条本机视频的查重指纹，按它存下来的文件现推；推不出来返回 null。
///
/// 早先版本的记录里没有指纹，只有 [importLocalVideo] 落盘的路径，光比指纹比不出
/// 来——家长把同一个文件再选一遍就又会存一份。路径最后一段是
/// `<微秒时间戳>_<文件名>`，配上传进来那份拷贝的字节数，正好能还原出
/// [videoFingerprint] 的写法。
///
/// 链接、文件已经被删掉或读不到，都返回 null：宁可漏判（家长自己能删），
/// 也别把两个不同的视频误判成一个。
Future<String?> storedFingerprintOf(String source) async {
  final base = source.split(RegExp(r'[/\\]')).last;
  final name = RegExp(r'^\d{10,}_(.+)$').firstMatch(base)?.group(1);
  if (name == null) return null;
  try {
    final size = await File(source).length();
    return size <= 0 ? null : '$name|$size';
  } catch (_) {
    return null;
  }
}

/// 把挑中的视频放进 App 私有目录，返回可长期播放的绝对路径。
Future<String> importLocalVideo(PickedVideo picked) async {
  final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/$kVideoDirName');
  if (!dir.existsSync()) await dir.create(recursive: true);
  final dest = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}'
      '_${safeVideoFileName(picked.name)}';
  if (await _movePickerCacheCopy(picked.path, dest)) return dest;
  await File(picked.path).copy(dest);
  await _dropPickerCacheCopy(picked.path);
  return dest;
}

/// 选择器已经把文件拷进自己的缓存目录了，再整份拷一遍是白花的功夫——几百兆的
/// 视频要好几秒，家长就得多等这一会儿。同一个文件系统上直接改名搬过去几乎不用
/// 时间。搬成了返回 true。
///
/// 只有在缓存目录里的副本才搬（[_dropPickerCacheCopy] 同一个前缀校验）：万一
/// 拿到的是家长自己的真实文件，绝不能把人家的文件搬走。
Future<bool> _movePickerCacheCopy(String source, String dest) async {
  try {
    final cache = (await getTemporaryDirectory()).path;
    if (!source.startsWith(cache)) return false;
    await File(source).rename(dest);
    return true;
  } catch (_) {
    // 跨文件系统之类的意外，交给调用方老老实实拷一份。
    return false;
  }
}

/// 从视频库里移除本地视频时顺带删掉文件，避免留下孤儿。
Future<void> deleteLocalVideoFile(String path) async {
  try {
    final f = File(path);
    if (f.existsSync()) await f.delete();
  } catch (_) {
    // 文件删不掉不影响「从列表里移除」这件事。
  }
}

/// 选择器会把 SAF 选中的文件复制一份到自己的缓存目录，导入完就没用了。
/// 只删我们自己缓存目录里的副本——万一拿到的是用户真实路径，绝不能碰。
Future<void> _dropPickerCacheCopy(String sourcePath) async {
  try {
    final cache = (await getTemporaryDirectory()).path;
    if (sourcePath.startsWith(cache)) await File(sourcePath).delete();
  } catch (_) {
    // 清缓存失败无所谓，系统迟早会回收。
  }
}

/// 只保留文件名部分，并去掉路径分隔符等非法字符。落盘用这个名字，
/// [storedFingerprintOf] 推指纹时也按这个名字对。
String safeVideoFileName(String name) {
  final base = name.split(RegExp(r'[/\\]')).last.trim();
  final cleaned = base.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_');
  return cleaned.isEmpty ? 'video.mp4' : cleaned;
}
