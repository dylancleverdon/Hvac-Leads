import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hvac_leads/services/overpass_service.dart';

void main() {
  test('parses named node/way elements and skips unnamed ones', () async {
    final responseBody = jsonEncode({
      'elements': [
        {
          'type': 'node',
          'id': 111,
          'lat': 40.01,
          'lon': -75.01,
          'tags': {
            'name': 'Test HVAC Co',
            'craft': 'hvac',
            'phone': '555-0000',
            'addr:housenumber': '12',
            'addr:street': 'Main St',
            'addr:city': 'Anytown',
            'addr:state': 'PA',
            'addr:postcode': '19000',
          },
        },
        {
          'type': 'way',
          'id': 222,
          'center': {'lat': 40.02, 'lon': -75.02},
          'tags': {'name': 'Heating Experts', 'contact:email': 'hi@heat.test'},
        },
        {
          'type': 'node',
          'id': 333,
          'lat': 40.03,
          'lon': -75.03,
          'tags': <String, dynamic>{},
        },
      ],
    });

    final client =
        MockClient((request) async => http.Response(responseBody, 200));
    final service = OverpassService(client: client);

    final results =
        await service.searchNearby(lat: 40.0, lng: -75.0, radiusMiles: 15);

    expect(results, hasLength(2));

    final first = results.firstWhere((r) => r.osmId == 'node/111');
    expect(first.name, 'Test HVAC Co');
    expect(first.phone, '555-0000');
    expect(first.address, '12 Main St, Anytown, PA, 19000');

    final second = results.firstWhere((r) => r.osmId == 'way/222');
    expect(second.name, 'Heating Experts');
    expect(second.lat, 40.02);
    expect(second.email, 'hi@heat.test');
  });

  test('name-match query clauses are case-insensitive', () async {
    String? capturedQuery;
    final client = MockClient((request) async {
      capturedQuery = request.bodyFields['data'];
      return http.Response(jsonEncode({'elements': []}), 200);
    });
    final service = OverpassService(client: client);

    await service.searchNearby(lat: 1.0, lng: 2.0, radiusMiles: 5);

    expect(capturedQuery, isNotNull);
    // Every ["name"~"..."] clause should carry the ",i" case-insensitive
    // flag, otherwise a business like "Acme Hvac" (not all-caps) is missed.
    final nameClauses =
        RegExp(r'"name"~"[^"]*"(,i)?\]').allMatches(capturedQuery!).toList();
    expect(nameClauses, isNotEmpty);
    for (final match in nameClauses) {
      expect(match.group(0), endsWith(',i]'));
    }
  });

  test(
      'throws OverpassRateLimitException after two full passes if every '
      'endpoint always returns 429', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      return http.Response('rate limited', 429, headers: {'retry-after': '0'});
    });
    final service = OverpassService(client: client, passCoolOff: Duration.zero);

    await expectLater(
      () => service.searchNearby(lat: 40.0, lng: -75.0, radiusMiles: 15),
      throwsA(isA<OverpassRateLimitException>()),
    );
    // 2 passes over all 4 configured mirrors, all 429, before giving up.
    expect(callCount, 8);
  });

  test(
      'does a second pass and recovers if every mirror was rate-limited in '
      'the first pass', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      if (callCount <= 4) {
        return http.Response('rate limited', 429,
            headers: {'retry-after': '0'});
      }
      return http.Response(
          jsonEncode({
            'elements': [
              {
                'type': 'node',
                'id': 7,
                'lat': 5.0,
                'lon': 6.0,
                'tags': {'name': 'Second Pass HVAC'},
              },
            ],
          }),
          200);
    });
    final service = OverpassService(client: client, passCoolOff: Duration.zero);

    final results =
        await service.searchNearby(lat: 5.0, lng: 6.0, radiusMiles: 10);

    expect(callCount, 5); // pass 1: 4 mirrors all 429; pass 2: 1st succeeds.
    expect(results, hasLength(1));
    expect(results.first.name, 'Second Pass HVAC');
  });

  test('recovers if an earlier endpoint 429s but a later one succeeds',
      () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      if (callCount == 1) {
        return http.Response('rate limited', 429,
            headers: {'retry-after': '0'});
      }
      return http.Response(
          jsonEncode({
            'elements': [
              {
                'type': 'node',
                'id': 42,
                'lat': 3.0,
                'lon': 4.0,
                'tags': {'name': 'Recovered HVAC'},
              },
            ],
          }),
          200);
    });
    final service = OverpassService(client: client);

    final results =
        await service.searchNearby(lat: 3.0, lng: 4.0, radiusMiles: 10);

    expect(callCount, 2);
    expect(results, hasLength(1));
    expect(results.first.name, 'Recovered HVAC');
  });

  test('falls back to the second endpoint if the first fails', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      if (callCount == 1) {
        return http.Response('server error', 500);
      }
      return http.Response(
          jsonEncode({
            'elements': [
              {
                'type': 'node',
                'id': 1,
                'lat': 1.0,
                'lon': 2.0,
                'tags': {'name': 'Fallback HVAC'},
              },
            ],
          }),
          200);
    });

    final service = OverpassService(client: client);
    final results =
        await service.searchNearby(lat: 1.0, lng: 2.0, radiusMiles: 10);

    expect(callCount, 2);
    expect(results, hasLength(1));
    expect(results.first.name, 'Fallback HVAC');
  });
}
