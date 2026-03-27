import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LibraryStorage {
  static const String _intervalKey = 'sampling_interval';
  static Database? _db;

  static Future<int> getInterval() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getInt(_intervalKey) ?? 15;
  }

  static Future<void> setInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_intervalKey, minutes);
  }

  static Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _initDB('background_logs.db');
    return _db!;
  }

  static Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            payload TEXT NOT NULL,
            is_synced INTEGER DEFAULT 0
          )
        ''');
      },
    );
  }

  static Future<void> saveLog(Map<String, dynamic> payload) async {
    final db = await _database;
    final timestamp = DateTime.now().toIso8601String();

    await db.insert('logs', {
      'timestamp': timestamp,
      'payload': jsonEncode(payload),
      'is_synced': 0,
    });

    debugPrint("💾 [SQLite] Payload saved successfully at $timestamp.");

    // Keep database from getting too large
    await db.execute('''
      DELETE FROM logs 
      WHERE id NOT IN (SELECT id FROM logs ORDER BY id DESC LIMIT 50000)
    ''');
  }

  static Future<List<Map<String, dynamic>>> getLogs() async {
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.query(
      'logs',
      orderBy: 'id DESC',
      limit: 1000,
    );
    return maps.map((row) => {...row, 'sqlite_id': row['id']}).toList();
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedLogs() async {
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.query(
      'logs',
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'id ASC',
    );
    return maps.map((row) => {...row, 'sqlite_id': row['id']}).toList();
  }

  static Future<void> markAsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE logs SET is_synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  static Future<void> clearLogs() async {
    final db = await _database;
    await db.delete('logs');
  }

  static Future<void> revertAllSynced() async {
    final db = await _database;
    await db.rawUpdate('UPDATE logs SET is_synced = 0');
  }
}
