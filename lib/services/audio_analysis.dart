import 'dart:math';
import 'dart:typed_data';

import 'fft.dart';
import 'pitch_detector.dart';
import 'wav_reader.dart';

/// 音频分析结果
class AudioAnalysisResult {
  final List<double> waveform; // 14 个采样点，用于缩略图
  final List<double> overviewWaveform; // 60 个采样点，用于详情页概览
  final List<List<double>> resonanceStack; // 20 段，每段 [胸腔, 鼻腔, 头腔, 大白嗓]
  final List<double> pitch; // 20 个音高点，归一化 0.0-1.0 (C3-C5)
  final Duration duration;

  const AudioAnalysisResult({
    required this.waveform,
    required this.overviewWaveform,
    required this.resonanceStack,
    required this.pitch,
    required this.duration,
  });
}

/// 音频分析服务 — 从 WAV 文件提取波形、音高曲线、共鸣比例
class AudioAnalysisService {
  AudioAnalysisService._();

  static const int _segmentCount = 20;
  static const int _thumbnailSamples = 14;
  static const int _overviewSamples = 60;
  static const int _fftSize = 2048;
  static const int _pitchSize = 1024;

  /// 分析 WAV 文件。返回 null 表示录音无效（太短或静音）
  static Future<AudioAnalysisResult?> analyze(String wavFilePath) async {
    final wav = await WavReader.read(wavFilePath);
    final samples = wav.samples;
    final sampleRate = wav.sampleRate;
    final duration = wav.duration;

    // 0. 整体 RMS 检测 — 太短或整体静音直接拒绝
    if (samples.length < sampleRate * 0.3) return null; // < 0.3 秒
    final overallRms = _rms(samples);
    if (overallRms < 0.005) return null; // 整体静音

    // 1. 提取波形缩略图
    final waveform = _extractWaveform(samples, _thumbnailSamples);
    final overviewWaveform = _extractWaveform(samples, _overviewSamples);

    // 2. 分段分析
    final segmentLength = (samples.length / _segmentCount).floor();
    if (segmentLength < _fftSize) {
      return _fallbackResult(duration);
    }

    final detector = PitchDetector(sampleRate: sampleRate);
    final resonanceStack = <List<double>>[];
    final pitchValues = <double>[];

    for (var i = 0; i < _segmentCount; i++) {
      final start = i * segmentLength;
      final end =
          (start + segmentLength).clamp(0, samples.length);

      // 提取本段数据
      final segLen = end - start;
      if (segLen < _fftSize) {
        resonanceStack.add([0, 0, 0, 0]);
        pitchValues.add(0.0);
        continue;
      }

      final segment = Float64List.sublistView(samples, start, end);

      // 分段 RMS 预检 — 静音段直接填零，不进行无意义分析
      final segRms = _rms(segment);
      if (segRms < 0.01) {
        resonanceStack.add([0, 0, 0, 0]);
        pitchValues.add(0.0);
        continue;
      }

      // 音高检测 — 取段中间的 _pitchSize 个样本
      final pitchStart = (segLen - _pitchSize) ~/ 2;
      final pitchFrame =
          Float64List.sublistView(segment, pitchStart, pitchStart + _pitchSize);
      final freq = detector.detect(pitchFrame);
      if (freq != null) {
        pitchValues.add(PitchDetector.freqToNormalized(freq));
      } else {
        // 尝试多个位置取平均
        final pitches = <double>[];
        for (var p = 0; p < 3; p++) {
          final ps = (segLen / 4 * (p + 1)).floor() - _pitchSize ~/ 2;
          if (ps >= 0 && ps + _pitchSize <= segLen) {
            final f = detector.detect(
                Float64List.sublistView(segment, ps, ps + _pitchSize));
            if (f != null) pitches.add(f);
          }
        }
        if (pitches.isNotEmpty) {
          final avgFreq =
              pitches.reduce((a, b) => a + b) / pitches.length;
          pitchValues.add(PitchDetector.freqToNormalized(avgFreq));
        } else {
          pitchValues.add(0.0); // 检测不到音高，归零（不再用 0.5/C4）
        }
      }

      // 共鸣分析 — 取段中间的 _fftSize 个样本做 FFT
      final fftStart = (segLen - _fftSize) ~/ 2;
      final fftFrame =
          Float64List.sublistView(segment, fftStart, fftStart + _fftSize);
      final mag = FFT.magnitudeSpectrum(fftFrame);
      resonanceStack.add(_calcResonance(mag, sampleRate));
    }

    return AudioAnalysisResult(
      waveform: waveform,
      overviewWaveform: overviewWaveform,
      resonanceStack: resonanceStack,
      pitch: pitchValues,
      duration: duration,
    );
  }

  /// 计算 RMS（均方根）能量
  static double _rms(Float64List samples) {
    if (samples.isEmpty) return 0;
    var sumSq = 0.0;
    for (var i = 0; i < samples.length; i++) {
      sumSq += samples[i] * samples[i];
    }
    return sqrt(sumSq / samples.length);
  }

  /// 从 PCM 采样提取波形（取绝对值最大值归一化）
  static List<double> _extractWaveform(Float64List samples, int count) {
    if (samples.isEmpty) return List.filled(count, 0.1);

    final segmentLength = (samples.length / count).floor();
    if (segmentLength == 0) return List.filled(count, 0.1);

    final result = List<double>.filled(count, 0.0);
    var maxVal = 0.001;

    for (var i = 0; i < count; i++) {
      final start = i * segmentLength;
      final end = (start + segmentLength).clamp(0, samples.length);
      var peak = 0.0;
      for (var j = start; j < end; j++) {
        final abs = samples[j].abs();
        if (abs > peak) peak = abs;
      }
      // 应用一些非线性放大让小信号也可见
      final v = sqrt(peak);
      result[i] = v;
      if (v > maxVal) maxVal = v;
    }

    // 归一化到 0.12 ~ 1.0 范围
    for (var i = 0; i < count; i++) {
      result[i] = (result[i] / maxVal).clamp(0.12, 1.0);
    }
    return result;
  }

  /// 基于 FFT 频段能量计算共鸣比例
  ///
  /// 频段划分（近似，基于声学共鸣特性）：
  /// - 胸腔共鸣: 80–350 Hz (低频，基频和低次谐波)
  /// - 鼻腔共鸣: 350–1500 Hz (中低频)
  /// - 头腔共鸣: 1500–4000 Hz (中高频，"金属感"和"穿透力")
  /// - 大白嗓: 其余 (极高/极低频，无聚焦共鸣)
  static List<double> _calcResonance(
      List<double> magnitude, int sampleRate) {
    final chest = FFT.bandEnergy(magnitude, sampleRate, 80, 350);
    final nasal = FFT.bandEnergy(magnitude, sampleRate, 350, 1500);
    final head = FFT.bandEnergy(magnitude, sampleRate, 1500, 4000);
    // 大白嗓: 总能量减去以上三段
    final total = FFT.bandEnergy(magnitude, sampleRate, 60, 8000);
    final raw = (total - chest - nasal - head).abs();

    final sum = chest + nasal + head + raw;
    if (sum < 1e-10) return [0.4, 0.2, 0.2, 0.2];

    return [
      chest / sum,
      nasal / sum,
      head / sum,
      raw / sum,
    ];
  }

  /// 音频太短时的 fallback — 全零
  static AudioAnalysisResult _fallbackResult(Duration duration) {
    return AudioAnalysisResult(
      waveform: List.filled(_thumbnailSamples, 0.0),
      overviewWaveform: List.filled(_overviewSamples, 0.0),
      resonanceStack: List.generate(
          _segmentCount, (_) => [0.0, 0.0, 0.0, 0.0]),
      pitch: List.filled(_segmentCount, 0.0),
      duration: duration,
    );
  }
}
