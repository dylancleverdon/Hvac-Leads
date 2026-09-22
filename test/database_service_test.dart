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
}
