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

import 'package:nicofy/services/audio_service.dart';
import 'package:nicofy/services/common_services.dart';
import 'package:nicofy/utilities/formatter.dart';

final _youtubeLinkRegex = RegExp(r'(youtube\.com|youtu\.be)');

Future<void> handleYoutubeSharedTextIntent(
  String? value, {
  required NicoFyAudioHandler audioHandler,
  required void Function(Object error, StackTrace stackTrace) onError,
}) async {
  if (value == null || !_youtubeLinkRegex.hasMatch(value)) {
    return;
  }

  final songId = getSongId(value);
  if (songId == null) {
    return;
  }

  try {
    final song = await getSongDetails(0, songId);
    await audioHandler.playSong(song);
  } catch (e, stackTrace) {
    onError(e, stackTrace);
  }
}

Future<void> consumeYoutubeSharedTextIntent(
  String? value, {
  required NicoFyAudioHandler audioHandler,
  required void Function(Object error, StackTrace stackTrace) onError,
}) async {
  if (value == null || value.isEmpty) {
    return;
  }

  final normalizedValue = value.trim();
  if (normalizedValue.isEmpty) {
    return;
  }

  await handleYoutubeSharedTextIntent(
    normalizedValue,
    audioHandler: audioHandler,
    onError: onError,
  );
}
