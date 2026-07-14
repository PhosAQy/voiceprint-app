import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 实时耳返服务 — 录制短段音频并立即播放，实现近实时监听
///
/// 原理：循环录制 400ms 音频片段 → 立即播放 → 重复
/// 延迟约 400-600ms，足以满足"听到自己声音"的监听需求
class EarMonitorService {
  static const _segmentMs = 400;
  static const _sampleRate = 16000;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _running = false;
  String? _tempDir;
  int _counter = 0;

  bool get isRunning => _running;

  /// 开始监听
  Future<bool> start() async {
    if (_running) return true;

    // 检查权限
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) return false;

    final docsDir = await getTemporaryDirectory();
    _tempDir = docsDir.path;

    _running = true;
    _monitorLoop();
    return true;
  }

  /// 停止监听
  Future<void> stop() async {
    _running = false;
    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
    _cleanupTempFiles();
  }

  /// 监听循环
  Future<void> _monitorLoop() async {
    while (_running) {
      try {
        final path = p.join(_tempDir!, 'ear_monitor_$_counter.wav');
        _counter++;

        // 开始录制
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: _sampleRate,
            numChannels: 1,
            autoGain: true,
            echoCancel: false,
            noiseSuppress: false,
          ),
          path: path,
        );

        // 等待 _segmentMs
        await Future.delayed(const Duration(milliseconds: _segmentMs));

        // 停止录制
        await _recorder.stop();

        if (!_running) break;

        // 播放刚录制的片段
        await _player.play(DeviceFileSource(path));

        // 等待播放完成（或超时）
        await Future.delayed(const Duration(milliseconds: _segmentMs));
        await _player.stop();
      } catch (e) {
        // 出错时短暂等待后重试
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  void _cleanupTempFiles() {
    if (_tempDir == null) return;
    try {
      final dir = Directory(_tempDir!);
      final files = dir.listSync();
      for (final f in files) {
        final name = p.basename(f.path);
        if (name.startsWith('ear_monitor_') && name.endsWith('.wav')) {
          f.deleteSync();
        }
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
    _player.dispose();
  }
}
