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

import 'package:cryptography/cryptography.dart'
    show SecretBoxAuthenticationError;
import 'package:nicofy/services/local_sync/sync_data.dart';
import 'package:nicofy/services/local_sync/sync_security.dart';
import 'package:nicofy/services/remote_control/remote_protocol.dart';

// How a remote talks to the device it controls, on the local sync server.
//
// Only a device paired by PIN may: the first request of a connection
// ("open") is encrypted with the pairing secret, and the reply hands back a
// fresh key for this connection only. Every request after it (a snapshot
// about once a second, or a command) is encrypted with that key and carries
// a random id the device refuses to see twice. A replayed "open" only
// creates a connection nobody else can read; a replayed command is refused.
//
// The pairing's own replay counter is left alone: it is written to disk on
// each request, which once a second on a TV box is too much, and requests
// sent at the same time may arrive out of order, which it would refuse.

typedef RemoteReply = (int, Map<String, dynamic>);

const String remoteOpenPath = '/api/remote/open';
const String remoteStatePath = '/api/remote/state';
const String remoteCommandPath = '/api/remote/command';
const String remoteDeviceHeader = 'x-musify-device';
const String remoteSessionHeader = 'x-nicofy-remote-session';

/// The largest request a remote sends: a list of [remoteListLimit] songs is
/// about 200 KB of JSON, a quarter of that once compressed and encrypted.
const int remoteMaxRequestBytes = 1024 * 1024;

/// An answer other than success, from the device or on the way to it.
class RemoteRequestFailure implements Exception {
  const RemoteRequestFailure(this.status, this.code);

  final int status;
  final String code;

  @override
  String toString() => 'HTTP $status: $code';
}

String _context(String path, String from, String to, [String? session]) =>
    '${path.substring(1)}|$from|$to${session == null ? '' : '|$session'}';

bool _isRequestId(Object? id) =>
    id is String && id.length >= 20 && id.length <= 128;

class _RemoteSession {
  _RemoteSession(this.deviceId, this.secretDigest, this.key, this.lastUsed);

  final String deviceId;

  /// Pairing again, or forgetting the device, ends the connection.
  final String secretDigest;
  final String key;
  DateTime lastUsed;
  bool used = false;
  final Set<String> seen = {};
}

/// The controlled side: answers the requests of paired remotes.
class RemoteControlHost {
  RemoteControlHost({
    required this.secretFor,
    required this.ownId,
    required this.deviceName,
    required this.target,
    required this.enabled,
    this.settle = const Duration(milliseconds: 1500),
    DateTime Function()? now,
    this.onError,
  }) : _now = now ?? DateTime.now;

  /// The pairing secret shared with a device, null when not paired.
  final String? Function(String deviceId) secretFor;
  final String Function() ownId;
  final String Function() deviceName;
  final RemotePlaybackTarget? Function() target;

  /// Whether this device lets paired devices control it.
  final bool Function() enabled;
  final Duration settle;
  final DateTime Function() _now;
  final void Function(Object error, StackTrace stackTrace)? onError;

  static const int maxSessions = 8;
  static const Duration idleTimeout = Duration(minutes: 10);

  /// About five hours of one request a second; the remote then reconnects.
  static const int maxRequestsPerSession = 20000;

  final Map<String, _RemoteSession> _sessions = {};

  int get sessionCount => _sessions.length;

  /// Ends every connection, when control is turned off for instance.
  void closeAll() => _sessions.clear();

  Future<RemoteReply> handle(
    String path, {
    required String? deviceId,
    required String? sessionId,
    required Map<String, dynamic> envelope,
  }) async {
    final player = target();
    if (!enabled() || player == null) {
      _sessions.clear();
      return (503, {'error': 'remote_off'});
    }
    if (deviceId == null) return (426, {'error': 'upgrade_required'});
    final secret = secretFor(deviceId);
    if (secret == null || secret.isEmpty) {
      return (403, {'error': 'not_paired'});
    }
    if (envelope['apiVersion'] != remoteApiVersion) {
      return (426, {'error': 'upgrade_required'});
    }
    final box = envelope['encrypted'];
    if (box is! Map) return (400, {'error': 'invalid'});

    try {
      if (path == remoteOpenPath) {
        return await _open(deviceId, secret, box);
      }
      if (path != remoteStatePath && path != remoteCommandPath) {
        return (404, {'error': 'not_found'});
      }
      return await _inSession(path, deviceId, secret, sessionId, box, player);
    } catch (e, stackTrace) {
      onError?.call(e, stackTrace);
      return (400, {'error': 'invalid'});
    }
  }

  Future<RemoteReply> _open(String deviceId, String secret, Map box) async {
    final own = ownId();
    final Map<String, dynamic> body;
    try {
      body = await SyncSecurity.open(
        secret,
        box,
        _context(remoteOpenPath, deviceId, own),
      );
    } on SecretBoxAuthenticationError {
      return (403, {'error': 'not_paired'});
    } catch (_) {
      return (400, {'error': 'invalid'});
    }
    if (!_isRequestId(body['requestId'])) {
      return (400, {'error': 'invalid_request'});
    }

    _expire();
    if (_sessions.length >= maxSessions) {
      // Connections nobody used yet go first: a replayed "open" must not
      // push out the remote that is actually in use.
      final victim = _sessions.entries.reduce(
        (a, b) => a.value.used == b.value.used
            ? (a.value.lastUsed.isBefore(b.value.lastUsed) ? a : b)
            : (a.value.used ? b : a),
      );
      _sessions.remove(victim.key);
    }
    final id = SyncSecurity.randomToken(16);
    final key = SyncSecurity.randomToken();
    _sessions[id] = _RemoteSession(deviceId, syncDigest(secret), key, _now());
    return (
      200,
      {
        'encrypted': await SyncSecurity.seal(secret, {
          'requestId': body['requestId'],
          'session': id,
          'key': key,
          'deviceName': deviceName(),
        }, _context(remoteOpenPath, own, deviceId)),
      },
    );
  }

  Future<RemoteReply> _inSession(
    String path,
    String deviceId,
    String secret,
    String? sessionId,
    Map box,
    RemotePlaybackTarget player,
  ) async {
    _expire();
    final session = sessionId == null ? null : _sessions[sessionId];
    if (session == null ||
        session.deviceId != deviceId ||
        session.secretDigest != syncDigest(secret) ||
        session.seen.length >= maxRequestsPerSession) {
      if (session != null && session.deviceId == deviceId) {
        _sessions.remove(sessionId);
      }
      return (401, {'error': 'session_expired'});
    }
    final own = ownId();
    final Map<String, dynamic> body;
    try {
      body = await SyncSecurity.open(
        session.key,
        box,
        _context(path, deviceId, own, sessionId),
      );
    } on SecretBoxAuthenticationError {
      // Not from the device that opened it: the connection itself is fine.
      return (403, {'error': 'forbidden'});
    } catch (_) {
      return (400, {'error': 'invalid'});
    }
    final requestId = body['requestId'];
    if (!_isRequestId(requestId)) return (400, {'error': 'invalid_request'});
    if (!session.seen.add(requestId as String)) {
      return (403, {'error': 'replayed_request'});
    }
    session
      ..lastUsed = _now()
      ..used = true;

    final known = body['knownQueue'];
    final knownQueue = known is String ? known : null;
    final reply = <String, dynamic>{'requestId': requestId};
    if (path == remoteCommandPath) {
      final RemoteCommand command;
      try {
        command = RemoteCommand.fromMap(body['command'] as Map);
      } catch (_) {
        return (400, {'error': 'invalid_command'});
      }
      final result = await dispatchRemoteCommand(
        player,
        command,
        settle: settle,
        onError: onError,
      );
      if (result.error != null) reply['error'] = result.error!.name;
      if (result.added != null) reply['added'] = result.added;
    }
    reply['snapshot'] = buildRemoteSnapshot(
      player,
      knownQueue: knownQueue,
    ).toMap();
    return (
      200,
      {
        'encrypted': await SyncSecurity.seal(
          session.key,
          reply,
          _context(path, own, deviceId, sessionId),
        ),
      },
    );
  }

  void _expire() {
    final now = _now();
    _sessions.removeWhere(
      (_, session) => now.difference(session.lastUsed) > idleTimeout,
    );
  }
}

/// Sends [envelope] to [path] on the controlled device and returns its JSON
/// reply; throws [RemoteRequestFailure] for an answer other than success.
typedef RemoteTransport = Future<Map<String, dynamic>> Function(
  String path,
  Map<String, dynamic> envelope,
  Map<String, String> headers,
  Duration timeout,
);

class RemoteCommandReply {
  const RemoteCommandReply({required this.snapshot, this.error, this.added});

  final RemoteSnapshot snapshot;
  final RemoteCommandError? error;

  /// How many songs a radio queued.
  final int? added;
}

/// The controlling side of one connection to one paired device.
class RemoteControlClient {
  RemoteControlClient({
    required this.ownId,
    required this.peerId,
    required this.secret,
    required this.transport,
  });

  final String ownId;
  final String peerId;
  final String secret;
  final RemoteTransport transport;

  static const Duration stateTimeout = Duration(seconds: 4);
  static const Duration commandTimeout = Duration(seconds: 8);

  /// A radio fetches its songs before answering.
  static const Duration radioTimeout = Duration(seconds: 30);

  String? _sessionId;
  String? _sessionKey;
  Future<void>? _opening;

  /// The name the other device gave itself when last connected.
  String? remoteName;

  bool get isOpen => _sessionId != null;

  void close() {
    _sessionId = null;
    _sessionKey = null;
  }

  Future<void> open() =>
      _opening ??= _open().whenComplete(() => _opening = null);

  Future<void> _open() async {
    final requestId = SyncSecurity.randomToken(24);
    final response = await transport(
      remoteOpenPath,
      {
        'apiVersion': remoteApiVersion,
        'encrypted': await SyncSecurity.seal(secret, {
          'requestId': requestId,
        }, _context(remoteOpenPath, ownId, peerId)),
      },
      {remoteDeviceHeader: ownId},
      stateTimeout,
    );
    final box = response['encrypted'];
    if (box is! Map) throw const RemoteRequestFailure(200, 'invalid_reply');
    final reply = await SyncSecurity.open(
      secret,
      box,
      _context(remoteOpenPath, peerId, ownId),
    );
    final session = reply['session'];
    final key = reply['key'];
    if (reply['requestId'] != requestId ||
        session is! String ||
        session.isEmpty ||
        session.length > 64 ||
        key is! String ||
        key.isEmpty) {
      throw const RemoteRequestFailure(200, 'invalid_reply');
    }
    _sessionId = session;
    _sessionKey = key;
    final name = reply['deviceName'];
    if (name is String && name.isNotEmpty) {
      remoteName = name.length > 100 ? name.substring(0, 100) : name;
    }
  }

  Future<RemoteSnapshot> fetchState({String? knownQueue}) async {
    final reply = await _request(remoteStatePath, {
      if (knownQueue != null) 'knownQueue': knownQueue,
    }, stateTimeout);
    return RemoteSnapshot.fromMap(reply['snapshot']);
  }

  Future<RemoteCommandReply> send(
    RemoteCommand command, {
    String? knownQueue,
  }) async {
    final reply = await _request(
      remoteCommandPath,
      {
        'command': command.toMap(),
        if (knownQueue != null) 'knownQueue': knownQueue,
      },
      command.action == RemoteAction.radio ||
              command.action == RemoteAction.playStation
          ? radioTimeout
          : commandTimeout,
    );
    final error = reply['error'];
    final added = reply['added'];
    return RemoteCommandReply(
      snapshot: RemoteSnapshot.fromMap(reply['snapshot']),
      error: RemoteCommandError.values
          .where((value) => value.name == error)
          .firstOrNull,
      added: added is int ? added : null,
    );
  }

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, dynamic> body,
    Duration timeout, {
    bool retried = false,
  }) async {
    if (!isOpen) await open();
    final session = _sessionId!;
    final key = _sessionKey!;
    final requestId = SyncSecurity.randomToken(24);
    final Map<String, dynamic> response;
    try {
      response = await transport(
        path,
        {
          'apiVersion': remoteApiVersion,
          'encrypted': await SyncSecurity.seal(key, {
            ...body,
            'requestId': requestId,
          }, _context(path, ownId, peerId, session)),
        },
        {remoteDeviceHeader: ownId, remoteSessionHeader: session},
        timeout,
      );
    } on RemoteRequestFailure catch (e) {
      // The other device restarted, or the connection sat idle too long: a
      // new one, once. The request was not carried out, so sending it again
      // cannot do it twice.
      if (e.status == 401 && !retried) {
        if (_sessionId == session) close();
        return _request(path, body, timeout, retried: true);
      }
      rethrow;
    }
    final box = response['encrypted'];
    if (box is! Map) throw const RemoteRequestFailure(200, 'invalid_reply');
    final reply = await SyncSecurity.open(
      key,
      box,
      _context(path, peerId, ownId, session),
    );
    if (reply['requestId'] != requestId) {
      throw const RemoteRequestFailure(200, 'invalid_reply');
    }
    return reply;
  }
}
