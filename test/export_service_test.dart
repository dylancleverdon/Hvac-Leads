import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:hvac_leads/models/application_status.dart';
import 'package:hvac_leads/models/company.dart';
import 'package:hvac_leads/services/export_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  final now = DateTime.parse('2026-01-15T10:00:00.000');
  final companies = [
    Company(
      id: 1,
      name: 'Acme, HVAC "Pros"',
      lat: 40.0,
      lng: -75.0,
      phone: '555-1234',
      email: 'jobs@acme.test',
      status: ApplicationStatus.applied,
      source: CompanySource.osm,
      createdAt: now,
      updatedAt: now,
    ),
    Company(
      id: 2,
      name: 'Cozy Heating',
      lat: 40.1,
      lng: -75.1,
      source: CompanySource.manual,
      createdAt: now,
      updatedAt: now,
    ),
  ];

  test('CSV export escapes commas and quotes, includes both rows', () async {
    final file =
        await ExportService().exportToFile(companies, ExportFormat.csv);
    final content = await file.readAsString();
    final lines = const LineSplitter().convert(content.trim());

    expect(lines.length, 3); // header + 2 rows
    expect(lines[0], startsWith('name,status,'));
    expect(lines[1], contains('"Acme, HVAC ""Pros"""'));
    expect(lines[2], contains('Cozy Heating'));

    await file.delete();
  });

  test('JSON export round-trips company fields', () async {
    final file =
        await ExportService().exportToFile(companies, ExportFormat.json);
    final content = await file.readAsString();
    final decoded = jsonDecode(content) as List<dynamic>;

    expect(decoded, hasLength(2));
    expect(decoded[0]['name'], 'Acme, HVAC "Pros"');
    expect(decoded[0]['status'], 'Applied');
    expect(decoded[1]['phone'], isNull);

    await file.delete();
  });
}
