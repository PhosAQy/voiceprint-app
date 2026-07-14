package com.moyu.voiceprint

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val EAR_CHANNEL = "voiceprint/ear_monitor"
    private val DECODE_CHANNEL = "voiceprint/audio_decode"

    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var monitorThread: Thread? = null
    @Volatile
    private var isMonitoring = false
    private val handler = Handler(Looper.getMainLooper())

    // 耳返音频参数 — 44.1kHz 单声道 16bit
    private val sampleRate = 44100
    private val channelConfigIn = AudioFormat.CHANNEL_IN_MONO
    private val channelConfigOut = AudioFormat.CHANNEL_OUT_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT

    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 耳返通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EAR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (isMonitoring) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    if (!hasMicPermission()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    startMonitoring()
                    result.success(true)
                }
                "stop" -> {
                    stopMonitoring()
                    result.success(true)
                }
                "isRunning" -> {
                    result.success(isMonitoring)
                }
                else -> result.notImplemented()
            }
        }

        // 音频解码通道 — 将 M4A/MP3/AAC/FLAC 等转为 WAV (PCM 16-bit mono)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DECODE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "decodeToWav" -> {
                    val srcPath = call.argument<String>("srcPath")
                    val destPath = call.argument<String>("destPath")
                    if (srcPath == null || destPath == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val success = decodeToWav(srcPath, destPath)
                        result.success(success)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ==================== 耳返 ====================

    private fun hasMicPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }

    private fun startMonitoring() {
        val minBufIn = AudioRecord.getMinBufferSize(sampleRate, channelConfigIn, audioFormat)
        val minBufOut = AudioTrack.getMinBufferSize(sampleRate, channelConfigOut, audioFormat)
        val bufferSize = Math.max(minBufIn, minBufOut)

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                sampleRate,
                channelConfigIn,
                audioFormat,
                bufferSize * 2
            )
            audioTrack = AudioTrack(
                AudioManager.STREAM_VOICE_CALL,
                sampleRate,
                channelConfigOut,
                audioFormat,
                bufferSize * 2,
                AudioTrack.MODE_STREAM
            )
            audioTrack?.setVolume(1.0f)
        } catch (e: Exception) {
            return
        }

        isMonitoring = true
        audioRecord?.startRecording()
        audioTrack?.play()

        monitorThread = Thread {
            val buffer = ShortArray(bufferSize)
            while (isMonitoring) {
                try {
                    val read = audioRecord?.read(buffer, 0, buffer.size) ?: -1
                    if (read != null && read > 0) {
                        audioTrack?.write(buffer, 0, read)
                    }
                } catch (e: Exception) {
                    break
                }
            }
        }.also { it.start() }
    }

    private fun stopMonitoring() {
        isMonitoring = false
        try { monitorThread?.join(500) } catch (e: Exception) {}
        monitorThread = null
        try { audioRecord?.stop() } catch (e: Exception) {}
        try { audioTrack?.stop() } catch (e: Exception) {}
        audioRecord?.release()
        audioTrack?.release()
        audioRecord = null
        audioTrack = null
    }

    // ==================== 音频解码 ====================

    /// 使用 MediaExtractor + MediaCodec 将任意音频格式解码为 PCM，写入 WAV 文件
    private fun decodeToWav(srcPath: String, destPath: String): Boolean {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(srcPath)

            // 找到音频轨道
            var audioTrackIndex = -1
            var srcFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    srcFormat = f
                    break
                }
            }
            if (audioTrackIndex < 0 || srcFormat == null) return false

            extractor.selectTrack(audioTrackIndex)
            val mime = srcFormat.getString(MediaFormat.KEY_MIME)!!

            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(srcFormat, null, null, 0)
            codec.start()

            val outSampleRate = srcFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val outChannels = if (srcFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                srcFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            } else 1

            // 循环解码，收集 PCM 数据
            val pcmBuffer = ByteArrayOutputStream()
            val bufferInfo = MediaCodec.BufferInfo()
            val timeoutUs = 10000L
            var inputDone = false
            var outputDone = false

            while (!outputDone) {
                // 喂入数据
                if (!inputDone) {
                    val inputBufIdx = codec.dequeueInputBuffer(timeoutUs)
                    if (inputBufIdx >= 0) {
                        val inputBuffer = codec.getInputBuffer(inputBufIdx)!!
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(inputBufIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inputBufIdx, 0, sampleSize, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                // 读取解码输出
                val outputBufIdx = codec.dequeueOutputBuffer(bufferInfo, timeoutUs)
                if (outputBufIdx >= 0) {
                    if (bufferInfo.size > 0 && (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                        val outputBuffer = codec.getOutputBuffer(outputBufIdx)!!
                        val chunk = ByteArray(bufferInfo.size)
                        outputBuffer.get(chunk)
                        pcmBuffer.write(chunk)
                    }
                    codec.releaseOutputBuffer(outputBufIdx, false)
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outputDone = true
                    }
                }
            }

            codec.stop()
            codec.release()
            codec = null

            // 将 PCM 写入 WAV 文件（自动下混为单声道）
            val pcmData = pcmBuffer.toByteArray()
            writeWavFile(destPath, pcmData, outSampleRate, outChannels)
            return true
        } catch (e: Exception) {
            return false
        } finally {
            try { codec?.release() } catch (e: Exception) {}
            try { extractor.release() } catch (e: Exception) {}
        }
    }

    /// 将 PCM 16-bit 数据写入标准 WAV 文件（RIFF/WAVE，单声道）
    private fun writeWavFile(path: String, pcmData: ByteArray, sampleRate: Int, channels: Int) {
        // 下混为单声道
        val monoPcm = if (channels > 1) downmixToMono(pcmData, channels) else pcmData
        val dataSize = monoPcm.size

        FileOutputStream(path).use { fos ->
            BufferedOutputStream(fos).use { bos ->
                // RIFF/WAVE 头部 — 小端序
                val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
                header.put("RIFF".toByteArray())
                header.putInt(36 + dataSize)       // chunkSize
                header.put("WAVE".toByteArray())
                header.put("fmt ".toByteArray())
                header.putInt(16)                   // fmt subchunk size (PCM)
                header.putShort(1)                  // audioFormat = PCM
                header.putShort(1)                  // numChannels = 1 (mono)
                header.putInt(sampleRate)
                header.putInt(sampleRate * 2)       // byteRate = sampleRate * 1 * 16/8
                header.putShort(2)                  // blockAlign = 1 * 16/8
                header.putShort(16)                 // bitsPerSample
                header.put("data".toByteArray())
                header.putInt(dataSize)

                bos.write(header.array())
                bos.write(monoPcm)
                bos.flush()
            }
        }
    }

    /// 下混多声道 PCM 16-bit 为单声道（取各声道平均值）
    private fun downmixToMono(pcmData: ByteArray, channels: Int): ByteArray {
        val frameSize = 2 * channels
        val frameCount = pcmData.size / frameSize
        val out = ByteArray(frameCount * 2)
        val src = ByteBuffer.wrap(pcmData).order(ByteOrder.LITTLE_ENDIAN)
        val dst = ByteBuffer.wrap(out).order(ByteOrder.LITTLE_ENDIAN)

        for (i in 0 until frameCount) {
            var sum = 0
            for (ch in 0 until channels) {
                sum += src.short.toInt()
            }
            dst.putShort((sum / channels).toShort())
        }
        return out
    }

    override fun onDestroy() {
        stopMonitoring()
        super.onDestroy()
    }
}
