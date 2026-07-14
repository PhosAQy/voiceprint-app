import 'dart:convert';
import 'package:flutter/painting.dart';
import '../theme/tokens.dart';

/// 录音数据模型 — 真实录音的完整元数据
class Recording {
  final int? id;
  final String filePath; // WAV 文件本地路径
  final String dateTimeLabel; // 例如 "07.14 15:30"
  final Duration duration;
  final List<double> waveform; // 缩略图波形 (14 点)
  final List<double> overviewWaveform; // 详情页波形 (60 点)
  final List<List<double>> resonanceStack; // 共鸣堆叠 20 段
  final List<double> pitch; // 音高曲线 20 点
  final int createdAt; // 毫秒时间戳

  Recording({
    this.id,
    required this.filePath,
    required this.dateTimeLabel,
    required this.duration,
    required this.waveform,
    required this.overviewWaveform,
    required this.resonanceStack,
    required this.pitch,
    required this.createdAt,
  });

  bool get isNew =>
      DateTime.now().millisecondsSinceEpoch - createdAt <
      const Duration(hours: 24).inMilliseconds;

  String get durationLabel {
    final m = duration.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 从数据库行构造
  factory Recording.fromMap(Map<String, dynamic> map) {
    return Recording(
      id: map['id'] as int?,
      filePath: map['filePath'] as String,
      dateTimeLabel: map['dateTimeLabel'] as String,
      duration: Duration(milliseconds: (map['durationMs'] as num).toInt()),
      waveform: _decodeList(map['waveformJson'] as String),
      overviewWaveform: _decodeList(map['overviewWaveformJson'] as String),
      resonanceStack: _decodeStack(map['stackJson'] as String),
      pitch: _decodeList(map['pitchJson'] as String),
      createdAt: (map['createdAt'] as num).toInt(),
    );
  }

  /// 转为数据库行
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'filePath': filePath,
      'dateTimeLabel': dateTimeLabel,
      'durationMs': duration.inMilliseconds,
      'waveformJson': jsonEncode(waveform),
      'overviewWaveformJson': jsonEncode(overviewWaveform),
      'stackJson': jsonEncode(resonanceStack),
      'pitchJson': jsonEncode(pitch),
      'createdAt': createdAt,
    };
  }

  static List<double> _decodeList(String json) =>
      (jsonDecode(json) as List).cast<double>();

  static List<List<double>> _decodeStack(String json) =>
      (jsonDecode(json) as List).map((e) => (e as List).cast<double>()).toList();
}

/// 声音报告的颜色和标签（常量）
class SoundReportConfig {
  SoundReportConfig._();

  static const List<Color> layerColors = [
    VpTokens.primary, // 胸腔（底）
    VpTokens.primary300, // 鼻腔
    VpTokens.primary200, // 头腔
    VpTokens.borderLight, // 大白嗓（顶）
  ];

  static const List<String> layerLabels = ['胸腔', '鼻腔', '头腔', '大白嗓'];
}
