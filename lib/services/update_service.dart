import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'github_config.dart';

/// App 当前版本（与 pubspec.yaml 的 version 保持一致）
class AppVersion {
  static const String current = '1.0.0';
}

/// 最新 Release 信息
class ReleaseInfo {
  final String tagName;
  final String name;
  final String body;
  final String? apkDownloadUrl;
  final int? apkSize;
  final String htmlUrl;
  final DateTime publishedAt;

  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    this.apkDownloadUrl,
    this.apkSize,
    required this.htmlUrl,
    required this.publishedAt,
  });

  /// 纯版本号字符串，去掉 "v" 前缀
  String get version =>
      tagName.startsWith('v') ? tagName.substring(1) : tagName;

  /// 是否比当前版本新
  bool get isNewer => _compareVersions(version, AppVersion.current) > 0;

  String get apkSizeLabel {
    if (apkSize == null) return '';
    final mb = apkSize! / 1024 / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// 版本比较：a > b 返回 1，a < b 返回 -1，相等返回 0
int _compareVersions(String a, String b) {
  final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va > vb) return 1;
    if (va < vb) return -1;
  }
  return 0;
}

/// 更新服务 — 调用 GitHub Releases API 检测与下载最新 APK
class UpdateService {
  static const _apiBase = 'https://api.github.com';

  /// 查询最新 Release
  static Future<ReleaseInfo?> checkLatest() async {
    await GithubConfig.load();
    final owner = GithubConfig.owner;
    final repo = GithubConfig.repo;
    final url = Uri.parse('$_apiBase/repos/$owner/$repo/releases/latest');

    final res = await http.get(
      url,
      headers: {
        'Accept': 'application/vnd.github+json',
        if (GithubConfig.hasToken)
          'Authorization': 'Bearer ${GithubConfig.token}',
      },
    );

    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final assets = (json['assets'] as List?) ?? [];

    // 找 APK asset
    String? apkUrl;
    int? apkSize;
    for (final a in assets) {
      final name = (a['name'] as String?) ?? '';
      if (name.endsWith('.apk')) {
        apkUrl = a['browser_download_url'] as String?;
        apkSize = a['size'] as int?;
        break;
      }
    }

    return ReleaseInfo(
      tagName: (json['tag_name'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      apkDownloadUrl: apkUrl,
      apkSize: apkSize,
      htmlUrl: (json['html_url'] as String?) ?? '',
      publishedAt: DateTime.tryParse(
              (json['published_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  /// 下载 APK 到临时目录，返回本地路径
  static Future<String> downloadApk(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('下载失败: HTTP ${res.statusCode}');
    }

    final tmpDir = await getTemporaryDirectory();
    final savePath = p.join(tmpDir.path, 'voiceprint_update.apk');
    final file = File(savePath);
    await file.writeAsBytes(res.bodyBytes);

    if (onProgress != null) {
      onProgress(res.bodyBytes.length, res.bodyBytes.length);
    }

    return savePath;
  }
}
