import 'package:shared_preferences/shared_preferences.dart';

/// GitHub 仓库配置 — 本地持久化用户填写的 token / owner / repo
class GithubConfig {
  static const _kToken = 'github_token';
  static const _kOwner = 'github_owner';
  static const _kRepo = 'github_repo';

  /// 默认仓库（用户可改）
  static const defaultOwner = 'PhosAQy';
  static const defaultRepo = 'voiceprint-app';

  static String? _token;
  static String _owner = defaultOwner;
  static String _repo = defaultRepo;
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final sp = await SharedPreferences.getInstance();
    _token = sp.getString(_kToken);
    _owner = sp.getString(_kOwner) ?? defaultOwner;
    _repo = sp.getString(_kRepo) ?? defaultRepo;
    _loaded = true;
  }

  static String? get token => _token;
  static String get owner => _owner;
  static String get repo => _repo;
  static bool get hasToken => _token != null && _token!.isNotEmpty;

  static Future<void> save({
    String? token,
    String? owner,
    String? repo,
  }) async {
    final sp = await SharedPreferences.getInstance();
    if (token != null) {
      _token = token;
      await sp.setString(_kToken, token);
    }
    if (owner != null) {
      _owner = owner;
      await sp.setString(_kOwner, owner);
    }
    if (repo != null) {
      _repo = repo;
      await sp.setString(_kRepo, repo);
    }
  }

  static Future<void> clearToken() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kToken);
    _token = null;
  }
}
