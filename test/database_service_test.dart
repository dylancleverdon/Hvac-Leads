import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hvac_leads/models/application_status.dart';
import 'package:hvac_leads/models/company.dart';
import 'package:hvac_leads/models/home_location.dart';
import 'package:hvac_leads/models/status_history_entry.dart';
import 'package:hvac_leads/services/database_service.dart';

Company _company({String? osmId, String name = 'Test Co'}) {
  final now = DateTime.now();
  return Company(
    osmId: osmId,
    name: name,
    lat: 40.0,
    lng: -75.0,
    source: osmId == null ? CompanySource.manual : CompanySource.osm,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseService db;

  setUp(() async {
    db = DatabaseService.instance;
    // The service is a singleton with a cached connection, so clear every
    // table between tests instead of reopening the database each time.
    final database = await db.database;
    await database.delete('status_history');
    await database.delete('companies');
    await database.delete('home_location');
  });

  test('upsertCompany inserts new and updates existing by osmId', () async {
    final id = await db
        .upsertCompany(_company(osmId: 'node/1', name: 'Original Name'));
    final updatedId =
        await db.upsertCompany(_company(osmId: 'node/1', name: 'Updated Name'));

    expect(updatedId, id);
    final all = await db.getAllCompanies();
    expect(all.where((c) => c.osmId == 'node/1'), hasLength(1));
    expect(all.firstWhere((c) => c.osmId == 'node/1').name, 'Updated Name');
  });

  test('upsertCompany inserts new and updates existing by licenseId', () async {
    final license = Company(
      licenseId: 'lic-1',
      name: 'Original License Name',
      lat: 40.0,
      lng: -75.0,
      source: CompanySource.license,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final id = await db.upsertCompany(license);
    final updatedId =
        await db.upsertCompany(license.copyWith(name: 'Updated License Name'));

    expect(updatedId, id);
    final all = await db.getAllCompanies();
    expect(all.where((c) => c.licenseId == 'lic-1'), hasLength(1));
    expect(all.firstWhere((c) => c.licenseId == 'lic-1').name,
        'Updated License Name');
  });

  test('manual companies (no osmId) never collide', () async {
    await db.upsertCompany(_company(name: 'Manual A'));
    await db.upsertCompany(_company(name: 'Manual B'));
    final all = await db.getAllCompanies();
    expect(all.where((c) => c.name.startsWith('Manual')), hasLength(2));
  });

  test('status history is recorded and ordered newest-first', () async {
    final id = await db.upsertCompany(_company(name: 'History Co'));

    await db.addStatusHistoryEntry(StatusHistoryEntry(
      companyId: id,
      status: ApplicationStatus.applied,
      timestamp: DateTime(2026, 1, 1),
    ));
    await db.addStatusHistoryEntry(StatusHistoryEntry(
      companyId: id,
      status: ApplicationStatus.interviewed,
      timestamp: DateTime(2026, 2, 1),
    ));

    final history = await db.getStatusHistory(id);
    expect(history, hasLength(2));
    expect(history.first.status, ApplicationStatus.interviewed);
  });

  test('deleteCompany removes it', () async {
    final id = await db.upsertCompany(_company(name: 'To Delete'));
    await db.deleteCompany(id);
    expect(await db.getCompanyById(id), isNull);
  });

  test('home location save/load round-trips', () async {
    expect(await db.getHomeLocation(), isNull);

    await db.saveHomeLocation(HomeLocation(
      address: '123 Main St',
      lat: 40.5,
      lng: -75.5,
      radiusMiles: 25,
      updatedAt: DateTime.now(),
    ));

    final loaded = await db.getHomeLocation();
    expect(loaded, isNotNull);
    expect(loaded!.address, '123 Main St');
    expect(loaded.radiusMiles, 25);

    // Saving again should replace, not duplicate, the single row.
    await db.saveHomeLocation(loaded.copyWith(radiusMiles: 40));
    expect((await db.getHomeLocation())!.radiusMiles, 40);
  });

  test(
      'migrating an existing v1 database to v2 adds license_id/likely_hvac '
      'without losing data', () async {
    // Regression test: SQLite's ALTER TABLE ADD COLUMN cannot add a UNIQUE
    // constraint directly ("Cannot add a UNIQUE column") — this reproduces
    // the exact upgrade path a real installed v1 app goes through, against
    // a standalone database (not the DatabaseService singleton), so it
    // doesn't interfere with the other tests' shared connection.
    final dbPath = '${Directory.systemTemp.path}/hvac_leads_migration_test.db';
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();

    final v1db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
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
        },
      ),
    );
    await v1db.insert('companies', {
      'osm_id': 'node/1',
      'name': 'Pre-existing Co',
      'lat': 1.0,
      'lng': 2.0,
      'source': 'osm',
      'status': 'notContacted',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    await v1db.close();

    final v2db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db
                .execute('ALTER TABLE companies ADD COLUMN license_id TEXT');
            await db.execute(
                'CREATE UNIQUE INDEX idx_companies_license_id ON companies(license_id)');
            await db.execute(
                'ALTER TABLE companies ADD COLUMN likely_hvac INTEGER NOT NULL DEFAULT 0');
          }
        },
      ),
    );

    final rows = await v2db.query('companies');
    expect(rows, hasLength(1));
    expect(rows.first['name'], 'Pre-existing Co');
    expect(rows.first['license_id'], isNull);
    expect(rows.first['likely_hvac'], 0);

    // New license-sourced rows insert fine post-migration, with uniqueness
    // still enforced by the index.
    await v2db.insert('companies', {
      'license_id': 'lic-1',
      'name': 'New License Co',
      'lat': 3.0,
      'lng': 4.0,
      'source': 'license',
      'status': 'notContacted',
      'likely_hvac': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    expect(await v2db.query('companies'), hasLength(2));

    await v2db.close();
    file.deleteSync();
  });
}
