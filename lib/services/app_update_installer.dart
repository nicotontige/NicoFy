/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     NicoFy is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     NicoFy is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     NicoFy is a modified version of Musify by Valeri Gokadze
 *     (https://github.com/gokadzev/Musify).
 *     For more information about NicoFy, please visit:
 *     https://github.com/nicotontige/NicoFy
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/extensions/l10n.dart';
import 'package:nicofy/main.dart' show logger;
import 'package:nicofy/utilities/flutter_toast.dart';
import 'package:nicofy/utilities/url_launcher.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads an update inside the app and hands it to the system installer.
///
/// Opening the APK link in a browser is no use on a TV, which usually has
/// none; this works the same on a phone and on a TV. The first time, Android
/// itself asks to allow NicoFy to install apps.
class AppUpdateInstaller {
  AppUpdateInstaller._();

  static const _channel = MethodChannel('nicofy/update');

  /// Downloads [url] while showing its progress, then opens the installer.
  /// Falls back to opening the link when anything goes wrong, so an update is
  /// never further out of reach than it was before.
  static Future<void> downloadAndInstall(
    BuildContext context,
    String url,
  ) async {
    final progress = ValueNotifier<double?>(null);
    final cancelled = Completer<void>();
    final l10n = context.l10n!;
    final navigator = Navigator.of(context, rootNavigator: true);

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(l10n.downloadingUpdate),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: value),
                const SizedBox(height: 12),
                Text(value == null ? '' : '${(value * 100).round()} %'),
              ],
            ),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () {
                if (!cancelled.isCompleted) cancelled.complete();
                navigator.pop();
              },
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );

    File? apk;
    try {
      apk = await _download(url, progress, cancelled.future);
    } catch (e, stackTrace) {
      logger.log('Update download failed', error: e, stackTrace: stackTrace);
    }

    if (cancelled.isCompleted) return;
    navigator.pop();

    var installed = false;
    if (apk != null) {
      try {
        installed =
            await _channel.invokeMethod<bool>('installApk', {
              'path': apk.path,
            }) ??
            false;
      } catch (e, stackTrace) {
        logger.log(
          'Opening the installer failed',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    if (!installed && context.mounted) {
      showToast(context, l10n.updateDownloadFailed);
      await launchURL(Uri.parse(url));
    }
  }

  static Future<File?> _download(
    String url,
    ValueNotifier<double?> progress,
    Future<void> cancelled,
  ) async {
    // The provider only shares this folder; older downloads go with each new
    // one so updates never pile up in the cache.
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/updates',
    );
    if (directory.existsSync()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
    final file = File('${directory.path}/NicoFy-update.apk');

    final client = http.Client();
    unawaited(cancelled.then((_) => client.close()));
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        logger.log('Update download returned ${response.statusCode}');
        return null;
      }

      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) progress.value = received / total;
        }
      } finally {
        await sink.close();
      }

      if (total != null && received != total) return null;
      return file;
    } finally {
      client.close();
    }
  }
}
