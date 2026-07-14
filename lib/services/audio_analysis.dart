import 'dart:math';
import 'dart:typed_data';

import 'audio_filter.dart';
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

  static const int _thumbnailSamples = 14;
  static const int _overviewSamples = 60;
  static const int _fftSize = 2048;
  static const int _pitchSize = 1024;

  /// 分析 WAV 文件。返回 null 表示录音无效（太短或静音）
  static Future<AudioAnalysisResult?> analyze(String wavFilePath) async {
    WavData wav;
    try {
      wav = await WavReader.read(wavFilePath);
    } catch (e) {
      // 文件格式不支持（非 WAV / 损坏）
      return null;
    }

    var samples = wav.samples;
    final sampleRate = wav.sampleRate;
    var duration = wav.duration;

    // 0. 整体 RMS 检测 — 太短或整体静音直接拒绝
    if (samples.length < sampleRate * 0.3) return null; // < 0.3 秒

    // 限制最大分析长度 — 超过 5 分钟的音频只取前 5 分钟，避免分析卡死
    final maxSamples = sampleRate * 300; // 5 分钟
    if (samples.length > maxSamples) {
      samples = Float64List.sublistView(samples, 0, maxSamples);
      duration = Duration(milliseconds: (maxSamples / sampleRate * 1000).round());
    }

    final overallRms = _rms(samples);
    if (overallRms < 0.005) return null; // 整体静音

    // 0.5 杂音过滤 — 高通(80Hz) + 低通(8kHz) + 软降噪门
    samples = AudioFilter.process(samples, sampleRate);

    // 1. 提取波形缩略图（用过滤后的数据，更干净）
    final waveform = _extractWaveform(samples, _thumbnailSamples);
    final overviewWaveform = _extractWaveform(samples, _overviewSamples);

    // 2. 共鸣分析 — 以 FFT 窗口大小为步长，精度最大化（无缝紧挨 = 连续色带）
    final maxSegByData = samples.length ~/ _fftSize;
    if (maxSegByData < 1) {
      return _fallbackResult(duration, 1, 1);
    }
    const maxSegCount = 800;
    final segCount =
        maxSegByData > maxSegCount ? maxSegCount : maxSegByData;
    final segLen = samples.length ~/ segCount;

    final detector = PitchDetector(sampleRate: sampleRate);
    final resonanceStack = <List<double>>[];

    for (var i = 0; i < segCount; i++) {
      final start = i * segLen;
      final end = (start + segLen).clamp(0, samples.length);
      final curLen = end - start;

      if (curLen < _fftSize) {
        resonanceStack.add([0, 0, 0, 0]);
        continue;
      }

      final segment = Float64List.sublistView(samples, start, end);

      // 分段 RMS 预检 — 静音段直接填零
      if (_rms(segment) < 0.01) {
        resonanceStack.add([0, 0, 0, 0]);
        continue;
      }

      // 共鸣分析 — 取段中间 _fftSize 样本做 FFT
      final fftStart = (curLen - _fftSize) ~/ 2;
      final fftFrame =
          Float64List.sublistView(segment, fftStart, fftStart + _fftSize);
      final mag = FFT.magnitudeSpectrum(fftFrame);
      resonanceStack.add(_calcResonance(mag, sampleRate));
    }

    // 3. 音高曲线 — 以检测窗口大小为步长，精度最大化（极密采样 → 极平滑曲线）
    final maxPitchByData = samples.length ~/ _pitchSize;
    const maxPitchPoints = 1500;
    final pitchCount = (maxPitchByData > maxPitchPoints
            ? maxPitchPoints
            : maxPitchByData)
        .clamp(1, maxPitchPoints);
    final pitchStep = samples.length ~/ pitchCount;
    final pitchValues = <double>[];
    for (var i = 0; i < pitchCount; i++) {
      final center = i * pitchStep + pitchStep ~/ 2;
      final ps = center - _pitchSize ~/ 2;
      if (ps < 0 || ps + _pitchSize > samples.length) {
        pitchValues.add(-1.0);
        continue;
      }
      final frame = Float64List.sublistView(samples, ps, ps + _pitchSize);
      if (_rms(frame) < 0.01) {
        pitchValues.add(-1.0);
        continue;
      }
      final freq = detector.detect(frame);
      // 存储 MIDI 值（-1 = 静音/检测失败），不归一化，保留原音音高
      pitchValues.add(
          freq != null ? PitchDetector.freqToMidi(freq) : -1.0);
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
  static AudioAnalysisResult _fallbackResult(
      Duration duration, int segCount, int pitchCount) {
    return AudioAnalysisResult(
      waveform: List.filled(_thumbnailSamples, 0.0),
      overviewWaveform: List.filled(_overviewSamples, 0.0),
      resonanceStack:
          List.generate(segCount, (_) => [0.0, 0.0, 0.0, 0.0]),
      pitch: List.filled(pitchCount, -1.0),
      duration: duration,
    );
  }
}
