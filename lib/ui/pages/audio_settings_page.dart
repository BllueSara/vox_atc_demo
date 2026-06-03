// lib/ui/pages/audio_settings_page.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/audio_settings_service.dart';
import '../../services/audio_devices_service.dart';

class AudioSettingsPage extends StatefulWidget {
  static const routeName = '/audio-settings';

  final bool asDialog;
  const AudioSettingsPage({super.key, this.asDialog = false});

  @override
  State<AudioSettingsPage> createState() => _AudioSettingsPageState();
}

class _AudioSettingsPageState extends State<AudioSettingsPage> {
  final _svc = AudioSettingsService();

  bool _loading = true;
  AudioSettings _settings = AudioSettings.defaults();

  List<String> _mics = const [];
  final _devSvc = AudioDevicesService();

  Process? _meterProc;
  StreamSubscription<List<int>>? _meterSub;

  final List<int> _pcmBuffer = <int>[];
  double _level01 = 0.0;
  double _target01 = 0.0;
  bool _meterRunning = false;
  Timer? _uiMeterTimer;

  static const int _sampleRate = 16000;
  static const int _frameMs = 20;
  static final int _frameBytes = (_sampleRate * _frameMs ~/ 1000) * 2;

  // --- HTT key capture ---
  final FocusNode _keyFocus = FocusNode();
  bool _capturingKey = false;

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    await _load();
    await _loadMics();
  }

  Future<void> _loadMics() async {
    try {
      final list = await _devSvc.listWindowsMics();
      if (!mounted) return;
      setState(() => _mics = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _mics = const []);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to list microphones: $e')),
      );
    }
  }

  Future<void> _startMeter() async {
    final mic = _settings.micName.trim();
    if (mic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a microphone first')),
      );
      return;
    }

    await _stopMeter();

    final args = [
      '-hide_banner',
      '-loglevel',
      'error',
      '-f',
      'dshow',
      '-i',
      'audio=$mic',
      '-ac',
      '1',
      '-ar',
      '$_sampleRate',
      '-f',
      's16le',
      'pipe:1',
    ];

    try {
      final p = await Process.start('ffmpeg', args, runInShell: true);
      _meterProc = p;
      _meterRunning = true;
      _pcmBuffer.clear();
      _target01 = 0.0;

      _meterSub = p.stdout.listen((bytes) {
        if (!_meterRunning) return;
        _pcmBuffer.addAll(bytes);

        while (_pcmBuffer.length >= _frameBytes) {
          final frame = _pcmBuffer.sublist(0, _frameBytes);
          _pcmBuffer.removeRange(0, _frameBytes);

          int peakAbs = 0;
          for (int i = 0; i < frame.length; i += 2) {
            final lo = frame[i];
            final hi = frame[i + 1];
            int v = (hi << 8) | lo;
            if ((v & 0x8000) != 0) v -= 0x10000;
            final av = v.abs();
            if (av > peakAbs) peakAbs = av;
          }

          final peak01 = (peakAbs / 32768.0).clamp(0.0, 1.0);
          final gated = peak01 < 0.02 ? 0.0 : peak01;
          _target01 = gated;
        }
      });

      p.stderr.listen((_) {});
      _uiMeterTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (!mounted || !_meterRunning) return;

        final cur = _level01;
        final tgt = _target01;
        final double next =
            (tgt > cur) ? cur + (tgt - cur) * 0.55 : cur + (tgt - cur) * 0.12;

        setState(() => _level01 = next.clamp(0.0, 1.0));
      });

      if (mounted) setState(() {});
    } catch (e) {
      await _stopMeter();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mic test failed: $e')),
      );
    }
  }

  Future<void> _stopMeter() async {
    _meterRunning = false;

    _uiMeterTimer?.cancel();
    _uiMeterTimer = null;

    final sub = _meterSub;
    _meterSub = null;
    await sub?.cancel();

    final p = _meterProc;
    _meterProc = null;

    try {
      p?.kill(ProcessSignal.sigterm);
    } catch (_) {}

    _pcmBuffer.clear();
    _target01 = 0.0;

    if (mounted) setState(() => _level01 = 0.0);
  }

  @override
  void dispose() {
    _stopMeter();
    _keyFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await _svc.load();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final ok = _settings.micName.trim().isNotEmpty;
    final next = _settings.copyWith(setupComplete: ok);

    await _svc.save(next);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Audio settings saved' : 'Select a microphone'),
      ),
    );

    setState(() => _settings = next);

    if (widget.asDialog && ok) {
      Navigator.of(context).pop(true);
    }
  }

  void _beginCaptureKey() {
    setState(() => _capturingKey = true);
    // ensure focus so we get key events
    FocusScope.of(context).requestFocus(_keyFocus);
  }

  void _cancelCaptureKey() {
    setState(() => _capturingKey = false);
  }

  void _onKeyEvent(KeyEvent e) {
    if (!_capturingKey) return;
    if (e is! KeyDownEvent) return;

    final key = e.logicalKey;
    final id = key.keyId;
    String label = key.keyLabel.trim();
    if (label.isEmpty) {
      label = key.debugName ?? 'Key';
    }

    setState(() {
      _settings = _settings.copyWith(httKeyId: id, httKeyLabel: label);
      _capturingKey = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('HTT key set to: $label')),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Focus(
      focusNode: _keyFocus,
      onKeyEvent: (node, event) {
        _onKeyEvent(event);
        return KeyEventResult.handled;
      },
      child: ListView(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Audio Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              if (widget.asDialog)
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // --- Mic ---
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Microphone',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Refresh mic list',
                onPressed: _loadMics,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: (_settings.micName.isNotEmpty &&
                    _mics.contains(_settings.micName))
                ? _settings.micName
                : null,
            items: _mics
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) async {
              if (_meterRunning) await _stopMeter();
              setState(() => _settings = _settings.copyWith(micName: v ?? ''));
            },
            decoration: InputDecoration(
              hintText: _mics.isEmpty
                  ? 'No mics found (press refresh)'
                  : 'Select microphone',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: MicLevelMeter(level01: _level01)),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _meterRunning ? _stopMeter : _startMeter,
                icon: Icon(_meterRunning ? Icons.stop : Icons.play_arrow),
                label: Text(_meterRunning ? 'Stop Test' : 'Test Mic'),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // --- HTT Key ---
          const Text(
            'Hold-to-talk key (HTT)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _capturingKey
                        ? 'Press any key now...'
                        : 'Current: ${_settings.httKeyLabel}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _capturingKey ? Colors.orangeAccent : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (_capturingKey)
                  OutlinedButton(
                    onPressed: _cancelCaptureKey,
                    child: const Text('Cancel'),
                  )
                else
                  FilledButton(
                    onPressed: _beginCaptureKey,
                    child: const Text('Set Key'),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // --- Whisper profile ---
          const Text(
            'Whisper Profile',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<WhisperProfile>(
            value: _settings.profile,
            items: const [
              DropdownMenuItem(
                value: WhisperProfile.fast,
                child: Text('Fast (lowest latency)'),
              ),
              DropdownMenuItem(
                value: WhisperProfile.auto,
                child: Text('Auto (adaptive)'),
              ),
              DropdownMenuItem(
                value: WhisperProfile.accurate,
                child: Text('Accurate (still ≤1.5s)'),
              ),
            ],
            onChanged: (v) async {
              if (v == null) return;
              if (_meterRunning) await _stopMeter();
              if (!mounted) return;
              setState(() => _settings = _settings.copyWith(profile: v));
            },
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable rescue pass (when confidence is low)'),
            value: _settings.enableRescuePass,
            onChanged: (v) {
              setState(
                  () => _settings = _settings.copyWith(enableRescuePass: v));
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _settings.setupComplete
                ? 'Setup complete ✅'
                : 'Setup not complete (select a microphone and Save).',
            style: TextStyle(
              color: _settings.setupComplete
                  ? Colors.greenAccent
                  : Colors.orangeAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16), child: _buildContent(context));

    if (widget.asDialog) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('Audio Settings')),
      body: content,
    );
  }
}

class MicLevelMeter extends StatelessWidget {
  final double level01;
  const MicLevelMeter({super.key, required this.level01});

  @override
  Widget build(BuildContext context) {
    final v = level01.clamp(0.0, 1.0);
    Color c;
    String label;

    if (v < 0.25) {
      c = Colors.amber;
      label = 'Low';
    } else if (v < 0.70) {
      c = Colors.green;
      label = 'Normal';
    } else {
      c = Colors.red;
      label = 'High';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mic level: $label'),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 14,
            color:
                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.7),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: v,
                child: Container(color: c),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
