import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nicofy/services/local_sync/sync_security.dart';
import 'package:nicofy/services/remote_control/remote_protocol.dart';
import 'package:nicofy/services/remote_control/remote_session.dart';

import 'fake_target.dart';

const tvId = 'tv-device';
const phoneId = 'phone-device';

/// The TV's side, with the phone paired to it.
class Tv {
  Tv() {
    host = build();
  }

  final target = FakeTarget();
  final secrets = <String, String>{phoneId: SyncSecurity.randomToken()};
  var enabled = true;
  DateTime now = DateTime(2026, 11, 16);
  late RemoteControlHost host;

  RemoteControlHost build() => RemoteControlHost(
    secretFor: (id) => secrets[id],
    ownId: () => tvId,
    deviceName: () => 'NicoFy (MIBOX4)',
    target: () => target,
    enabled: () => enabled,
    settle: Duration.zero,
    now: () => now,
  );

  /// Every request that went through, as the network would let anyone
  /// capture it.
  final sent = <(String, Map<String, dynamic>, Map<String, String>)>[];

  Future<Map<String, dynamic>> transport(
    String path,
    Map<String, dynamic> envelope,
    Map<String, String> headers,
    Duration timeout,
  ) async {
    final copy = jsonDecode(jsonEncode(envelope)) as Map<String, dynamic>;
    sent.add((path, copy, headers));
    final (status, body) = await host.handle(
      path,
      deviceId: headers[remoteDeviceHeader],
      sessionId: headers[remoteSessionHeader],
      envelope: copy,
    );
    if (status != 200) {
      throw RemoteRequestFailure(status, body['error'].toString());
    }
    return jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
  }

  RemoteControlClient phone({String? secret, String id = phoneId}) =>
      RemoteControlClient(
        ownId: id,
        peerId: tvId,
        secret: secret ?? secrets[phoneId]!,
        transport: transport,
      );

  /// Sends a captured request again, as an attacker on the network would.
  Future<(int, Map<String, dynamic>)> replay(int index) {
    final (path, envelope, headers) = sent[index];
    return host.handle(
      path,
      deviceId: headers[remoteDeviceHeader],
      sessionId: headers[remoteSessionHeader],
      envelope: envelope,
    );
  }
}

Matcher failsWith(int status, [String? code]) => throwsA(
  isA<RemoteRequestFailure>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.code, 'code', code ?? anything),
);

void main() {
  test('a paired phone sees what plays and drives it', () async {
    final tv = Tv();
    final phone = tv.phone();
    await phone.open();
    expect(phone.remoteName, 'NicoFy (MIBOX4)');

    final first = await phone.fetchState();
    expect(first.track!.ytid, 'a');
    expect(first.upcoming!.map((t) => t.ytid), ['b', 'c']);

    final again = await phone.fetchState(knownQueue: first.queueSignature);
    expect(again.upcoming, isNull);

    final paused = await phone.send(const RemoteCommand.pause());
    expect(paused.snapshot.playing, isFalse);
    final next = await phone.send(const RemoteCommand.next());
    expect(next.snapshot.track!.ytid, 'b');
    final radio = await phone.send(const RemoteCommand.radio());
    expect(radio.added, 25);
    expect(tv.target.calls, ['pause', 'next', 'radio']);
  });

  test('a device that is not paired is refused', () async {
    final tv = Tv();
    final stranger = tv.phone(
      id: 'stranger',
      secret: SyncSecurity.randomToken(),
    );
    await expectLater(stranger.open(), failsWith(403, 'not_paired'));
    expect(tv.host.sessionCount, 0);
  });

  test('a request forged without the pairing secret is refused', () async {
    final tv = Tv();
    // Claims to be the phone, which anyone can: its id is public.
    final forger = tv.phone(secret: SyncSecurity.randomToken());
    await expectLater(forger.open(), failsWith(403, 'not_paired'));
    expect(tv.host.sessionCount, 0);
    expect(tv.target.calls, isEmpty);
  });

  test('a session cannot be used by another device or a forged key', () async {
    final tv = Tv();
    tv.secrets['other'] = SyncSecurity.randomToken();
    final phone = tv.phone();
    await phone.open();
    await phone.fetchState();
    final (_, envelope, headers) = tv.sent.last;
    final session = headers[remoteSessionHeader];

    // Another paired device that learnt the session id.
    final (status, body) = await tv.host.handle(
      remoteCommandPath,
      deviceId: 'other',
      sessionId: session,
      envelope: envelope,
    );
    expect((status, body['error']), (401, 'session_expired'));

    // The right device and session, a key that is not the session's.
    final forged = {
      'apiVersion': remoteApiVersion,
      'encrypted': await SyncSecurity.seal(SyncSecurity.randomToken(), {
        'requestId': SyncSecurity.randomToken(24),
        'command': const RemoteCommand.next().toMap(),
      }, 'api/remote/command|$phoneId|$tvId|$session'),
    };
    final (forgedStatus, _) = await tv.host.handle(
      remoteCommandPath,
      deviceId: phoneId,
      sessionId: session,
      envelope: forged,
    );
    expect(forgedStatus, 403);
    expect(tv.target.calls, isEmpty);

    // The phone itself carries on.
    expect((await phone.fetchState()).track, isNotNull);
  });

  test('a captured command played again is refused', () async {
    final tv = Tv();
    final phone = tv.phone();
    await phone.send(const RemoteCommand.next());
    expect(tv.target.calls, ['next']);
    final commandIndex = tv.sent.lastIndexWhere(
      (request) => request.$1 == remoteCommandPath,
    );

    final (status, body) = await tv.replay(commandIndex);
    expect((status, body['error']), (403, 'replayed_request'));
    expect(tv.target.calls, ['next']);
  });

  test('a captured "open" played again gives nothing away', () async {
    final tv = Tv();
    final phone = tv.phone();
    await phone.open();
    final (status, body) = await tv.replay(0);
    expect(status, 200);
    // Only the pairing secret opens the reply holding the session key.
    await expectLater(
      SyncSecurity.open(
        SyncSecurity.randomToken(),
        body['encrypted'] as Map,
        'api/remote/open|$tvId|$phoneId',
      ),
      throwsA(anything),
    );
  });

  test('connections nobody uses go first when there are too many', () async {
    final tv = Tv();
    final phone = tv.phone();
    await phone.fetchState();
    for (var i = 0; i < RemoteControlHost.maxSessions + 3; i++) {
      await tv.replay(0);
    }
    expect(tv.host.sessionCount, RemoteControlHost.maxSessions);
    final before = tv.sent.length;
    await phone.fetchState();
    // Still the same connection: no new "open" was needed.
    expect(tv.sent.skip(before).map((r) => r.$1), [remoteStatePath]);
  });

  test('forgetting the phone ends its control', () async {
    final tv = Tv();
    final phone = tv.phone();
    await phone.fetchState();
    tv.secrets.remove(phoneId);
    await expectLater(phone.fetchState(), failsWith(403, 'not_paired'));
  });

  test('pairing again ends the connections of the old pairing', () async {
    final tv = Tv();
    final old = tv.phone();
    await old.fetchState();
    tv.secrets[phoneId] = SyncSecurity.randomToken();
    // The old secret no longer opens anything.
    await expectLater(old.fetchState(), failsWith(403, 'not_paired'));
    expect((await tv.phone().fetchState()).track, isNotNull);
  });

  test('the phone reconnects by itself after the TV restarted', () async {
    final tv = Tv();
    final phone = tv.phone();
    await phone.fetchState();
    tv.host = tv.build();
    expect((await phone.fetchState()).track, isNotNull);
    expect(tv.host.sessionCount, 1);
  });

  test('an idle connection expires', () async {
    final tv = Tv();
    final phone = tv.phone();
    await phone.fetchState();
    tv.now = tv.now.add(const Duration(hours: 1));
    final before = tv.sent.length;
    await phone.fetchState();
    expect(tv.sent.skip(before).map((r) => r.$1), [
      remoteStatePath,
      remoteOpenPath,
      remoteStatePath,
    ]);
  });

  test('control turned off on the TV refuses everything', () async {
    final tv = Tv();
    final phone = tv.phone();
    await phone.fetchState();
    tv.enabled = false;
    await expectLater(phone.fetchState(), failsWith(503, 'remote_off'));
    await expectLater(
      phone.send(const RemoteCommand.pause()),
      failsWith(503, 'remote_off'),
    );
    expect(tv.target.calls, isEmpty);
    expect(tv.host.sessionCount, 0);
  });

  test('a command for a moved queue comes back refused', () async {
    final tv = Tv();
    final phone = tv.phone();
    final shown = (await phone.fetchState()).upcoming!.last;
    tv.target.queue = [song('a'), song('x'), song('y')];
    final reply = await phone.send(RemoteCommand.skipTo(shown));
    expect(reply.error, RemoteCommandError.queueChanged);
    expect(reply.snapshot.upcoming!.map((t) => t.ytid), ['x', 'y']);
    expect(tv.target.calls, isEmpty);
  });

  test('a request that is not an envelope is refused', () async {
    final tv = Tv();
    final phone = tv.phone();
    await phone.fetchState();
    final session = tv.sent.last.$3[remoteSessionHeader];
    for (final envelope in [
      <String, dynamic>{'apiVersion': remoteApiVersion, 'encrypted': 'nope'},
      <String, dynamic>{'apiVersion': 99, 'encrypted': <String, dynamic>{}},
      <String, dynamic>{
        'apiVersion': remoteApiVersion,
        'encrypted': {'nonce': 'x', 'ciphertext': 'y', 'mac': 'z'},
      },
    ]) {
      final (status, _) = await tv.host.handle(
        remoteCommandPath,
        deviceId: phoneId,
        sessionId: session,
        envelope: envelope,
      );
      expect(status, anyOf(400, 426));
    }
    expect(tv.target.calls, isEmpty);
    expect((await phone.fetchState()).track, isNotNull);
  });
}
