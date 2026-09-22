import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hvac_leads/models/company.dart';
import 'package:hvac_leads/services/license_data_service.dart';

void main() {
  // Small fixture standing in for the real bundled/geocoded asset, so this
  // test doesn't depend on assets/data/seattle_hvac_licenses.json actually
  // existing (it's produced by a separate, manually-triggered geocoding
  // workflow, not available at every test run).
  final fixture = jsonEncode([
    {
      'id': '1',
      'name': 'A Quality Heating & Air',
      'address': '123 Main St, Seattle WA 98101',
      'phone': '(206) 555-0100',
      'likelyHvac': true,
      'lat': 40.0,
      'lng': -75.0,
    },
    {
      'id': '2',
      'name': '123 Plumbing LLC',
      'address': '456 Elm St, Tacoma WA 98402',
      'phone': null,
      'likelyHvac': false,
      'lat': 41.0, // far away
      'lng': -76.0,
    },
    {
      'id': '3',
      'name': 'Nearby Comfort Systems',
      'address': '789 Oak St, Seattle WA 98101',
      'phone': '(206) 555-0200',
      'likelyHvac': true,
      'lat': 40.05,
      'lng': -75.05,
    },
  ]);

  test('withinRadius filters by distance and preserves fields', () async {
    final service = LicenseDataService(loadJson: () async => fixture);

    final results = await service.withinRadius(
      homeLat: 40.0,
      homeLng: -75.0,
      radiusMiles: 10,
    );

    expect(results, hasLength(2)); // excludes the far-away Tacoma entry
    final names = results.map((r) => r.name).toSet();
    expect(names, {'A Quality Heating & Air', 'Nearby Comfort Systems'});

    final first = results.firstWhere((r) => r.id == '1');
    expect(first.phone, '(206) 555-0100');
    expect(first.likelyHvac, isTrue);
  });

  test('toCompany maps to CompanySource.license with likelyHvac carried over',
      () async {
    final service = LicenseDataService(loadJson: () async => fixture);
    final results = await service.withinRadius(
      homeLat: 40.0,
      homeLng: -75.0,
      radiusMiles: 1,
    );

    final company = results.single.toCompany();
    expect(company.source, CompanySource.license);
    expect(company.licenseId, '1');
    expect(company.likelyHvac, isTrue);
    expect(company.osmId, isNull);
  });

  test('caches after first load (second call does not re-invoke loader)',
      () async {
    var loadCount = 0;
    final service = LicenseDataService(loadJson: () async {
      loadCount++;
      return fixture;
    });

    await service.withinRadius(homeLat: 40.0, homeLng: -75.0, radiusMiles: 1);
    await service.withinRadius(homeLat: 40.0, homeLng: -75.0, radiusMiles: 1);

    expect(loadCount, 1);
  });
}
