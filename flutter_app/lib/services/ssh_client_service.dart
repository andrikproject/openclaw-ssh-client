import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart' as ssh;

/// SSH Client Service — koneksi ke VPS via SSH
class SshClientService {
  ssh.SSHClient? _client;
  ssh.SSHShell? _shell;
  StreamSubscription? _outputSub;
  bool _disposed = false;

  bool get isConnected => _client != null && _shell != null;

  StreamController<SshClientEvent> _controller = StreamController<SshClientEvent>.broadcast();
  Stream<SshClientEvent> get events => _controller.stream;

  /// Connect ke VPS
  Future<bool> connect({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    try {
      _controller.add(SshClientEvent(status: 'connecting', text: 'Connecting to $host:$port...\n'));

      final socket = await ssh.SSHClient.connect(
        host,
        port: port,
      );

      _controller.add(SshClientEvent(status: 'authenticating', text: 'Authenticating...\n'));

      await socket.authenticate(
        (username) => ssh.SSHKeyboardAuth(
          username: username,
          password: password,
        ),
      );

      _client = socket;

      _controller.add(SshClientEvent(status: 'starting_shell', text: 'Opening shell...\n'));

      _shell = await _client!.shell(
        terminal: 'xterm-256color',
        terminalWidth: 80,
        terminalHeight: 24,
      );

      _outputSub = _shell!.stdout.listen(
        (data) {
          if (!_disposed) {
            _controller.add(SshClientEvent(
              status: 'data',
              text: utf8.decode(data, allowMalformed: true),
            ));
          }
        },
        onError: (err) {
          if (!_disposed) {
            _controller.add(SshClientEvent(
              status: 'error',
              text: 'SSH Error: $err\n',
            ));
          }
        },
        onDone: () {
          if (!_disposed) {
            _controller.add(SshClientEvent(
              status: 'disconnected',
              text: '\nConnection closed.\n',
            ));
          }
        },
      );

      _controller.add(SshClientEvent(status: 'connected', text: '✓ Connected to $host\n'));
      return true;
    } catch (e) {
      _controller.add(SshClientEvent(
        status: 'error',
        text: '✗ Connection failed: $e\n',
      ));
      return false;
    }
  }

  /// Kirim command ke shell
  void sendCommand(String cmd) {
    if (_shell != null && !_disposed) {
      _shell!.stdin.add(utf8.encode(cmd));
      _controller.add(SshClientEvent(status: 'data', text: cmd));
    }
  }

  /// Kirim Enter
  void sendEnter() {
    if (_shell != null && !_disposed) {
      _shell!.stdin.add(utf8.encode('\n'));
    }
  }

  /// Kirim Ctrl+C
  void sendCtrlC() {
    if (_shell != null && !_disposed) {
      _shell!.stdin.add([3]); // ASCII ETX
    }
  }

  /// Disconnect
  Future<void> disconnect() async {
    _disposed = true;
    await _outputSub?.cancel();
    await _shell?.close();
    _shell = null;
    _client = null;
    _controller.add(SshClientEvent(status: 'disconnected', text: 'Disconnected.\n'));
  }

  void dispose() {
    _disposed = true;
    _outputSub?.cancel();
    _shell?.close();
    _client?.close();
    _controller.close();
  }
}

class SshClientEvent {
  final String status;
  final String text;
  SshClientEvent({required this.status, required this.text});
}
