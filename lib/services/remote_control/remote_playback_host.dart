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

import 'package:audio_service/audio_service.dart';
import 'package:nicofy/services/audio_service.dart';
import 'package:nicofy/services/local_sync_service.dart';
import 'package:nicofy/services/remote_control/remote_protocol.dart';
import 'package:nicofy/services/settings_manager.dart';
import 'package:nicofy/utilities/platform_utils.dart';

/// The app's player, as a paired remote sees and drives it.
class AudioHandlerRemoteTarget implements RemotePlaybackTarget {
  AudioHandlerRemoteTarget(this.handler);

  final NicoFyAudioHandler handler;

  @override
  List<Map> get queue => handler.browserQueue;

  @override
  int get currentIndex => handler.currentQueueIndex;

  @override
  bool get playing => handler.playbackState.value.playing;

  @override
  RemoteProcessing get processing =>
      switch (handler.playbackState.value.processingState) {
        AudioProcessingState.idle => RemoteProcessing.idle,
        AudioProcessingState.loading => RemoteProcessing.loading,
        AudioProcessingState.buffering => RemoteProcessing.buffering,
        AudioProcessingState.ready => RemoteProcessing.ready,
        AudioProcessingState.completed => RemoteProcessing.completed,
        AudioProcessingState.error => RemoteProcessing.error,
      };

  @override
  Duration get position => handler.audioPlayer.position;

  @override
  Duration? get duration => handler.audioPlayer.duration;

  @override
  double get speed => handler.audioPlayer.speed;

  @override
  bool get canSkipToNext => handler.canSkipToNext;

  @override
  bool get hasPrevious => handler.hasPrevious;

  @override
  Future<void> play() => handler.play();

  @override
  Future<void> pause() => handler.pause();

  @override
  Future<void> skipToNext() => handler.skipToNext();

  @override
  Future<void> skipToPrevious() => handler.skipToPrevious();

  @override
  Future<void> seek(Duration position) => handler.seek(position);

  @override
  Future<void> skipToSong(int index) => handler.skipToSong(index);

  @override
  Future<int> startRadio() => handler.startRadio();

  // What a remote starts plays on this device's own player, even if this
  // device happens to control yet another one.

  @override
  String entryIdOf(Map song) => handler.ensureBrowserQueueEntryId(song);

  @override
  Future<void> playList(List<Map> songs, {int? startIndex, bool? shuffle}) =>
      handler.addPlaylistToQueueHere(
        songs,
        replace: true,
        startIndex: startIndex,
        shuffle: shuffle,
      );

  @override
  Future<void> enqueue(
    List<Map> songs, {
    bool next = false,
    int? startIndex,
  }) async {
    if (next) {
      // Each goes right after the current song: the last first keeps them in
      // the order they were picked.
      for (final song in songs.reversed) {
        await handler.addToQueueHere(song, playNext: true);
      }
    } else if (songs.length == 1 && startIndex == null) {
      await handler.addToQueueHere(songs.single);
    } else {
      await handler.addPlaylistToQueueHere(songs, startIndex: startIndex);
    }
  }

  @override
  Future<void> playSong(Map song) => handler.playSongHere(song);

  @override
  Future<bool> playStation({
    required String id,
    required String name,
    required String streamUrl,
    required String image,
    String? genre,
  }) => handler.playRadioStreamHere(
    id: id,
    name: name,
    streamUrl: streamUrl,
    image: image,
    genre: genre,
  );

  @override
  Future<void> removeFromQueue(int index) => handler.removeFromQueue(index);

  @override
  Future<void> moveEntry(String entryId, int toIndex) =>
      handler.reorderQueueById(entryId, toIndex);

  @override
  Future<void> clearQueue() async => handler.clearQueue();

  @override
  Future<void> shuffleQueue() => handler.shuffleQueue();
}

/// Lets paired devices control [handler]: on Android the local sync server
/// stays up for that from the first song loaded, even with sync turned off,
/// as long as remote control is allowed. A device that never plays anything,
/// a phone used only as a remote, keeps its server off. A computer is only
/// controllable while its sync is on: opening a server there by surprise
/// would have its firewall ask about it.
void startRemoteControlHosting(NicoFyAudioHandler handler) {
  final service = LocalSyncService.instance;
  if (!service.isSupportedPlatform) return;
  service.remoteTarget = AudioHandlerRemoteTarget(handler);
  if (!isAndroidPlatform) return;

  var hadMedia = handler.mediaItem.value != null;
  void update() => unawaited(
    service.setRemoteHosting(remoteControlEnabled.value && hadMedia),
  );

  remoteControlEnabled.addListener(update);
  if (hadMedia) {
    update();
    return;
  }
  unawaited(
    handler.mediaItem.firstWhere((item) => item != null).then((_) {
      hadMedia = true;
      update();
    }),
  );
}
