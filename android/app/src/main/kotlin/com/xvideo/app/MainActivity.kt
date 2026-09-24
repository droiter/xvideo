package com.xvideo.app

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.BaseColumns
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xvideo/picker")
            .setMethodCallHandler { call, result ->
                if (call.method != "displayName") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val uri = call.argument<String>("uri")
                // 查内容提供者可能要等一会儿，别占着主线程。
                Thread {
                    val name = displayNameOf(uri)
                    runOnUiThread {
                        try {
                            result.success(name)
                        } catch (_: Exception) {
                            // 界面已经退掉了，这个结果没人要了。
                        }
                    }
                }.start()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xvideo/video")
            .setMethodCallHandler { call, result ->
                if (call.method != "thumbnail") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val maxWidth = call.argument<Int>("maxWidth") ?: 480
                // 要读文件头、解码关键帧，比问文件名慢得多，更不能占主线程。
                thumbWorker.execute {
                    val bytes = thumbnailOf(path, maxWidth)
                    runOnUiThread {
                        try {
                            result.success(bytes)
                        } catch (_: Exception) {
                            // 界面已经退掉了，这个结果没人要了。
                        }
                    }
                }
            }
    }

    /// 从本机视频里抽一帧当缩略图，返回 JPEG 字节；抽不出来返回 null。
    private fun thumbnailOf(path: String?, maxWidth: Int): ByteArray? {
        if (path.isNullOrBlank()) return null
        val file = File(path)
        if (!file.isFile || file.length() <= 0L) return null

        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val frame = frameOf(retriever) ?: return null
            val scaled = scaleDown(frame, maxWidth)
            ByteArrayOutputStream().use { out ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 82, out)
                out.toByteArray()
            }
        } catch (_: Exception) {
            // 文件坏了、根本不是视频、这个编码解不了……都当抽不出来。
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
                // 释放失败无所谓。
            }
        }
    }

    /// 取片长十分之一处的一帧：开头往往是黑场或台标，截出来是一片黑。
    private fun frameOf(retriever: MediaMetadataRetriever): Bitmap? {
        val durationMs = retriever
            .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            ?.toLongOrNull() ?: 0L
        val targetUs = durationMs.coerceIn(0L, 50000L) / 10 * 1000
        return retriever.getFrameAtTime(targetUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            ?: retriever.getFrameAtTime(-1L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
    }

    private fun scaleDown(src: Bitmap, maxWidth: Int): Bitmap {
        if (src.width <= maxWidth) return src
        val height = (src.height.toFloat() * maxWidth / src.width).roundToInt()
            .coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(src, maxWidth, height, true)
        if (scaled !== src) src.recycle()
        return scaled
    }

    companion object {
        /// 抽帧一个接一个来：解码一整帧又吃 CPU 又吃内存，列表里几十个视频
        /// 同时开解，平板扛不住。慢一点没关系，缩略图是陆续补上的。
        private val thumbWorker = Executors.newSingleThreadExecutor()
    }

    /// 文件在「文件管理 / 相册」里显示的名字；查不到就返回 null 交给上层兜底。
    ///
    /// 选择器插件自己也会查一次，但它只问 `display_name` 一列，问不到就退回
    /// 拿地址最后一段当名字——相册给的地址 `content://media/.../1234` 最后一段
    /// 是编号，于是家长看到的就是一串数字。
    private fun displayNameOf(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        val uri = Uri.parse(raw)
        if (uri.scheme == "file") return uri.lastPathSegment
        if (uri.scheme != "content") return null

        // 不同提供者认的列名不一样，常用的都问一遍。
        return queryName(uri, OpenableColumns.DISPLAY_NAME)
            ?: queryName(uri, MediaStore.MediaColumns.DISPLAY_NAME)
            ?: queryName(uri, MediaStore.MediaColumns.TITLE)
            ?: nameById(uri)
    }

    private fun queryName(
        uri: Uri,
        column: String,
        selection: String? = null,
        args: Array<String>? = null,
    ): String? =
        try {
            contentResolver.query(uri, arrayOf(column), selection, args, null)?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) {
                    cursor.getString(0)?.takeIf { it.isNotBlank() }
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            // 没有权限、提供者不认识这一列……都当没问出来。
            null
        }

    /// 地址只给到 `content://media/.../1234` 时，拿这个编号去媒体库里再查一遍。
    private fun nameById(uri: Uri): String? {
        val id = uri.lastPathSegment?.takeIf { it.isNotEmpty() && it.all(Char::isDigit) }
            ?: return null
        val tables = listOf(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Files.getContentUri("external"),
        )
        for (table in tables) {
            val name = queryName(
                table,
                MediaStore.MediaColumns.DISPLAY_NAME,
                "${BaseColumns._ID} = ?",
                arrayOf(id),
            )
            if (name != null) return name
        }
        return null
    }
}
