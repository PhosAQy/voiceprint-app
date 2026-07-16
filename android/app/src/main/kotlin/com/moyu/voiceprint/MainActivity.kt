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
import android.media.AudioAttributes
import android.os.Bundle
import android.os.Process
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

    // 耳返音频参数 — 用设备原生采样率避免重采样延迟
    private var sampleRate = 48000
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
                "updateParams" -> {
                    @Suppress("UNCHECKED_CAST")
                    val params = call.argument<Map<String, Any>>("params") ?: emptyMap()
                    updateDspParams(params)
                    result.success(true)
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

    // DSP 参数（由 Flutter 实时更新，DSP 线程读取）
    @Volatile private var dspParams = DspParams()
    private var dsp: DspPipeline? = null

    private fun hasMicPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }

    /// 更新 DSP 参数（由 Flutter 调用）
    private fun updateDspParams(params: Map<String, Any>) {
        val p = dspParams.copy()
        (params["reverbIndex"] as? Number)?.toInt()?.let { p.reverbIndex = it }
        (params["dryWet"] as? Number)?.toDouble()?.let { p.dryWet = it }
        (params["decay"] as? Number)?.toDouble()?.let { p.decay = it }
        (params["preDelay"] as? Number)?.toDouble()?.let { p.preDelay = it }
        (params["monitorVol"] as? Number)?.toDouble()?.let { p.monitorVol = it }
        (params["eqLow"] as? Number)?.toDouble()?.let { p.eqLow = it }
        (params["eqMid"] as? Number)?.toDouble()?.let { p.eqMid = it }
        (params["eqHigh"] as? Number)?.toDouble()?.let { p.eqHigh = it }
        (params["micIndex"] as? Number)?.toInt()?.let { p.micIndex = it }
        dspParams = p
        // 同步 EQ 系数到 biquad
        dsp?.updateEq(p.eqLow, p.eqMid, p.eqHigh)
    }

    private fun startMonitoring() {
        // 1. 查询设备原生采样率，避免系统重采样带来的延迟
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        val nativeRate = am.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull()
        if (nativeRate != null && nativeRate > 0) {
            sampleRate = nativeRate
        }

        // 2. 计算最小缓冲（LOW_LATENCY 模式下系统会返回较小值）
        val minBufIn = AudioRecord.getMinBufferSize(sampleRate, channelConfigIn, audioFormat)
        val minBufOut = AudioTrack.getMinBufferSize(sampleRate, channelConfigOut, audioFormat)

        try {
            // 3. AudioRecord.Builder — VOICE_COMMUNICATION 源 + 最小缓冲
            //    (AudioRecord.Builder 没有 setPerformanceMode，用 VOICE_COMMUNICATION 源本身已是低延迟)
            audioRecord = AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setChannelMask(channelConfigIn)
                        .setEncoding(audioFormat)
                        .build()
                )
                .setBufferSizeInBytes(minBufIn)
                .build()

            // 4. AudioTrack.Builder + LOW_LATENCY + VOICE_COMMUNICATION 用途
            //    buffer 设为最小值，保证播放缓冲最小 → 稳态延迟最低
            audioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setChannelMask(channelConfigOut)
                        .setEncoding(audioFormat)
                        .build()
                )
                .setBufferSizeInBytes(minBufOut)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            audioTrack?.setVolume(1.0f)
        } catch (e: Exception) {
            return
        }

        // 5. 初始化 DSP 处理器（用实际采样率）
        val dspInst = DspPipeline(sampleRate)
        dsp = dspInst
        dspInst.updateEq(dspParams.eqLow, dspParams.eqMid, dspParams.eqHigh)

        isMonitoring = true
        audioRecord?.startRecording()
        audioTrack?.play()

        // 6. 每次处理 64 帧（~1.3ms @ 48kHz），最小化端到端延迟
        val frameSize = 64
        monitorThread = Thread {
            // 提升线程优先级到音频紧急级，减少调度延迟
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            val buffer = ShortArray(frameSize)
            val processed = FloatArray(frameSize)
            while (isMonitoring) {
                try {
                    val read = audioRecord?.read(buffer, 0, frameSize) ?: -1
                    if (read > 0) {
                        // Short → Float
                        for (i in 0 until read) {
                            processed[i] = buffer[i] / 32768.0f
                        }
                        // DSP 处理
                        val params = dspParams
                        dspInst.process(processed, read, params)
                        // Float → Short
                        for (i in 0 until read) {
                            val v = (processed[i] * 32767.0f).toInt().coerceIn(-32768, 32767)
                            buffer[i] = v.toShort()
                        }
                        // 非阻塞写入（WRITE_NON_BLOCKING），防止累积延迟
                        audioTrack?.write(buffer, 0, read, AudioTrack.WRITE_NON_BLOCKING)
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
        dsp = null
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
