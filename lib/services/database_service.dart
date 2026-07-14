import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/recording.dart';

/// 本地 SQLite 数据库服务 — 录音 CRUD
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'voiceprint.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE recordings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filePath TEXT NOT NULL,
            dateTimeLabel TEXT NOT NULL,
            durationMs INTEGER NOT NULL,
            waveformJson TEXT NOT NULL,
            overviewWaveformJson TEXT NOT NULL,
            stackJson TEXT NOT NULL,
            pitchJson TEXT NOT NULL,
            createdAt INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  /// 插入一条录音
  Future<int> insert(Recording recording) async {
    final db = await _getDb();
    return db.insert('recordings', recording.toMap());
  }

  /// 获取所有录音（按创建时间降序）
  Future<List<Recording>> getAll() async {
    final db = await _getDb();
    final rows = await db.query(
      'recordings',
      orderBy: 'createdAt DESC',
    );
    return rows.map(Recording.fromMap).toList();
  }

  /// 获取单条录音
  Future<Recording?> getById(int id) async {
    final db = await _getDb();
    final rows = await db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Recording.fromMap(rows.first);
  }

  /// 删除录音（同时删除文件）
  Future<int> delete(int id) async {
    final db = await _getDb();
    final rec = await getById(id);
    if (rec != null) {
      try {
        final f = File(rec.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    return db.delete('recordings', where: 'id = ?', whereArgs: [id]);
  }

  /// 获取录音总数
  Future<int> count() async {
    final db = await _getDb();
    final rows = await db.rawQuery('SELECT COUNT(*) as c FROM recordings');
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}
