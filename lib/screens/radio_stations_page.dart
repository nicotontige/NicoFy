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
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/constants/app_constants.dart';
import 'package:nicofy/database/radio_stations.db.dart';
import 'package:nicofy/extensions/l10n.dart';
import 'package:nicofy/main.dart';
import 'package:nicofy/models/radio_model.dart';
import 'package:nicofy/services/common_services.dart';
import 'package:nicofy/utilities/flutter_toast.dart';
import 'package:nicofy/widgets/mini_player_bottom_space.dart';
import 'package:nicofy/widgets/radio_station_card.dart';

class RadioStationsPage extends StatelessWidget {
  const RadioStationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n!.radioStations)),
      body: ValueListenableBuilder(
        valueListenable: userLikedRadioStations,
        builder: (context, likedStations, _) {
          final stations = _sortWithLikedFirst(
            radioStationsDB,
            likedStations.toSet(),
          );

          if (stations.isEmpty) {
            return Center(child: Text(context.l10n!.noRadioStations));
          }

          return SingleChildScrollView(
            padding: commonSingleChildScrollViewPadding,
            child: Column(
              children: [
                ...List.generate(stations.length, (index) {
                  final station = stations[index];
                  return Padding(
                    key: ValueKey(station.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RadioStationCard(
                      station: station,
                      onPressed: () async {
                        final success = await audioHandler.playRadioStream(
                          id: station.id,
                          name: station.name,
                          streamUrl: station.streamUrl,
                          image: station.image,
                          genre: station.genre,
                        );

                        if (!success && context.mounted) {
                          showToast(context, context.l10n!.error);
                        }
                      },
                    ),
                  );
                }),
                const MiniPlayerBottomSpace(),
              ],
            ),
          );
        },
      ),
    );
  }
}

List<RadioStation> _sortWithLikedFirst(
  List<RadioStation> stations,
  Set<String> likedIds,
) {
  final liked = <RadioStation>[];
  final rest = <RadioStation>[];

  for (final station in stations) {
    if (likedIds.contains(station.id)) {
      liked.add(station);
    } else {
      rest.add(station);
    }
  }

  return [...liked, ...rest];
}
