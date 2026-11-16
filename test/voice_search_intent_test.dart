import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nicofy/services/voice_search_intent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nicofy/voice');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('plays the search that opened the app', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'takePendingQuery' ? 'daft punk' : null,
    );
    final played = <String>[];

    await listenToVoiceSearchIntents((query) async => played.add(query));

    expect(played, ['daft punk']);
  });

  test('plays a search that comes in later', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final played = <String>[];
    await listenToVoiceSearchIntents((query) async => played.add(query));
    expect(played, isEmpty);

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('playFromSearch', 'Clocks'),
      ),
      (_) {},
    );

    expect(played, ['Clocks']);
  });

  test('copes with a build without the channel', () async {
    final played = <String>[];

    await listenToVoiceSearchIntents((query) async => played.add(query));

    expect(played, isEmpty);
  });
}
