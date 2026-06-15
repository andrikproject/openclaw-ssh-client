import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart' as ssh;

/// SSH Client Service — koneksi ke VPS via SSH (dartssh2 v2)
class SshClientService {
  ssh.SSHClient? _client;
  ssh.SSHShell? _shell;
  StreamSubscription? _outputSub;
  StreamSubscription? _stderrSub;
  bool _disposed = false;

  bool get isConnected => _client != null && _shell != null;

  final StreamController<SshClientEvent> _controller =
      StreamController<SshClientEvent>.broadcast();
  Stream<SshClientEvent> get events => _controller.stream;

  /// Connect ke VPS
  Future<bool> connect({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    try {
      _controller.add(SshClientEvent(
          status: 'connecting', text: 'Connecting to $host:$port...\n'));

      // dartssh2 v2: buat TCP socket dulu
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 15));

      _controller.add(SshClientEvent(
          status: 'authenticating', text: 'Authenticating...\n'));

      // Bungkus socket dengan SSHClient, pakai password auth
      _client = ssh.SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );

      // Tunggu autentikasi selesai
      await _client!.authenticated.timeout(const Duration(seconds: 30));
      _controller.add(SshClientEvent(
          status: 'starting_shell', text: 'Opening shell...\n'));

      // Buka shell interaktif
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

      // Juga baca stderr
      _stderrSub = _shell!.stderr.listen(
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
              text: 'SSH stderr: $err\n',
            ));
          }
        },
      );

      _controller.add(
          SshClientEvent(status: 'connected', text: '✓ Connected to $host\n'));
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
    await _stderrSub?.cancel();
    await _shell?.close();
    _shell = null;
    _client = null;
    _controller
        .add(SshClientEvent(status: 'disconnected', text: 'Disconnected.\n'));
  }

  void dispose() {
    _disposed = true;
    _outputSub?.cancel();
    _stderrSub?.cancel();
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
