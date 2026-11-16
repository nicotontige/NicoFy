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

import 'package:flutter/services.dart';
import 'package:nicofy/utilities/platform_utils.dart';

/// The model of this Android device ("Pixel 8", "MIBOX4"), so that a phone
/// and a TV box do not both call themselves "NicoFy (Android)". Null until
/// [loadDeviceIdentity] ran, or where it is unknown.
String? deviceModel;

/// Whether this device is a TV, driven with a remote.
bool isTelevision = false;

Future<void> loadDeviceIdentity() async {
  if (!isAndroidPlatform) return;
  try {
    final info = await const MethodChannel('nicofy/device')
        .invokeMapMethod<String, Object?>('identity');
    final model = info?['model'];
    if (model is String && model.trim().isNotEmpty) {
      final trimmed = model.trim();
      deviceModel = trimmed.length > 40 ? trimmed.substring(0, 40) : trimmed;
    }
    isTelevision = info?['television'] == true;
  } catch (_) {
    // An older build without the channel: the generic name will do.
  }
}
