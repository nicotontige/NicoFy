import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nicofy/services/local_sync/sync_security.dart';
import 'package:nicofy/services/local_sync_service.dart';
import 'package:nicofy/services/remote_control/remote_protocol.dart';
import 'package:nicofy/services/remote_control/remote_session.dart';
import 'package:nicofy/services/settings_manager.dart';

import '../local_sync/service_harness.dart';
import 'fake_target.dart';

RemoteTransport httpTo(LocalSyncService service) =>
    (path, envelope, headers, timeout) async {
      final response = await http
          .post(
            Uri.parse('http://127.0.0.1:${service.serverPort}$path'),
            headers: {'Content-Type': 'application/json', ...headers},
            body: jsonEncode(envelope),
          )
          .timeout(timeout);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw RemoteRequestFailure(response.statusCode, '${body['error']}');
      }
      return body;
    };

void main() {
  final h = SyncHarness();
  late FakeTarget target;
  setUpAll(h.openStorage);
  setUp(() async {
    await h.start();
    target = FakeTarget();
    h.server.remoteTarget = target;
    remoteControlEnabled.value = true;
  });
  tearDown(h.stop);
  tearDownAll(h.closeStorage);

  RemoteControlClient phone(LocalSyncService service, {String? secret}) =>
      RemoteControlClient(
        ownId: SyncHarness.peerId,
        peerId: h.ownId,
        secret: secret ?? h.secret,
        transport: httpTo(service),
      );

  test('a paired device controls playback over the sync server', () async {
    final client = phone(h.server);
    final snapshot = await client.fetchState();
    expect(snapshot.track!.ytid, 'a');
    final reply = await client.send(
      RemoteCommand.seek(const Duration(seconds: 90)),
    );
    expect(reply.snapshot.positionMs, 90000);
    expect(target.calls, ['seek:90000']);
  });

  test('without the pairing secret nothing gets through', () async {
    await expectLater(
      phone(h.server, secret: SyncSecurity.randomToken()).fetchState(),
      throwsA(
        isA<RemoteRequestFailure>().having((e) => e.status, 'status', 403),
      ),
    );
    expect(target.calls, isEmpty);
  });

  test('turning remote control off refuses it at once', () async {
    final client = phone(h.server);
    await client.fetchState();
    await h.server.setRemoteControlEnabled(false);
    await expectLater(
      client.send(const RemoteCommand.pause()),
      throwsA(
        isA<RemoteRequestFailure>().having((e) => e.status, 'status', 503),
      ),
    );
    expect(target.calls, isEmpty);
    await h.server.setRemoteControlEnabled(true);
  });

  test('a server up for remote control only does not sync', () async {
    final service = LocalSyncService.forTesting()..remoteTarget = target;
    await service.savePairedDevice(
      PairedSyncDevice(
        deviceId: SyncHarness.peerId,
        name: 'Fixture',
        secret: h.secret,
      ),
    );
    await service.setRemoteHosting(true);
    try {
      expect(service.serverPort, isNotNull);
      final response = await http.post(
        Uri.parse(
          'http://127.0.0.1:${service.serverPort}/api/sync/capabilities',
        ),
        headers: {
          'Content-Type': 'application/json',
          'x-musify-device': SyncHarness.peerId,
        },
        body: jsonEncode(await h.envelope('capabilities', {})),
      );
      expect(response.statusCode, 503);
      expect(jsonDecode(response.body)['error'], 'sync_off');

      // Remote control works there all the same.
      expect((await phone(service).fetchState()).track, isNotNull);

      // Turning sync off keeps it up for remote control...
      await service.setEnabled(false);
      expect(service.serverPort, isNotNull);
      // ...and no longer hosting lets it stop.
      await service.setRemoteHosting(false);
      expect(service.serverPort, isNull);
    } finally {
      await service.dispose();
    }
  });

  test('sync still answers when the server runs for both', () async {
    await h.server.setRemoteHosting(true);
    final capabilities = await h.secure('capabilities', {});
    expect(capabilities.status, 200);
    await h.server.setRemoteHosting(false);
    // Sync was on: the server stays.
    expect(h.server.serverPort, isNotNull);
  });
}
