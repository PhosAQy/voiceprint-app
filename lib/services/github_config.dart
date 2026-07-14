import 'package:shared_preferences/shared_preferences.dart';

/// GitHub 仓库配置 — 仅用于检测更新（读取公开 Release）
/// 不需要 Token，不需要上传功能
class GithubConfig {
  static const _kOwner = 'github_owner';
  static const _kRepo = 'github_repo';

  /// 默认仓库
  static const defaultOwner = 'PhosAQy';
  static const defaultRepo = 'voiceprint-app';

  static String _owner = defaultOwner;
  static String _repo = defaultRepo;
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final sp = await SharedPreferences.getInstance();
    _owner = sp.getString(_kOwner) ?? defaultOwner;
    _repo = sp.getString(_kRepo) ?? defaultRepo;
    _loaded = true;
  }

  static String get owner => _owner;
  static String get repo => _repo;

  static Future<void> save({
    String? owner,
    String? repo,
  }) async {
    final sp = await SharedPreferences.getInstance();
    if (owner != null) {
      _owner = owner;
      await sp.setString(_kOwner, owner);
    }
    if (repo != null) {
      _repo = repo;
      await sp.setString(_kRepo, repo);
    }
  }
}
