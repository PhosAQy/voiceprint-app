import 'dart:math';
import 'dart:typed_data';

/// 线性预测编码（LPC）+ 共振峰提取
///
/// 声学依据：声道可建模为全极点滤波器 H(z) = 1 / A(z)，
/// A(z) = 1 + a1*z^-1 + a2*z^-2 + ... + aN*z^-N
/// 滤波器的极点（A(z)=0 的根）对应声道共振峰（formants）。
///
/// 算法：
/// 1. 自相关法 + Levinson-Durbin 递归求解 LPC 系数 a1..aN
/// 2. 对 A(z) 多项式求根（Bairstow 方法）
/// 3. 根的辐角对应共振峰频率：f = arg(z) * sampleRate / (2π)
/// 4. 根的模越接近 1，共振峰越尖锐（带宽越窄）
class Lpc {
  Lpc._();

  /// Levinson-Durbin 递归求解 LPC 系数
  ///
  /// [samples] 输入信号（建议先加窗）
  /// [order] LPC 阶数（共振峰提取一般用 2 * 期望共振峰数，
  ///   采样率 16kHz 取 12，44.1kHz 取 20）
  /// 返回 LPC 系数 [1, a1, a2, ..., aN]（长度 = order+1）
  static Float64List compute(Float64List samples, int order) {
    if (samples.isEmpty || order <= 0) {
      return Float64List(1)..[0] = 1.0;
    }

    // 1. 自相关 r[0..order]
    final r = Float64List(order + 1);
    for (var k = 0; k <= order; k++) {
      var sum = 0.0;
      for (var i = k; i < samples.length; i++) {
        sum += samples[i] * samples[i - k];
      }
      r[k] = sum;
    }

    // 2. Levinson-Durbin 递归
    final a = Float64List(order + 1);
    final aPrev = Float64List(order + 1);
    a[0] = 1.0;
    aPrev[0] = 1.0;

    var e = r[0]; // 误差
    if (e <= 0) return a;

    for (var i = 1; i <= order; i++) {
      // 反射系数 k_i = -(r[i] + sum_{j=1}^{i-1} aPrev[j] * r[i-j]) / e
      var acc = r[i];
      for (var j = 1; j < i; j++) {
        acc += aPrev[j] * r[i - j];
      }
      final k = -acc / e;

      // 更新系数
      a[i] = k;
      for (var j = 1; j < i; j++) {
        a[j] = aPrev[j] + k * aPrev[i - j];
      }

      // 更新误差
      e *= 1 - k * k;
      if (e <= 0) break;

      // 保存当前系数供下一轮使用
      for (var j = 0; j <= i; j++) {
        aPrev[j] = a[j];
      }
    }

    return a;
  }

  /// 从 LPC 系数求根，提取共振峰频率
  ///
  /// 返回按频率排序的共振峰列表，每个元素为 (频率Hz, 带宽Hz)
  /// 带宽反映共振峰的尖锐程度（带宽小 = 共振强烈）
  static List<Formant> extractFormants(Float64List lpc, int sampleRate) {
    if (lpc.length < 2) return [];

    // 多项式 A(z) = 1 + a1*z^-1 + ... + aN*z^-N
    // 转换为 z 正幂形式用于求根
    final coeffs = lpc.toList(); // 已经是 [1, a1, ..., aN]，对应降幂

    final roots = _findRoots(coeffs);
    if (roots.isEmpty) return [];

    final formants = <Formant>[];
    for (final r in roots) {
      // 只取单位圆内的根（|r| < 1，物理可实现）
      final mag = sqrt(r.real * r.real + r.imag * r.imag);
      if (mag > 1.0 || mag < 0.1) continue;

      // 只取正频率（共轭对的一半）
      if (r.imag <= 0) continue;

      // 频率 = arg(z) * sampleRate / (2π)
      final angle = atan2(r.imag, r.real);
      final freq = angle * sampleRate / (2 * pi);

      // 带宽 = -ln(|r|) * sampleRate / π
      // |r| 越接近 1，带宽越窄（共振越强）
      final bw = -log(mag) * sampleRate / pi;

      // 过滤不合理频率
      if (freq < 50 || freq > sampleRate / 2 - 100) continue;
      if (bw < 0 || bw > 1000) continue;

      formants.add(Formant(freq, bw));
    }

    formants.sort((a, b) => a.frequency.compareTo(b.frequency));
    return formants;
  }
}

/// 共振峰：频率 + 带宽
class Formant {
  final double frequency; // Hz
  final double bandwidth; // Hz，越小共振越强

  const Formant(this.frequency, this.bandwidth);

  /// 共振强度：带宽越窄，强度越高（0-1）
  double get strength {
    // 带宽 50Hz → 1.0，带宽 500Hz → 0.1
    final s = 1.0 - (bandwidth / 500).clamp(0.0, 1.0);
    return s.clamp(0.0, 1.0);
  }

  @override
  String toString() => 'F(${frequency.toStringAsFixed(0)}Hz, bw=${bandwidth.toStringAsFixed(0)})';
}

/// 复数
class Complex {
  final double real;
  final double imag;
  const Complex(this.real, this.imag);

  Complex operator +(Complex o) => Complex(real + o.real, imag + o.imag);
  Complex operator -(Complex o) => Complex(real - o.real, imag - o.imag);
  Complex operator *(Complex o) =>
      Complex(real * o.real - imag * o.imag, real * o.imag + imag * o.real);

  double abs() => sqrt(real * real + imag * imag);

  @override
  String toString() => '$real${imag >= 0 ? '+' : ''}${imag}i';
}

/// Bairstow 方法求多项式所有根
///
/// 输入多项式系数（降幂），返回所有根
List<Complex> _findRoots(List<double> coeffs) {
  // 移除前导零
  var start = 0;
  while (start < coeffs.length - 1 && coeffs[start].abs() < 1e-12) {
    start++;
  }
  var poly = coeffs.sublist(start);
  if (poly.length <= 1) return [];

  final roots = <Complex>[];

  // 不断用 Bairstow 提取二次因子，直到多项式降为一次或二次
  while (poly.length > 3) {
    final result = _bairstow(poly);
    if (result == null) break;
    final (factor, quadratic) = result;
    final pair = _solveQuadratic(quadratic[0], quadratic[1], quadratic[2]);
    roots.addAll(pair);
    poly = _polyDivide(poly, factor);
  }

  // 处理剩余的一次或二次
  if (poly.length == 3) {
    roots.addAll(_solveQuadratic(poly[0], poly[1], poly[2]));
  } else if (poly.length == 2) {
    roots.add(Complex(-poly[1] / poly[0], 0));
  }

  return roots;
}

/// Bairstow 方法：从多项式 p(x) 中提取一个二次因子 x² + rx + s
/// 返回 (二次因子, p(x) 除以该因子的商)
(List<double>, List<double>)? _bairstow(List<double> poly) {
  final n = poly.length - 1;
  if (n < 2) return null;

  // 归一化
  final p = poly.map((c) => c / poly[0]).toList();

  // 初始猜测
  var r = 0.1;
  var s = -0.1;
  const maxIter = 100;
  const eps = 1e-10;

  for (var iter = 0; iter < maxIter; iter++) {
    // b = p / (x² + rx + s) 的商和余数
    final b = List<double>.filled(p.length, 0);
    b[0] = p[0];
    b[1] = p[1] - r * b[0];
    for (var i = 2; i < p.length; i++) {
      b[i] = p[i] - r * b[i - 1] - s * b[i - 2];
    }
    // 余数: b[n], b[n-1] 实际上是 c[]
    final rem1 = b[n - 1]; // 对应 s 项
    final rem0 = b[n]; // 对应常数项

    // c = b / (x² + rx + s)
    final c = List<double>.filled(p.length, 0);
    c[0] = b[0];
    c[1] = b[1] - r * c[0];
    for (var i = 2; i < p.length - 1; i++) {
      c[i] = b[i] - r * c[i - 1] - s * c[i - 2];
    }

    // 雅可比矩阵元
    final denom = c[n - 2] * c[n - 2] - c[n - 3] * (c[n - 1] - b[n - 1]);
    if (denom.abs() < 1e-15) return null;

    final dr = (-rem1 * c[n - 2] + rem0 * c[n - 3]) / denom;
    final ds = (-rem0 * c[n - 2] + rem1 * (c[n - 1] - b[n - 1])) / denom;

    r += dr;
    s += ds;

    if (dr.abs() < eps && ds.abs() < eps) {
      // 收敛
      final factor = [1.0, r, s];
      // 商是 b[0..n-2]
      final quotient = b.sublist(0, n - 1);
      return (factor, quotient);
    }
  }
  return null;
}

/// 多项式除法：p / divisor，返回商
List<double> _polyDivide(List<double> p, List<double> divisor) {
  // divisor 是二次 [1, r, s]
  final n = p.length - 1;
  final q = List<double>.filled(n - 1, 0);
  final r = List<double>.filled(p.length, 0);

  for (var i = 0; i < p.length; i++) {
    r[i] = p[i];
  }

  for (var i = 0; i <= n - 2; i++) {
    q[i] = r[i];
    r[i + 1] -= divisor[1] * q[i];
    r[i + 2] -= divisor[2] * q[i];
  }

  return q;
}

/// 解二次方程 ax² + bx + c = 0
List<Complex> _solveQuadratic(double a, double b, double c) {
  final disc = b * b - 4 * a * c;
  if (disc >= 0) {
    final sq = sqrt(disc);
    return [
      Complex((-b + sq) / (2 * a), 0),
      Complex((-b - sq) / (2 * a), 0),
    ];
  } else {
    final sq = sqrt(-disc);
    return [
      Complex(-b / (2 * a), sq / (2 * a)),
      Complex(-b / (2 * a), -sq / (2 * a)),
    ];
  }
}
