import 'package:flutter/services.dart';

/// 原生音频解码服务 — 通过 Android MediaExtractor + MediaCodec
/// 将 M4A/MP3/AAC/FLAC/OGG 等格式转换为 WAV (PCM 16-bit mono)
class AudioDecoderService {
  static const _channel = MethodChannel('voiceprint/audio_decode');

  /// 将 [srcPath] 指向的音频文件解码为 WAV，写入 [destPath]
  /// 返回 true 表示成功
  static Future<bool> decodeToWav(String srcPath, String destPath) async {
    try {
      final result = await _channel.invokeMethod<bool>('decodeToWav', {
        'srcPath': srcPath,
        'destPath': destPath,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
