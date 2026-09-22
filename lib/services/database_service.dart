import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/company.dart';
import '../models/home_location.dart';
import '../models/status_history_entry.dart';

/// Owns the single on-device SQLite database. There is no backend and no
/// sync — this file on the phone is the only copy of the user's data (see
/// ExportService for a manual backup path).
class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'hvac_leads.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE companies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            osm_id TEXT UNIQUE,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            address TEXT,
            phone TEXT,
            email TEXT,
            website TEXT,
            source TEXT NOT NULL,
            status TEXT NOT NULL,
            notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE status_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id INTEGER NOT NULL,
            status TEXT NOT NULL,
            note TEXT,
            timestamp TEXT NOT NULL,
            FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE home_location (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            address TEXT NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            radius_miles REAL NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // --- Companies ---------------------------------------------------------

  Future<List<Company>> getAllCompanies() async {
    final db = await database;
    final rows = await db.query('companies', orderBy: 'name COLLATE NOCASE');
    return rows.map(Company.fromMap).toList();
  }

  Future<Company?> getCompanyById(int id) async {
    final db = await database;
    final rows = await db.query('companies', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Company.fromMap(rows.first);
  }

  Future<Set<String>> getExistingOsmIds() async {
    final db = await database;
    final rows = await db.query('companies',
        columns: ['osm_id'], where: 'osm_id IS NOT NULL');
    return rows.map((r) => r['osm_id'] as String).toSet();
  }

  /// Inserts a new company, or updates an existing one with the same osmId.
  Future<int> upsertCompany(Company company) async {
    final db = await database;
    if (company.osmId != null) {
      final existing = await db.query('companies',
          where: 'osm_id = ?', whereArgs: [company.osmId], limit: 1);
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        await db.update('companies', company.toMap()..remove('id'),
            where: 'id = ?', whereArgs: [id]);
        return id;
      }
    }
    return db.insert('companies', company.toMap()..remove('id'));
  }

  Future<void> updateCompany(Company company) async {
    final db = await database;
    await db.update('companies', company.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [company.id]);
  }

  Future<void> deleteCompany(int id) async {
    final db = await database;
    await db.delete('companies', where: 'id = ?', whereArgs: [id]);
  }

  // --- Status history ------------------------------------------------------

  Future<void> addStatusHistoryEntry(StatusHistoryEntry entry) async {
    final db = await database;
    await db.insert('status_history', entry.toMap()..remove('id'));
  }

  Future<List<StatusHistoryEntry>> getStatusHistory(int companyId) async {
    final db = await database;
    final rows = await db.query(
      'status_history',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'timestamp DESC',
    );
    return rows.map(StatusHistoryEntry.fromMap).toList();
  }

  // --- Home location ---------------------------------------------------

  Future<HomeLocation?> getHomeLocation() async {
    final db = await database;
    final rows = await db.query('home_location', where: 'id = 1');
    if (rows.isEmpty) return null;
    return HomeLocation.fromMap(rows.first);
  }

  Future<void> saveHomeLocation(HomeLocation location) async {
    final db = await database;
    await db.insert(
      'home_location',
      location.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
