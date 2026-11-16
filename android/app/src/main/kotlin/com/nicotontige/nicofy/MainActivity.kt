package com.nicotontige.nicofy

import android.app.SearchManager
import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// AudioServiceActivity keeps the engine the audio service shares; it only
// gains the channels that hand a downloaded update to the system installer,
// name the device, and pass on voice searches.
class MainActivity : AudioServiceActivity() {
  private var voiceChannel: MethodChannel? = null

  // A voice search that arrived before Dart listened, at a cold start.
  private var pendingVoiceQuery: String? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    // Aligns the Flutter view vertically with the window.
    WindowCompat.setDecorFitsSystemWindows(getWindow(), false)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      // Disable the Android splash screen fade out animation to avoid
      // a flicker before the similar frame is drawn in Flutter.
      splashScreen.setOnExitAnimationListener { splashScreenView -> splashScreenView.remove() }
    }

    super.onCreate(savedInstanceState)
    handleVoiceSearch(intent)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    handleVoiceSearch(intent)
  }

  // MEDIA_PLAY_FROM_SEARCH carries what was asked for in SearchManager.QUERY,
  // empty for "play some music". Dart plays it like the media session's
  // playFromSearch, or picks it up at startup if it is not listening yet.
  private fun handleVoiceSearch(intent: Intent?) {
    if (intent?.action != MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH) return
    val query = intent.getStringExtra(SearchManager.QUERY) ?: ""
    // Handled once, not again when the activity is recreated.
    intent.action = Intent.ACTION_MAIN
    val channel = voiceChannel
    if (channel == null) {
      pendingVoiceQuery = query
      return
    }
    channel.invokeMethod("playFromSearch", query, object : MethodChannel.Result {
      override fun success(result: Any?) {}

      override fun error(code: String, message: String?, details: Any?) {}

      // Dart is not listening yet: it asks for it once it starts.
      override fun notImplemented() {
        pendingVoiceQuery = query
      }
    })
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "installApk" -> {
            val path = call.argument<String>("path")
            if (path == null) {
              result.error("no_path", "No APK path given", null)
            } else {
              result.success(installApk(File(path)))
            }
          }
          else -> result.notImplemented()
        }
      }
    voiceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_CHANNEL)
      .also { channel ->
        channel.setMethodCallHandler { call, result ->
          when (call.method) {
            "takePendingQuery" -> {
              result.success(pendingVoiceQuery)
              pendingVoiceQuery = null
            }
            else -> result.notImplemented()
          }
        }
      }
    // How this device names itself to the other NicoFy devices on the network.
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "identity" -> result.success(
            mapOf("model" to Build.MODEL, "television" to isTelevision())
          )
          else -> result.notImplemented()
        }
      }
  }

  private fun isTelevision(): Boolean {
    val uiMode = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
    return uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
  }

  // The system installer asks for the "install unknown apps" permission
  // itself the first time, on phones and on TVs alike.
  private fun installApk(apk: File): Boolean {
    if (!apk.isFile) return false
    val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
    val intent = Intent(Intent.ACTION_VIEW)
      .setDataAndType(uri, "application/vnd.android.package-archive")
      .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
    return try {
      startActivity(intent)
      true
    } catch (e: ActivityNotFoundException) {
      false
    }
  }

  companion object {
    private const val UPDATE_CHANNEL = "nicofy/update"
    private const val DEVICE_CHANNEL = "nicofy/device"
    private const val VOICE_CHANNEL = "nicofy/voice"
  }
}
