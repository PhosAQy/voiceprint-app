import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../models/recording.dart';
import 'audio_analysis.dart';
import 'audio_decoder_service.dart';
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

    // 分析音频（返回 null 表示录音无效：太短或静音）
    final analysis = await AudioAnalysisService.analyze(path);
    if (analysis == null) return null;

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

  /// 导入本地音频文件 — 复制到 App 目录 + 分析 + 入库
  /// 返回 null 表示导入失败或文件无效
  Future<Recording?> importFile(String srcPath) async {
    String? destPath;
    try {
      final srcFile = File(srcPath);
      if (!await srcFile.exists()) return null;

      // 复制到 App recordings 目录
      final dir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory(p.join(dir.path, 'recordings'));
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      final now = DateTime.now();
      final fileName = 'rec_${now.millisecondsSinceEpoch}.wav';
      destPath = p.join(recordingsDir.path, fileName);

      // 判断源文件格式 — WAV 直接复制，其他格式通过原生 MediaCodec 解码
      final isWav = srcPath.toLowerCase().endsWith('.wav');
      if (isWav) {
        await srcFile.copy(destPath);
      } else {
        // M4A/MP3/AAC 等需要先解码为 WAV
        final decoded = await AudioDecoderService.decodeToWav(srcPath, destPath);
        if (!decoded) return null;
      }

      // 分析音频（内部已捕获格式异常 + 限制 5 分钟长度，不会卡死）
      final analysis = await AudioAnalysisService.analyze(destPath);
      if (analysis == null) {
        // 分析失败（非 WAV / 损坏 / 静音 / 太短），删除已复制的文件
        try {
          await File(destPath).delete();
        } catch (_) {}
        return null;
      }

      final dateLabel =
          '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final recording = Recording(
        filePath: destPath,
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
    } catch (e) {
      // 任何未预期异常 — 清理文件并返回 null，绝不卡死
      if (destPath != null) {
        try {
          await File(destPath).delete();
        } catch (_) {}
      }
      return null;
    }
  }

  /// 删除录音
  Future<void> deleteRecording(int id) => _db.delete(id);

  void dispose() {
    _recorder.dispose();
  }
}
