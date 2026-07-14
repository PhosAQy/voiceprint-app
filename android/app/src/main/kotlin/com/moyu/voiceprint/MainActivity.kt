package com.moyu.voiceprint

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "voiceprint/ear_monitor"
    private val REQUEST_MIC = 1001

    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var monitorThread: Thread? = null
    @Volatile
    private var isMonitoring = false
    private val handler = Handler(Looper.getMainLooper())

    // 音频参数 — 44.1kHz 单声道 16bit，平衡延迟与兼容性
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
    }

    private fun hasMicPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }

    private fun startMonitoring() {
        // 计算最小缓冲区
        val minBufIn = AudioRecord.getMinBufferSize(sampleRate, channelConfigIn, audioFormat)
        val minBufOut = AudioTrack.getMinBufferSize(sampleRate, channelConfigOut, audioFormat)

        // 使用较小的缓冲区以降低延迟（约 20-40ms）
        val bufferSize = Math.max(minBufIn, minBufOut)

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                sampleRate,
                channelConfigIn,
                audioFormat,
                bufferSize * 2
            )

            // 使用 STREAM_VOICE_CALL 获得最低延迟
            audioTrack = AudioTrack(
                AudioManager.STREAM_VOICE_CALL,
                sampleRate,
                channelConfigOut,
                audioFormat,
                bufferSize * 2,
                AudioTrack.MODE_STREAM
            )

            // 设置音量
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
        try {
            monitorThread?.join(500)
        } catch (e: Exception) {
        }
        monitorThread = null
        try {
            audioRecord?.stop()
        } catch (e: Exception) {
        }
        try {
            audioTrack?.stop()
        } catch (e: Exception) {
        }
        audioRecord?.release()
        audioTrack?.release()
        audioRecord = null
        audioTrack = null
    }

    override fun onDestroy() {
        stopMonitoring()
        super.onDestroy()
    }
}
