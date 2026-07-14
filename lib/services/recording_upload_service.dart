import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'github_config.dart';

/// 录音上传结果
class UploadResult {
  final bool success;
  final String? downloadUrl;
  final String? error;
  const UploadResult({required this.success, this.downloadUrl, this.error});
}

/// 录音上传服务 — 通过 GitHub Contents API 上传 WAV 到仓库 recordings/ 目录
class RecordingUploadService {
  static const _apiBase = 'https://api.github.com';

  /// 上传录音文件到 GitHub 仓库
  static Future<UploadResult> upload(String filePath) async {
    await GithubConfig.load();

    if (!GithubConfig.hasToken) {
      return const UploadResult(
        success: false,
        error: '未配置 GitHub Token，请先在设置页填写',
      );
    }

    final file = File(filePath);
    if (!await file.exists()) {
      return const UploadResult(
        success: false,
        error: '录音文件不存在',
      );
    }

    final bytes = await file.readAsBytes();
    final base64Content = base64Encode(bytes);
    final fileName = p.basename(filePath);
    final owner = GithubConfig.owner;
    final repo = GithubConfig.repo;
    final keyPath = 'recordings/$fileName';

    final url = Uri.parse('$_apiBase/repos/$owner/$repo/contents/$keyPath');

    // 先检查文件是否已存在（获取 sha 用于覆盖）
    String? sha;
    final checkRes = await http.get(
      url,
      headers: {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer ${GithubConfig.token}',
      },
    );
    if (checkRes.statusCode == 200) {
      final checkJson = jsonDecode(checkRes.body) as Map<String, dynamic>;
      sha = checkJson['sha'] as String?;
    }

    // 上传（创建或更新）
    final body = {
      'message': 'chore(recordings): upload $fileName',
      'content': base64Content,
      if (sha != null) 'sha': sha,
    };

    final res = await http.put(
      url,
      headers: {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer ${GithubConfig.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (res.statusCode == 201 || res.statusCode == 200) {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final content = json['content'] as Map<String, dynamic>?;
      final downloadUrl = content?['download_url'] as String?;
      return UploadResult(success: true, downloadUrl: downloadUrl);
    }

    return UploadResult(
      success: false,
      error: '上传失败: HTTP ${res.statusCode} — ${_extractMessage(res.body)}',
    );
  }

  static String _extractMessage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['message'] as String?) ?? body;
    } catch (_) {
      return body;
    }
  }
}
