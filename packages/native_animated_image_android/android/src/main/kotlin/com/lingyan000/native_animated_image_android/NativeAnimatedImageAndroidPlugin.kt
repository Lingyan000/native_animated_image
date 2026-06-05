package com.lingyan000.native_animated_image_android

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.os.Build
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

/**
 * Android plugin entry point.
 *
 * Two responsibilities:
 *
 * 1. **FFI**: package the Rust shared libraries (under `jniLibs/{abi}/`) so
 *    `DynamicLibrary.open('libnative_animated_image_codec.so')` on the Dart
 *    side can resolve symbols for GIF/APNG/WebP decoding.
 * 2. **AVIF method channel**: route to Android's system `ImageDecoder`
 *    (API 31+) for static AVIF — the system decoder is hardware-aware on
 *    Pixel 9 / Snapdragon 8 Gen 3+ and uses optimized libaom on older chips.
 *    Animated AVIF requires per-frame extraction that the public
 *    `ImageDecoder` API doesn't expose cleanly; we surface that as an error
 *    so the Dart side falls back to flutter_avif. (v0.3 may revisit via
 *    custom AV1 framing or `AnimatedImageDrawable` introspection.)
 */
class NativeAnimatedImageAndroidPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private var channel: MethodChannel? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val ch = MethodChannel(
      binding.binaryMessenger,
      "com.lingyan000.native_animated_image/avif_platform",
    )
    ch.setMethodCallHandler(this)
    channel = ch
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "canDecodeAvif" -> {
        // ImageDecoder added AVIF support in API 31 (Android 12).
        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
      }

      "decodeAvif" -> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
          result.error(
            "unsupported_os",
            "Android API 31+ required for AVIF (current=${Build.VERSION.SDK_INT})",
            null,
          )
          return
        }
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.isEmpty()) {
          result.error("invalid_args", "expected non-empty bytes", null)
          return
        }

        // Decode off the platform thread.
        Thread({
          try {
            val decoded = decodeAvif(bytes)
            // Switch back to main looper for MethodChannel.Result.success
            android.os.Handler(android.os.Looper.getMainLooper()).post {
              result.success(decoded)
            }
          } catch (e: Exception) {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
              result.error("decode_error", e.message ?: e.javaClass.simpleName, null)
            }
          }
        }, "NativeAvifDecode").start()
      }

      else -> result.notImplemented()
    }
  }

  @RequiresApi(Build.VERSION_CODES.S)
  private fun decodeAvif(bytes: ByteArray): Map<String, Any> {
    val source = ImageDecoder.createSource(ByteBuffer.wrap(bytes))

    var isAnimated = false
    val bitmap: Bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
      isAnimated = info.isAnimated
      // ALLOCATOR_SOFTWARE lets us read pixels via getPixels().
      // The default HARDWARE allocator yields a GPU-only Bitmap, useless here.
      decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
    }

    if (isAnimated) {
      bitmap.recycle()
      throw UnsupportedOperationException(
        "animated AVIF not yet supported on Android platform decoder — caller should fall back",
      )
    }

    val w = bitmap.width
    val h = bitmap.height
    val rgba = ByteArray(w * h * 4)
    val pixels = IntArray(w * h)
    bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
    bitmap.recycle()

    // Android Bitmap pixels are ARGB_8888 packed: A<<24 | R<<16 | G<<8 | B
    // Flutter wants RGBA_8888 (R,G,B,A bytes in that order).
    for (i in 0 until w * h) {
      val p = pixels[i]
      rgba[i * 4] = ((p shr 16) and 0xFF).toByte()       // R
      rgba[i * 4 + 1] = ((p shr 8) and 0xFF).toByte()    // G
      rgba[i * 4 + 2] = (p and 0xFF).toByte()            // B
      rgba[i * 4 + 3] = ((p ushr 24) and 0xFF).toByte()  // A
    }

    return mapOf(
      "width" to w,
      "height" to h,
      "loopCount" to 0,
      "frames" to listOf(
        mapOf(
          "rgba" to rgba,
          "delayMs" to 0,
        ),
      ),
    )
  }
}
