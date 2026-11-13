package com.nicotontige.nicofy

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// AudioServiceActivity keeps the engine the audio service shares; it only
// gains the channel that hands a downloaded update to the system installer.
class MainActivity : AudioServiceActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    // Aligns the Flutter view vertically with the window.
    WindowCompat.setDecorFitsSystemWindows(getWindow(), false)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      // Disable the Android splash screen fade out animation to avoid
      // a flicker before the similar frame is drawn in Flutter.
      splashScreen.setOnExitAnimationListener { splashScreenView -> splashScreenView.remove() }
    }

    super.onCreate(savedInstanceState)
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
  }
}
