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

/// Where the songs the app's screens start go instead of this device's
/// player: the device this one controls, while it does.
///
/// Only what the user starts from the screens goes through it. The car, the
/// notification and the queue the player works through itself stay here.
abstract class PlaybackRedirect {
  /// Whether songs go elsewhere right now.
  bool get isActive;

  /// Replaces the queue there with [songs], playing from [startIndex].
  Future<void> playList(List<Map> songs, {int? startIndex, bool? shuffle});

  /// Adds [songs] to the queue there, after the current song when [next],
  /// playing from [startIndex] when given.
  Future<void> enqueue(List<Map> songs, {bool next = false, int? startIndex});

  /// Plays [song] there, its queue left as it is.
  Future<void> playSong(Map song);

  /// Plays a radio station there; false when it could not.
  Future<bool> playStation({
    required String id,
    required String name,
    required String streamUrl,
    required String image,
    String? genre,
  });
}
