// Ses kaydı ve çalma.

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';

class AudioService {
  AudioService._();
  static final instance = AudioService._();

  final _rec = AudioRecorder();
  final _player = AudioPlayer();
  String? playing;

  String get extension => Platform.isWindows ? 'wav' : 'm4a';

  Future<bool> start(String path) async {
    if (!await _rec.hasPermission()) return false;
    await _rec.start(RecordConfig(encoder: Platform.isWindows ? AudioEncoder.wav : AudioEncoder.aacLc), path: path);
    return true;
  }

  Future<String?> stop() => _rec.stop();

  Future<void> cancel() => _rec.cancel();

  Future<void> toggle(String assetId, String path) async {
    if (playing == assetId) {
      await _player.stop();
      playing = null;
      return;
    }
    await _player.stop();
    playing = assetId;
    await _player.play(DeviceFileSource(path));
    _player.onPlayerComplete.first.then((_) {
      if (playing == assetId) playing = null;
    });
  }
}
