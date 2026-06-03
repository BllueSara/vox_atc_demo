import 'dart:io';

import 'package:flutter/material.dart';

import 'services/audio_capture.dart';
import 'services/audio_devices_service.dart';
import 'services/audio_lifecycle.dart';
import 'services/audio_settings_service.dart';
import 'services/ptt_handler.dart';
import 'services/speech_engine.dart';

/// AVFoundation default audio input (first audio device, no video).
const _macDefaultMic = ':0';

final ValueNotifier<String> pttStatus = ValueNotifier<String>('Ready');
final ValueNotifier<String> transcript = ValueNotifier<String>('');
final ValueNotifier<bool> isTranscribing = ValueNotifier<bool>(false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initVoiceServices();
  runApp(const VoxAtcDemoApp());
}

Future<void> _initVoiceServices() async {
  var settings = await AudioSettingsService().load();

  if (Platform.isMacOS) {
    settings = settings.copyWith(micName: _macDefaultMic);
  } else if (Platform.isWindows && settings.micName.trim().isEmpty) {
    final mics = await AudioDevicesService().listWindowsMics();
    if (mics.isNotEmpty) {
      settings = settings.copyWith(micName: mics.first);
      debugPrint('AudioCapture: using default Windows mic "${mics.first}"');
    }
  }

  await PttHandler.instance.init(settings);
  await AudioCapture.instance.init(settings);
  await SpeechEngine.instance.start();

  PttHandler.instance.onPTTStart = _onPttStart;
  PttHandler.instance.onPTTEnd = _onPttEnd;
}

void _onPttStart() {
  // ignore: avoid_print
  print('PTT pressed');
  transcript.value = '';
  pttStatus.value = 'Recording...';
  AudioCapture.instance.start();
}

void _onPttEnd() {
  // ignore: avoid_print
  print('PTT released');
  AudioCapture.instance.stop().then(_onRecordingSaved);
}

Future<void> _onRecordingSaved(String path) async {
  if (path.isEmpty) {
    pttStatus.value = 'Ready';
    return;
  }

  // ignore: avoid_print
  print('Audio saved at: $path');
  pttStatus.value = 'Saved at: $path';

  isTranscribing.value = true;
  transcript.value = '';

  final text = await SpeechEngine.instance.transcribe(path);

  isTranscribing.value = false;
  if (await deleteWavFile(path)) {
    // ignore: avoid_print
    print('Audio file deleted: $path');
  }

  if (text.isNotEmpty) {
    // ignore: avoid_print
    print('Transcribed: $text');
    transcript.value = text;
    pttStatus.value = 'Transcription complete';
  } else {
    transcript.value = '(no transcription)';
    pttStatus.value = 'Transcription failed';
  }
}

class VoxAtcDemoApp extends StatefulWidget {
  const VoxAtcDemoApp({super.key});

  @override
  State<VoxAtcDemoApp> createState() => _VoxAtcDemoAppState();
}

class _VoxAtcDemoAppState extends State<VoxAtcDemoApp> {
  @override
  void dispose() {
    PttHandler.instance.dispose();
    AudioCapture.instance.dispose();
    SpeechEngine.instance.dispose();
    pttStatus.dispose();
    transcript.dispose();
    isTranscribing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoxATC Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const PttTestScreen(),
    );
  }
}

class PttTestScreen extends StatefulWidget {
  const PttTestScreen({super.key});

  @override
  State<PttTestScreen> createState() => _PttTestScreenState();
}

class _PttTestScreenState extends State<PttTestScreen> {
  String _httKeyLabel = 'Space';

  @override
  void initState() {
    super.initState();
    _loadKeyLabel();
  }

  Future<void> _loadKeyLabel() async {
    final settings = await AudioSettingsService().load();
    if (!mounted) return;
    setState(() => _httKeyLabel = settings.httKeyLabel);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VoxATC PTT Test')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: pttStatus,
              builder: (context, status, _) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Status',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          status,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<bool>(
              valueListenable: isTranscribing,
              builder: (context, loading, _) {
                if (!loading) return const SizedBox.shrink();
                return const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Transcribing...'),
                    ],
                  ),
                );
              },
            ),
            ValueListenableBuilder<String>(
              valueListenable: transcript,
              builder: (context, text, _) {
                if (text.isEmpty) return const SizedBox.shrink();
                return Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Transcript',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          text,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const Spacer(),
            Listener(
              onPointerDown: (_) => _onPttStart(),
              onPointerUp: (_) => _onPttEnd(),
              onPointerCancel: (_) => _onPttEnd(),
              child: SizedBox(
                height: 72,
                child: FilledButton(
                  onPressed: () {},
                  child: const Text(
                    'Hold to Talk',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              Platform.isMacOS
                  ? 'Or hold $_httKeyLabel while this window is focused.'
                  : 'Or hold $_httKeyLabel (global).',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (Platform.isMacOS) ...[
              const SizedBox(height: 8),
              Text(
                'Mic: $_macDefaultMic (avfoundation default)',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
