import 'package:flutter_test/flutter_test.dart';
import 'package:nicofy/utilities/formatter.dart';

void main() {
  group('two videos are the same song', () {
    for (final title in [
      'Clocks (Live in Buenos Aires)',
      'Clocks - Remastered 2008',
      'Clocks [Official Video]',
      'CLOCKS',
      'Clocks feat. Someone',
      'Clocks | Lyrics',
      'Clocks Live',
    ]) {
      test(title, () => expect(songTitleKey(title), songTitleKey('Clocks')));
    }
  });

  test('another song stays another song', () {
    expect(songTitleKey('Fix You'), isNot(songTitleKey('Clocks')));
    expect(songTitleKey('La Vie en rose'), 'la vie en rose');
  });

  test('a title made only of version words keeps them', () {
    expect(songTitleKey('Live'), 'live');
  });
}
