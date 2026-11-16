import 'package:nicofy/services/remote_control/remote_protocol.dart';

Map<String, dynamic> song(String id, {String? image}) => {
  'ytid': id,
  'title': 'Title $id',
  'artist': 'Artist $id',
  'highResImage': image ?? 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
  'duration': 180,
};

/// A player that records what it was asked to do.
class FakeTarget implements RemotePlaybackTarget {
  FakeTarget({List<Map>? queue, this.currentIndex = 0})
    : queue = queue ?? [song('a'), song('b'), song('c')];

  @override
  List<Map> queue;
  @override
  int currentIndex;
  @override
  bool playing = true;
  @override
  RemoteProcessing processing = RemoteProcessing.ready;
  @override
  Duration position = const Duration(seconds: 42);
  @override
  Duration? duration = const Duration(minutes: 3);
  @override
  double speed = 1;
  @override
  bool canSkipToNext = true;
  @override
  bool hasPrevious = true;

  final List<String> calls = [];
  int radioSongs = 25;

  @override
  Future<void> play() async {
    calls.add('play');
    playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> skipToNext() async {
    calls.add('next');
    currentIndex++;
  }

  @override
  Future<void> skipToPrevious() async {
    calls.add('previous');
    if (currentIndex > 0) currentIndex--;
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
    this.position = position;
  }

  @override
  Future<void> skipToSong(int index) async {
    calls.add('skipTo:$index');
    currentIndex = index;
  }

  @override
  Future<int> startRadio() async {
    calls.add('radio');
    return radioSongs;
  }
}
