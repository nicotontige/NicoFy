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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/extensions/l10n.dart';
import 'package:nicofy/localization/app_localizations.dart';
import 'package:nicofy/services/local_sync_service.dart';
import 'package:nicofy/services/remote_control/remote_control_controller.dart';
import 'package:nicofy/utilities/device_identity.dart';

/// Why controlling [name] did not work, for the user.
String remoteFailureMessage(
  AppLocalizations l10n,
  RemoteFailure failure,
  String name,
) => switch (failure) {
  RemoteFailure.untrusted => l10n.remoteErrorUntrusted(name),
  RemoteFailure.remoteOff => l10n.remoteErrorOff(name),
  RemoteFailure.updateRequired => l10n.remoteErrorUpdate(name),
  RemoteFailure.unreachable => l10n.remoteErrorUnreachable(name),
  RemoteFailure.failed => l10n.remoteErrorFailed(name),
};

String _pairingFailureMessage(
  AppLocalizations l10n,
  LocalSyncError error,
  String name,
) => switch (error) {
  LocalSyncError.incorrectPin => l10n.syncErrorIncorrectPin(name),
  LocalSyncError.rejected => l10n.syncErrorRejected(name),
  LocalSyncError.busy => l10n.syncErrorBusy(name),
  LocalSyncError.updateRequired => l10n.remoteErrorUpdate(name),
  LocalSyncError.unreachable => l10n.remoteErrorUnreachable(name),
  _ => l10n.remoteErrorFailed(name),
};

/// Lists the NicoFy devices on the network to control one of them, pairing
/// it first if needed. True once this device controls another.
Future<bool> showRemoteDevicePicker(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => const _RemoteDevicePicker(),
    ) ??
    false;

/// The button that opens [showRemoteDevicePicker]; lit while this device
/// controls another. [onConnected] runs once it does.
class RemoteDevicesButton extends StatelessWidget {
  const RemoteDevicesButton({super.key, required this.onConnected, this.style});

  final void Function(BuildContext context) onConnected;
  final ButtonStyle? style;

  /// Not on a TV: it is the device being controlled, not the remote.
  static bool get isAvailable =>
      LocalSyncService.instance.isSupportedPlatform && !isTelevision;

  @override
  Widget build(BuildContext context) {
    if (!isAvailable) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<RemoteControlState?>(
      valueListenable: RemoteControlController.instance.state,
      builder: (context, remote, _) => IconButton(
        tooltip: context.l10n!.remoteDevices,
        style: style,
        icon: Icon(
          remote == null
              ? FluentIcons.cast_24_regular
              : FluentIcons.cast_24_filled,
          color: remote == null ? null : colorScheme.primary,
        ),
        onPressed: () async {
          if (await showRemoteDevicePicker(context) && context.mounted) {
            onConnected(context);
          }
        },
      ),
    );
  }
}

class _RemoteDevicePicker extends StatefulWidget {
  const _RemoteDevicePicker();

  @override
  State<_RemoteDevicePicker> createState() => _RemoteDevicePickerState();
}

class _RemoteDevicePickerState extends State<_RemoteDevicePicker> {
  final _service = LocalSyncService.instance;
  final _controller = RemoteControlController.instance;

  List<DiscoveredSyncDevice> _devices = const [];
  bool _scanning = false;
  String? _busyId;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _message = null;
    });
    final found = await _service.discoverDevices(
      duration: const Duration(seconds: 3),
      onFound: (devices) {
        if (mounted) setState(() => _devices = devices);
      },
    );
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _devices = found;
    });
  }

  String _nameOf(DiscoveredSyncDevice device) =>
      _service.pairedDevices.value
          .where((d) => d.deviceId == device.deviceId)
          .firstOrNull
          ?.name ??
      device.name;

  Future<void> _choose(DiscoveredSyncDevice device) async {
    if (_busyId != null) return;
    final l10n = context.l10n!;
    final name = _nameOf(device);
    if (_controller.state.value?.device.deviceId == device.deviceId) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busyId = device.deviceId;
      _message = null;
    });
    try {
      if (!_service.isDevicePaired(device.deviceId)) {
        final error = await _service.pairWith(
          device,
          askPin: () => _askPin(name),
        );
        if (!mounted) return;
        if (error != null) {
          setState(() => _message = _pairingFailureMessage(l10n, error, name));
          return;
        }
        // The PIN entry was cancelled.
        if (!_service.isDevicePaired(device.deviceId)) return;
      }
      final failure = await _controller.connect(device);
      if (!mounted) return;
      if (failure == null) {
        Navigator.pop(context, true);
        return;
      }
      // The other device forgot this one: the secret kept here is useless,
      // and forgetting it lets the next tap pair them again.
      if (failure == RemoteFailure.untrusted) {
        await _service.forgetDevice(device.deviceId);
      }
      if (mounted) {
        setState(() => _message = remoteFailureMessage(l10n, failure, name));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<String?> _askPin(String name) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n!;
        final theme = Theme.of(dialogContext);
        void submit() {
          final pin = controller.text.trim();
          if (pin.length == 6) Navigator.pop(dialogContext, pin);
        }

        return AlertDialog(
          title: Text(l10n.syncPairWith(name)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.syncPinInstructions, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: theme.textTheme.headlineSmall?.copyWith(
                  letterSpacing: 10,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: '······',
                  counterText: '',
                ),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(onPressed: submit, child: Text(l10n.syncPair)),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final colorScheme = Theme.of(context).colorScheme;
    final active = _controller.state.value;

    return AlertDialog(
      icon: Icon(FluentIcons.cast_24_regular, color: colorScheme.primary),
      title: Text(l10n.remoteDevicesTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.remoteDevicesDescription,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(FluentIcons.phone_24_regular),
                title: Text(l10n.syncThisDevice),
                trailing: active == null
                    ? Icon(
                        FluentIcons.checkmark_24_filled,
                        color: colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(context, false);
                  _controller.disconnect();
                },
              ),
              for (final device in _devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(FluentIcons.tv_24_regular),
                  title: Text(_nameOf(device)),
                  subtitle: Text(
                    _service.isDevicePaired(device.deviceId)
                        ? l10n.remotePaired
                        : l10n.remoteNotPaired,
                  ),
                  trailing: _busyId == device.deviceId
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : active?.device.deviceId == device.deviceId
                      ? Icon(
                          FluentIcons.checkmark_24_filled,
                          color: colorScheme.primary,
                        )
                      : null,
                  onTap: _busyId == null ? () => _choose(device) : null,
                ),
              if (_scanning)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                )
              else if (_devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.remoteNoDevices,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _message!,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _scanning || _busyId != null ? null : _scan,
          child: Text(l10n.syncScanAgain),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
