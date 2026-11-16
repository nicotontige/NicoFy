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

import 'package:flutter/services.dart';

/// "Ok Google, mets <artiste> sur NicoFy" mostly reaches the player through
/// its media session. Some systems send the older MEDIA_PLAY_FROM_SEARCH
/// intent to the activity instead; the activity hands its words over here,
/// and they are played exactly as the media session's would be.
///
/// [playFromSearch] is the audio handler's: an empty query resumes, anything
/// else plays the songs found for it, the library first, then YouTube.
Future<void> listenToVoiceSearchIntents(
  Future<void> Function(String query) playFromSearch, {
  MethodChannel channel = const MethodChannel('nicofy/voice'),
}) async {
  channel.setMethodCallHandler((call) async {
    if (call.method != 'playFromSearch') {
      throw MissingPluginException(call.method);
    }
    final query = call.arguments;
    await playFromSearch(query is String ? query : '');
  });

  // The search that opened the app, from before this listened.
  try {
    final pending = await channel.invokeMethod<String>('takePendingQuery');
    if (pending != null) await playFromSearch(pending);
  } on MissingPluginException {
    // Not an Android build with the channel.
  } on PlatformException {
    // Nothing to pick up.
  }
}
