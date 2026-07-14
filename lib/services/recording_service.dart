import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../models/recording.dart';
import 'audio_analysis.dart';
import 'database_service.dart';

/// 录音服务 — 管理录音生命周期 + 分析 + 入库
class RecordingService {
  static final RecordingService _instance = RecordingService._internal();
  factory RecordingService() => _instance;
  RecordingService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  final DatabaseService _db = DatabaseService();

  bool _isRecording = false;
  String? _currentPath;

  bool get isRecording => _isRecording;

  /// 检查并请求麦克风权限
  Future<bool> ensurePermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  /// 开始录音
  Future<bool> start() async {
    if (_isRecording) return false;
    if (!await ensurePermission()) return false;

    final dir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory(p.join(dir.path, 'recordings'));
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }

    final now = DateTime.now();
    final fileName =
        'rec_${now.millisecondsSinceEpoch}.wav';
    _currentPath = p.join(recordingsDir.path, fileName);

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: _currentPath!,
    );
    _isRecording = true;
    return true;
  }

  /// 停止录音并分析入库，返回新建的 Recording
  Future<Recording?> stop() async {
    if (!_isRecording) return null;
    final path = await _recorder.stop();
    _isRecording = false;
    _currentPath = null;

    if (path == null) return null;

    // 分析音频
    final analysis = await AudioAnalysisService.analyze(path);

    final now = DateTime.now();
    final dateLabel =
        '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final recording = Recording(
      filePath: path,
      dateTimeLabel: dateLabel,
      duration: analysis.duration,
      waveform: analysis.waveform,
      overviewWaveform: analysis.overviewWaveform,
      resonanceStack: analysis.resonanceStack,
      pitch: analysis.pitch,
      createdAt: now.millisecondsSinceEpoch,
    );

    final id = await _db.insert(recording);
    return Recording(
      id: id,
      filePath: recording.filePath,
      dateTimeLabel: recording.dateTimeLabel,
      duration: recording.duration,
      waveform: recording.waveform,
      overviewWaveform: recording.overviewWaveform,
      resonanceStack: recording.resonanceStack,
      pitch: recording.pitch,
      createdAt: recording.createdAt,
    );
  }

  /// 获取所有录音
  Future<List<Recording>> getAllRecordings() => _db.getAll();

  /// 删除录音
  Future<void> deleteRecording(int id) => _db.delete(id);

  void dispose() {
    _recorder.dispose();
  }
}
