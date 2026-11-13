import 'package:flutter_test/flutter_test.dart';
import 'package:nicofy/services/update_manager.dart';

Map<String, dynamic> _release(
  String tag, {
  String body = '',
  bool apk = true,
  bool prerelease = false,
}) => {
  'tag_name': tag,
  'body': body,
  'draft': false,
  'prerelease': prerelease,
  'assets': [
    if (apk) {'name': 'NicoFy.apk'},
    {'name': 'NicoFy-windows-x64.zip'},
  ],
};

void main() {
  test('every release missed since the installed one, newest first', () {
    final notes = releaseNotesSince(
      [
        _release('1.0.1', body: 'lyrics'),
        _release('1.2.0', body: 'two'),
        _release('1.1.1', body: 'one'),
        _release('1.0.0', body: 'first'),
      ],
      installed: '1.0.1',
      latest: '1.2.0',
    );

    expect(notes, '**1.2.0**\ntwo\n\n**1.1.1**\none');
  });

  test('a release that shipped no APK is left out', () {
    final notes = releaseNotesSince(
      [
        _release('1.1.1', body: 'fixed build'),
        _release('1.1.0', body: 'never on a phone', apk: false),
      ],
      installed: '1.0.1',
      latest: '1.1.1',
    );

    expect(notes, '**1.1.1**\nfixed build');
  });

  test('nothing newer than the announced version, nor a prerelease', () {
    final notes = releaseNotesSince(
      [
        _release('1.3.0', body: 'not announced yet'),
        _release('1.2.1', body: 'beta', prerelease: true),
        _release('nicofy', body: 'branch build'),
        _release('1.2.0', body: 'two'),
      ],
      installed: '1.1.1',
      latest: '1.2.0',
    );

    expect(notes, '**1.2.0**\ntwo');
  });
}
