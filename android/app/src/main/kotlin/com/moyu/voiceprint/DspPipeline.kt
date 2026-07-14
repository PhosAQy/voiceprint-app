package com.moyu.voiceprint

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin

/// DSP 参数 — 由 Flutter 实时更新
data class DspParams(
    var reverbIndex: Int = 1,    // 0=原声 1=录音室 2=大厅 3=KTV 4=演唱会
    var dryWet: Double = 0.30,   // 0=纯干声 1=纯湿声
    var decay: Double = 0.40,    // 0-1 反馈强度
    var preDelay: Double = 0.33, // 0-1 → 0-60ms
    var monitorVol: Double = 0.75,// 0-1
    var eqLow: Double = 0.58,    // 0-1, 0.5=0dB
    var eqMid: Double = 0.50,
    var eqHigh: Double = 0.42,
    var micIndex: Int = 1        // 0=动圈 1=电容 2=屏幕麦
) {
    fun copy(): DspParams {
        val p = DspParams()
        p.reverbIndex = reverbIndex
        p.dryWet = dryWet
        p.decay = decay
        p.preDelay = preDelay
        p.monitorVol = monitorVol
        p.eqLow = eqLow
        p.eqMid = eqMid
        p.eqHigh = eqHigh
        p.micIndex = micIndex
        return p
    }
}

/// DSP 管道：麦克风模拟 → EQ → 混响 → 音量
///
/// 混响算法：Schroeder 混响（4 个并联 comb + 2 个串联 allpass）
/// EQ：三段 biquad（low-shelf + peaking + high-shelf）
class DspPipeline(private val sampleRate: Int) {

    // ---- 麦克风模拟 EQ（固定参数，按 micIndex 选择）----
    private val micLowShelf = Biquad(sampleRate)
    private val micHighShelf = Biquad(sampleRate)

    // ---- 三段 EQ ----
    private val eqLowShelf = Biquad(sampleRate)   // 低频 shelf @ 200Hz
    private val eqMidPeak = Biquad(sampleRate)    // 中频 peak @ 1000Hz
    private val eqHighShelf = Biquad(sampleRate)  // 高频 shelf @ 4000Hz

    // ---- Schroeder 混响 ----
    // 4 个并联 comb filter（延迟时间互质，单位：样本）
    // @ 44.1kHz: 1427, 1601, 1811, 1973（经典 Schroeder 值）
    private val combDelays = intArrayOf(1427, 1601, 1811, 1973)
    private val combs = Array(4) { CombFilter(combDelays[it]) }
    // 2 个串联 allpass filter
    private val allpassDelays = intArrayOf(396, 660)
    private val allpasses = Array(2) { AllpassFilter(allpassDelays[it]) }

    // ---- 预延迟缓冲 ----
    private val preDelayMax = sampleRate / 16 // 最大 62.5ms
    private val preDelayBuf = FloatArray(preDelayMax)
    private var preDelayPos = 0

    init {
        // 初始化麦克风模拟
        applyMicModel(1)
    }

    /// 主处理函数
    fun process(samples: FloatArray, len: Int, params: DspParams) {
        if (len <= 0) return

        // 1. 麦克风模拟（切换时更新）
        applyMicModel(params.micIndex)

        for (i in 0 until len) {
            var s = samples[i]

            // 2. 麦克风模拟 EQ
            s = micLowShelf.process(s)
            s = micHighShelf.process(s)

            // 3. 三段 EQ
            s = eqLowShelf.process(s)
            s = eqMidPeak.process(s)
            s = eqHighShelf.process(s)

            // 4. 混响（Schroeder）
            val wet = if (params.reverbIndex > 0) {
                processReverb(s, params)
            } else 0.0f

            // 5. 干湿混合
            val dryWet = params.dryWet.toFloat()
            var out = s * (1.0f - dryWet) + wet * dryWet

            // 6. 音量
            out *= params.monitorVol.toFloat()

            samples[i] = out
        }
    }

    /// Schroeder 混响处理
    private fun processReverb(input: Float, params: DspParams): Float {
        // 反馈增益：根据 decay 参数（0.3-0.75）
        val feedback = (0.3 + params.decay * 0.45).toFloat()

        // 预延迟
        val preDelaySamples = (params.preDelay * preDelayMax).toInt().coerceIn(0, preDelayMax - 1)
        val delayed = preDelayBuf[(preDelayPos - preDelaySamples + preDelayMax) % preDelayMax]
        preDelayBuf[preDelayPos] = input
        preDelayPos = (preDelayPos + 1) % preDelayMax

        // 混响强度系数（按 reverbIndex 调整 wet 量）
        val reverbGain = when (params.reverbIndex) {
            1 -> 0.6f  // 录音室
            2 -> 0.8f  // 大厅
            3 -> 1.0f  // KTV
            4 -> 1.2f  // 演唱会
            else -> 0.0f
        }

        // 4 个并联 comb
        var combSum = 0.0f
        for (k in 0 until 4) {
            combSum += combs[k].process(delayed, feedback)
        }
        combSum *= 0.25f

        // 2 个串联 allpass
        var y = allpasses[0].process(combSum, 0.7f)
        y = allpasses[1].process(y, 0.7f)

        return y * reverbGain
    }

    /// 应用麦克风模拟参数
    private fun applyMicModel(micIndex: Int) {
        when (micIndex) {
            0 -> {
                // 动圈麦：低频略增强，高频衰减（温暖、圆润）
                micLowShelf.setLowShelf(200.0, 1.0, 3.0)
                micHighShelf.setHighShelf(4000.0, 1.0, -4.0)
            }
            1 -> {
                // 电容麦：平坦响应（参考级）
                micLowShelf.setLowShelf(200.0, 1.0, 0.0)
                micHighShelf.setHighShelf(4000.0, 1.0, 0.0)
            }
            2 -> {
                // 屏幕麦：中频突出，高频限制（电话效果）
                micLowShelf.setLowShelf(200.0, 1.0, -6.0)
                micHighShelf.setHighShelf(3500.0, 1.0, -8.0)
            }
        }
    }

    /// 更新 EQ 参数（由外部按滑块值调用）
    fun updateEq(eqLow: Double, eqMid: Double, eqHigh: Double) {
        // 0-1 → ±12dB（0.5=0dB）
        val lowDb = (eqLow - 0.5) * 24.0
        val midDb = (eqMid - 0.5) * 24.0
        val highDb = (eqHigh - 0.5) * 24.0
        eqLowShelf.setLowShelf(200.0, 1.0, lowDb)
        eqMidPeak.setPeaking(1000.0, 1.0, midDb)
        eqHighShelf.setHighShelf(4000.0, 1.0, highDb)
    }
}

// ==================== Biquad 滤波器 ====================

/// 二阶 IIR（biquad）滤波器
/// 支持 low-shelf / high-shelf / peaking 三种类型
class Biquad(private val sampleRate: Int) {
    private var b0 = 1.0
    private var b1 = 0.0
    private var b2 = 0.0
    private var a1 = 0.0
    private var a2 = 0.0
    private var x1 = 0.0
    private var x2 = 0.0
    private var y1 = 0.0
    private var y2 = 0.0

    /// Low-shelf：低频提升/衰减
    fun setLowShelf(freq: Double, q: Double, gainDb: Double) {
        val A = Math.pow(10.0, gainDb / 40.0)
        val w0 = 2.0 * PI * freq / sampleRate
        val cosW = cos(w0)
        val sinW = sin(w0)
        val alpha = sinW / (2.0 * q)
        val beta = A.coerceAtLeast(0.0)

        b0 = A * ((A + 1) - (A - 1) * cosW + 2 * beta * alpha)
        b1 = 2 * A * ((A - 1) - (A + 1) * cosW)
        b2 = A * ((A + 1) - (A - 1) * cosW - 2 * beta * alpha)
        val a0 = (A + 1) + (A - 1) * cosW + 2 * beta * alpha
        a1 = -2 * ((A - 1) + (A + 1) * cosW)
        a2 = (A + 1) + (A - 1) * cosW - 2 * beta * alpha

        normalize(a0)
    }

    /// High-shelf：高频提升/衰减
    fun setHighShelf(freq: Double, q: Double, gainDb: Double) {
        val A = Math.pow(10.0, gainDb / 40.0)
        val w0 = 2.0 * PI * freq / sampleRate
        val cosW = cos(w0)
        val sinW = sin(w0)
        val alpha = sinW / (2.0 * q)
        val beta = A.coerceAtLeast(0.0)

        b0 = A * ((A + 1) + (A - 1) * cosW + 2 * beta * alpha)
        b1 = -2 * A * ((A - 1) + (A + 1) * cosW)
        b2 = A * ((A + 1) + (A - 1) * cosW - 2 * beta * alpha)
        val a0 = (A + 1) - (A - 1) * cosW + 2 * beta * alpha
        a1 = 2 * ((A - 1) - (A + 1) * cosW)
        a2 = (A + 1) - (A - 1) * cosW - 2 * beta * alpha

        normalize(a0)
    }

    /// Peaking：中频峰
    fun setPeaking(freq: Double, q: Double, gainDb: Double) {
        val A = Math.pow(10.0, gainDb / 40.0)
        val w0 = 2.0 * PI * freq / sampleRate
        val cosW = cos(w0)
        val sinW = sin(w0)
        val alpha = sinW / (2.0 * q)

        b0 = 1 + alpha * A
        b1 = -2 * cosW
        b2 = 1 - alpha * A
        val a0 = 1 + alpha / A
        a1 = -2 * cosW
        a2 = 1 - alpha / A

        normalize(a0)
    }

    private fun normalize(a0: Double) {
        b0 /= a0
        b1 /= a0
        b2 /= a0
        a1 /= a0
        a2 /= a0
    }

    fun process(x: Float): Float {
        val y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x.toDouble()
        y2 = y1
        y1 = y
        return y.toFloat()
    }
}

// ==================== 混响组件 ====================

/// Comb filter（带反馈的延迟线）
class CombFilter(private val delay: Int) {
    private val buffer = FloatArray(delay)
    private var pos = 0

    fun process(input: Float, feedback: Float): Float {
        val output = buffer[pos]
        buffer[pos] = input + output * feedback
        pos = (pos + 1) % delay
        return output
    }
}

/// Allpass filter（用于产生密集回声）
class AllpassFilter(private val delay: Int) {
    private val buffer = FloatArray(delay)
    private var pos = 0

    fun process(input: Float, feedback: Float): Float {
        val delayed = buffer[pos]
        val output = -input + delayed
        buffer[pos] = input + delayed * feedback
        pos = (pos + 1) % delay
        return output
    }
}
