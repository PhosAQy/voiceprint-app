import 'dart:io';
import 'dart:typed_data';

/// WAV 文件读取器 — 解析 PCM 16-bit 单声道/立体声 WAV
class WavData {
  final int sampleRate;
  final int numChannels;
  final int bitsPerSample;
  final Float64List samples; // 归一化到 -1.0 ~ 1.0（如立体声已混合为单声道）
  final int totalSamples;

  WavData({
    required this.sampleRate,
    required this.numChannels,
    required this.bitsPerSample,
    required this.samples,
    required this.totalSamples,
  });

  Duration get duration =>
      Duration(milliseconds: (totalSamples / sampleRate * 1000).round());
}

class WavReader {
  WavReader._();

  /// 从文件路径读取 WAV 并解析 PCM 数据
  static Future<WavData> read(String path) async {
    final bytes = await File(path).readAsBytes();
    return parse(bytes);
  }

  /// 解析 WAV 字节流
  static WavData parse(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);

    // RIFF header
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    if (riff != 'RIFF') throw FormatException('Not a RIFF file: $riff');

    // WAVE
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (wave != 'WAVE') throw FormatException('Not a WAVE file: $wave');

    int offset = 12;
    int sampleRate = 16000;
    int numChannels = 1;
    int bitsPerSample = 16;
    Uint8List? pcmData;

    // 遍历 chunks
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      final dataStart = offset + 8;

      if (chunkId == 'fmt ') {
        numChannels = bd.getUint16(dataStart + 2, Endian.little);
        sampleRate = bd.getUint32(dataStart + 4, Endian.little);
        bitsPerSample = bd.getUint16(dataStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        pcmData = bytes.sublist(dataStart, dataStart + chunkSize);
      }

      offset = dataStart + chunkSize;
      // chunks 偶数对齐
      if (chunkSize.isOdd) offset++;
    }

    if (pcmData == null) {
      throw const FormatException('No data chunk found in WAV');
    }

    // 解码 PCM 16-bit
    final samples = _decodePcm16(pcmData, numChannels);
    return WavData(
      sampleRate: sampleRate,
      numChannels: numChannels,
      bitsPerSample: bitsPerSample,
      samples: samples,
      totalSamples: samples.length,
    );
  }

  /// 解码 16-bit PCM，立体声混合为单声道
  static Float64List _decodePcm16(Uint8List pcmData, int numChannels) {
    final bd = ByteData.sublistView(pcmData);
    final frameCount = pcmData.length ~/ (2 * numChannels);
    final out = Float64List(frameCount);
    const scale = 1.0 / 32768.0;

    for (var i = 0; i < frameCount; i++) {
      double sum = 0;
      for (var ch = 0; ch < numChannels; ch++) {
        final idx = (i * numChannels + ch) * 2;
        final s = bd.getInt16(idx, Endian.little);
        sum += s;
      }
      out[i] = (sum / numChannels) * scale;
    }
    return out;
  }
}
