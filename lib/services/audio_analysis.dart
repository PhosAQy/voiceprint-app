import 'dart:math';
import 'dart:typed_data';

import 'audio_filter.dart';
import 'fft.dart';
import 'lpc.dart';
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

      // 共鸣分析 — 取段中间 _fftSize 样本做 FFT + LPC
      final fftStart = (curLen - _fftSize) ~/ 2;
      final fftFrame =
          Float64List.sublistView(segment, fftStart, fftStart + _fftSize);
      final mag = FFT.magnitudeSpectrum(fftFrame);
      resonanceStack.add(_calcResonance(fftFrame, mag, sampleRate));
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

  /// 基于共振峰（LPC）+ 频谱平坦度 + 歌唱家共振峰的科学共鸣分析
  ///
  /// 声学定义（有文献依据）：
  /// - **胸腔共鸣**：F1 较低（< 500Hz）且基频附近能量集中
  ///   - 声学依据：胸腔共鸣表现为低频共振，声道较长、F1 偏低
  ///   - 测量：F1 落在 200-500Hz 区间 + 低频能量比
  ///
  /// - **鼻腔共鸣**：鼻音化程度
  ///   - 声学依据：A1-P1 法（Chen 1997），鼻音化时 F1 处能量增强
  ///   - 测量：F1 处能量与基频能量的比值（近似 A1-P1）
  ///
  /// - **头腔共鸣**：歌唱家共振峰（Sundberg 1974）
  ///   - 声学依据：2-5kHz 频段出现明显共振峰，由喉咽部收窄产生
  ///   - 测量：2-5kHz 能量集中度（峰值/均值比）
  ///
  /// - **大白嗓**：频谱平坦度 + 缺乏共振峰塑形
  ///   - 声学依据：大白嗓缺乏声道塑形，频谱接近白噪（平坦）
  ///   - 测量：SFM × (1 - 歌唱家共振峰强度)
  static List<double> _calcResonance(
      Float64List timeSignal, List<double> magnitude, int sampleRate) {
    // ---- LPC 共振峰提取 ----
    // 加 Hann 窗（LPC 对窗敏感）
    final windowed = Float64List(timeSignal.length);
    final n = timeSignal.length;
    for (var i = 0; i < n; i++) {
      final w = 0.5 - 0.5 * cos(2 * pi * i / (n - 1));
      windowed[i] = timeSignal[i] * w;
    }

    // LPC 阶数：约为采样率/1000 + 2，保证能提取 F1-F4
    final lpcOrder = (sampleRate ~/ 1000) + 2;
    final lpcCoeffs = Lpc.compute(windowed, lpcOrder);
    final formants = Lpc.extractFormants(lpcCoeffs, sampleRate);

    // ---- 频谱平坦度 SFM (Spectral Flatness Measure) ----
    // SFM = exp(mean(log(mag))) / mean(mag)
    // SFM → 1：白噪（完全平坦）；SFM → 0：有强共振峰
    final sfm = _spectralFlatness(magnitude);

    // ---- 歌唱家共振峰强度（2-5kHz）----
    // 头腔共鸣：2-5kHz 频段峰值能量与全频段平均能量的比值
    final singerFormantStrength = _singerFormantStrength(magnitude, sampleRate);

    // ---- 四维共鸣比例计算 ----
    // 每个维度先算"原始强度"，再归一化为比例（和为 1）

    final totalEnergy =
        FFT.bandEnergy(magnitude, sampleRate, 60, 8000);

    // 1. 胸腔共鸣强度
    //    声学依据：胸声（chest voice）的本质是基频 + 前几个低次谐波
    //    能量集中。发胸声时基频 ~80-200Hz，前 3 谐波 ~240-600Hz
    //    全部落在低频区，低频能量占比高。
    //
    //    主要指标：低频能量集中度（80-600Hz 占总能量比例）
    //    辅助指标：F1 位置（F1 落在 150-600Hz 说明声道较长）
    final lowFreqEnergy =
        FFT.bandEnergy(magnitude, sampleRate, 80, 600);
    var chestStrength = 0.2; // 基础值，保证不为零
    if (totalEnergy > 1e-10) {
      final lowRatio = lowFreqEnergy / totalEnergy;
      // 大幅加权：发胸声时 lowRatio 0.4-0.6 → chestStrength 1.0-1.5
      chestStrength += lowRatio * 2.5;
    }
    if (formants.isNotEmpty) {
      final f1 = formants.first;
      if (f1.frequency >= 150 && f1.frequency <= 600) {
        // F1 在胸腔区，加权
        chestStrength += f1.strength * 0.4;
      }
    }

    // 2. 鼻腔共鸣强度（A1-P1 法）
    //    声学依据（Chen 1997）：鼻音化时 F1 处幅度 A1 明显高于
    //    基频幅度 P1。非鼻音时 A1 ≈ P1 或 A1 < P1。
    //
    //    测量：F1 处频谱幅度 A1，基频附近幅度 P1
    //    鼻音度 = max(0, (A1 - P1) / max(A1, P1))
    //    只有 F1 明显强于基频时才算鼻音（避免把胸声谐波误判为鼻腔）
    var nasalStrength = 0.15; // 基础值
    if (formants.isNotEmpty) {
      final f1Freq = formants.first.frequency;
      // 找基频附近的最大幅度（P1）：扫描 70-250Hz 找峰值
      final p1Bin = _findPeakBin(magnitude, sampleRate, 70, 250);
      // F1 处幅度（A1）：F1 频率附近的峰值
      final a1Bin = _findPeakBin(magnitude, sampleRate,
          f1Freq - 50, f1Freq + 50);
      if (p1Bin >= 0 && a1Bin >= 0) {
        final p1 = magnitude[p1Bin];
        final a1 = magnitude[a1Bin];
        if (p1 > 1e-10 && a1 > 1e-10) {
          // 鼻音度：A1 相对 P1 的超出程度
          final nasality = (a1 - p1) / (a1 > p1 ? a1 : p1);
          // 只有 A1 明显大于 P1（>20%）才算鼻音
          if (nasality > 0.2) {
            nasalStrength = nasality * 0.8;
          }
          // 否则鼻腔保持基础值（非鼻音）
        }
      }
    }

    // 3. 头腔共鸣强度 = 歌唱家共振峰强度
    //    - 2-5kHz 能量集中度（峰值/均值）
    var headStrength = singerFormantStrength;

    // 4. 大白嗓强度 = SFM × (1 - 歌唱家共振峰强度)
    //    - 频谱越平坦（SFM 大）+ 头腔越弱 → 大白嗓比例越高
    //    - 限制最大权重，避免过度压制其他维度
    var whiteStrength = sfm * (1.0 - singerFormantStrength) * 0.7;

    // 确保各值为正
    chestStrength = chestStrength.clamp(0.01, 10.0);
    nasalStrength = nasalStrength.clamp(0.01, 10.0);
    headStrength = headStrength.clamp(0.01, 10.0);
    whiteStrength = whiteStrength.clamp(0.01, 10.0);

    final sum = chestStrength + nasalStrength + headStrength + whiteStrength;
    if (sum < 1e-10) return [0.25, 0.25, 0.25, 0.25];

    return [
      chestStrength / sum,
      nasalStrength / sum,
      headStrength / sum,
      whiteStrength / sum,
    ];
  }

  /// 在指定频率范围内找到频谱幅度的峰值 bin
  /// 返回 bin 索引，找不到返回 -1
  static int _findPeakBin(List<double> magnitude, int sampleRate,
      double freqLow, double freqHigh) {
    final n = (magnitude.length - 1) * 2;
    final binLow = (freqLow / sampleRate * n).floor().clamp(0, magnitude.length - 1);
    final binHigh = (freqHigh / sampleRate * n).ceil().clamp(0, magnitude.length - 1);
    if (binHigh <= binLow) return -1;

    var peakBin = -1;
    var peakVal = -1.0;
    for (var i = binLow; i <= binHigh && i < magnitude.length; i++) {
      if (magnitude[i] > peakVal) {
        peakVal = magnitude[i];
        peakBin = i;
      }
    }
    return peakBin;
  }

  /// 计算频谱平坦度（Spectral Flatness Measure, SFM）
  ///
  /// SFM = exp(mean(log(mag))) / mean(mag)
  /// - SFM → 1：白噪声（频谱完全平坦，无共振峰）
  /// - SFM → 0：有强共振峰（能量集中在某些频率）
  static double _spectralFlatness(List<double> magnitude) {
    if (magnitude.isEmpty) return 0.5;

    // 只取有意义的频段（避开直流和极高频）
    final start = 1;
    final end = magnitude.length ~/ 2; // 取前半部分
    if (end - start < 2) return 0.5;

    var sumLog = 0.0;
    var sumLinear = 0.0;
    var count = 0;
    for (var i = start; i < end; i++) {
      final m = magnitude[i];
      if (m > 1e-10) {
        sumLog += log(m);
        sumLinear += m;
        count++;
      }
    }
    if (count == 0 || sumLinear <= 0) return 0.5;

    final geoMean = exp(sumLog / count);
    final arithMean = sumLinear / count;
    return (geoMean / arithMean).clamp(0.0, 1.0);
  }

  /// 计算歌唱家共振峰强度（2-5kHz 频段）
  ///
  /// 返回值 0-1：
  /// - 1：2-5kHz 有明显峰值（强头腔共鸣）
  /// - 0：2-5kHz 能量平坦（无头腔共鸣）
  ///
  /// 算法：2-5kHz 区间峰值能量 / 全频段平均能量，归一化
  static double _singerFormantStrength(
      List<double> magnitude, int sampleRate) {
    final n = (magnitude.length - 1) * 2;
    final binLow = (2000 / sampleRate * n).floor().clamp(0, magnitude.length - 1);
    final binHigh = (5000 / sampleRate * n).ceil().clamp(0, magnitude.length - 1);
    if (binHigh <= binLow) return 0.0;

    // 2-5kHz 区间的峰值和均值
    var peak = 0.0;
    var sumBand = 0.0;
    var countBand = 0;
    for (var i = binLow; i <= binHigh && i < magnitude.length; i++) {
      if (magnitude[i] > peak) peak = magnitude[i];
      sumBand += magnitude[i];
      countBand++;
    }
    if (countBand == 0) return 0.0;
    final bandMean = sumBand / countBand;
    if (bandMean <= 0) return 0.0;

    // 全频段平均能量
    var sumAll = 0.0;
    for (var i = 1; i < magnitude.length ~/ 2; i++) {
      sumAll += magnitude[i];
    }
    final allMean = sumAll / (magnitude.length ~/ 2 - 1);
    if (allMean <= 0) return 0.0;

    // 峰值 / 全频段均值，反映 2-5kHz 的突出程度
    final ratio = peak / allMean;

    // 归一化：ratio 1.0 → 0，ratio 5.0+ → 1（经验值）
    return ((ratio - 1.0) / 4.0).clamp(0.0, 1.0);
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
