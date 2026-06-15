import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ssh_client_service.dart';

/// SSH Client Screen — form koneksi + terminal output
class SshClientScreen extends StatefulWidget {
  const SshClientScreen({super.key});

  @override
  State<SshClientScreen> createState() => _SshClientScreenState();
}

class _SshClientScreenState extends State<SshClientScreen> {
  final _hostC = TextEditingController(text: '');
  final _portC = TextEditingController(text: '22');
  final _userC = TextEditingController(text: 'root');
  final _passC = TextEditingController(text: '');
  final _cmdC = TextEditingController();
  final _scrollC = ScrollController();
  final _focusCmd = FocusNode();

  final _service = SshClientService();
  bool _connecting = false;
  bool _connected = false;
  String _output = '';
  List<String> _history = [];
  int _historyIdx = -1;

  @override
  void initState() {
    super.initState();
    _service.events.listen(_onEvent);
    _focusCmd.onKeyEvent = (node, event) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() {
            if (_history.isNotEmpty) {
              _historyIdx = (_historyIdx + 1).clamp(0, _history.length - 1);
              _cmdC.text = _history[_historyIdx];
            }
          });
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          setState(() {
            if (_historyIdx > 0) {
              _historyIdx--;
              _cmdC.text = _history[_historyIdx];
            } else {
              _historyIdx = -1;
              _cmdC.clear();
            }
          });
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _service.dispose();
    _hostC.dispose();
    _portC.dispose();
    _userC.dispose();
    _passC.dispose();
    _cmdC.dispose();
    _scrollC.dispose();
    _focusCmd.dispose();
    super.dispose();
  }

  void _onEvent(SshClientEvent e) {
    if (!mounted) return;
    setState(() {
      _output += e.text;
      if (e.status == 'connected') {
        _connecting = false;
        _connected = true;
      } else if (e.status == 'error' || e.status == 'disconnected') {
        _connecting = false;
        _connected = false;
      } else if (e.status == 'connecting' || e.status == 'authenticating' || e.status == 'starting_shell') {
        _connecting = true;
      }
    });
    // Auto-scroll ke bawah
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollC.hasClients) {
        _scrollC.animateTo(_scrollC.position.maxScrollExtent, duration: 200.milliseconds, curve: Curves.easeOut);
      }
    });
  }

  Future<void> _connect() async {
    final host = _hostC.text.trim();
    final port = int.tryParse(_portC.text.trim()) ?? 22;
    final user = _userC.text.trim();
    final pass = _passC.text;

    if (host.isEmpty || user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi host, username, dan password!')),
      );
      return;
    }

    setState(() {
      _connecting = true;
      _connected = false;
      _output = '';
    });

    await _service.connect(
      host: host,
      port: port,
      username: user,
      password: pass,
    );
  }

  void _sendCommand() {
    final cmd = _cmdC.text;
    if (cmd.isEmpty) return;
    _history.insert(0, cmd);
    if (_history.length > 50) _history.removeLast();
    _historyIdx = -1;
    _service.sendCommand('$cmd\n');
    _cmdC.clear();
    _focusCmd.requestFocus();
  }

  void _disconnect() async {
    await _service.disconnect();
    setState(() => _connected = false);
  }

  void _copyOutput() {
    Clipboard.setData(ClipboardData(text: _output));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Output copied!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH Client'),
        actions: [
          if (_connected)
            IconButton(
              icon: const Icon(Icons.link_off, color: Colors.redAccent),
              tooltip: 'Disconnect',
              onPressed: _disconnect,
            ),
        ],
      ),
      body: _connected ? _buildTerminal(theme) : _buildForm(theme),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.computer, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text('SSH ke VPS', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Masukkan kredensial VPS kamu', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),

          // Host
          TextField(
            controller: _hostC,
            decoration: const InputDecoration(
              labelText: 'Host / IP VPS',
              hintText: 'contoh: 192.168.1.100',
              prefixIcon: Icon(Icons.dns),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          // Port + User
          Row(
            children: [
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _portC,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '22',
                    prefixIcon: Icon(Icons.numbers),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _userC,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'root',
                    prefixIcon: Icon(Icons.person),
                  ),
                  textInputAction: TextInputAction.next,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Password
          TextField(
            controller: _passC,
            decoration: const InputDecoration(
              labelText: 'Password',
              hintText: 'Masukkan password VPS',
              prefixIcon: Icon(Icons.lock),
            ),
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 24),

          // Tombol Connect
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _connecting ? null : _connect,
              icon: _connecting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.terminal),
              label: Text(_connecting ? 'Connecting...' : 'Connect'),
            ),
          ),

          // Output log
          if (_output.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _output,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF00FF00)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTerminal(ThemeData theme) {
    return Column(
      children: [
        // Terminal output
        Expanded(
          child: Container(
            width: double.infinity,
            color: Colors.black,
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              controller: _scrollC,
              child: SelectableText(
                _output,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF00FF00)),
              ),
            ),
          ),
        ),

        // Toolbar
        Container(
          color: const Color(0xFF1A1A1A),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              _toolBtn('Ctrl+C', () => _service.sendCtrlC()),
              const SizedBox(width: 4),
              _toolBtn('Copy', _copyOutput),
              const Spacer(),
              if (_output.contains('$ '))
                Text('● Connected', style: TextStyle(fontSize: 11, color: Colors.green[400])),
            ],
          ),
        ),

        // Input command
        Container(
          color: const Color(0xFF0D0D0D),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Text('\$ ', style: TextStyle(fontFamily: 'monospace', color: Colors.green, fontSize: 14)),
              Expanded(
                child: TextField(
                  controller: _cmdC,
                  focusNode: _focusCmd,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14, color: Colors.white),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    border: InputBorder.none,
                    hintText: 'ketik command...',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  autofocus: true,
                  onSubmitted: (_) => _sendCommand(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, size: 18, color: Colors.green),
                onPressed: _sendCommand,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolBtn(String label, VoidCallback onTap) {
    return Material(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ),
      ),
    );
  }
}
