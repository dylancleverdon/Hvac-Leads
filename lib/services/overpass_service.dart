import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/company.dart';

class OverpassResult {
  final String osmId;
  final String name;
  final double lat;
  final double lng;
  final String? address;
  final String? phone;
  final String? email;
  final String? website;

  const OverpassResult({
    required this.osmId,
    required this.name,
    required this.lat,
    required this.lng,
    this.address,
    this.phone,
    this.email,
    this.website,
  });

  Company toCompany() {
    final now = DateTime.now();
    return Company(
      osmId: osmId,
      name: name,
      lat: lat,
      lng: lng,
      address: address,
      phone: phone,
      email: email,
      website: website,
      source: CompanySource.osm,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Searches OpenStreetMap for HVAC-related businesses near a point using the
/// free, keyless Overpass API.
///
/// OSM's tagging for HVAC contractors is community-maintained, so this casts
/// a slightly wider net than just `craft=hvac`: it also matches businesses
/// whose name self-identifies as heating/cooling/HVAC, to make up for
/// inconsistent tagging. Coverage will still vary by area — that's why the
/// app also supports adding companies manually.
class OverpassService {
  OverpassService({http.Client? client}) : _client = client ?? http.Client();

  // Public Overpass mirrors, tried in order, since the shared instances
  // occasionally rate-limit or go down.
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  final http.Client _client;

  String _buildQuery(double lat, double lng, double radiusMeters) {
    final around = 'around:${radiusMeters.round()},$lat,$lng';
    const nameRegex = 'HVAC|[Hh]eating|[Aa]ir[- ][Cc]ondition';
    return '''
[out:json][timeout:25];
(
  node["craft"="hvac"]($around);
  way["craft"="hvac"]($around);
  node["name"~"$nameRegex"]($around);
  way["name"~"$nameRegex"]($around);
);
out center tags;
''';
  }

  Future<List<OverpassResult>> searchNearby({
    required double lat,
    required double lng,
    required double radiusMiles,
  }) async {
    final radiusMeters = radiusMiles * 1609.34;
    final query = _buildQuery(lat, lng, radiusMeters);

    Object? lastError;
    for (final endpoint in _endpoints) {
      try {
        final response = await _client.post(Uri.parse(endpoint),
            body: {'data': query}).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw Exception('Overpass returned ${response.statusCode}');
        }
        return _parse(response.body);
      } catch (e) {
        lastError = e;
        continue;
      }
    }
    throw Exception('All Overpass endpoints failed: $lastError');
  }

  List<OverpassResult> _parse(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final elements = (decoded['elements'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    final results = <OverpassResult>[];
    final seenIds = <String>{};

    for (final el in elements) {
      final type = el['type'] as String;
      final id = el['id'];
      final osmId = '$type/$id';
      if (!seenIds.add(osmId)) continue;

      double? lat = (el['lat'] as num?)?.toDouble();
      double? lng = (el['lon'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        final center = el['center'] as Map<String, dynamic>?;
        lat = (center?['lat'] as num?)?.toDouble();
        lng = (center?['lon'] as num?)?.toDouble();
      }
      if (lat == null || lng == null) continue;

      final tags = (el['tags'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString()));
      final name = tags['name'];
      if (name == null || name.trim().isEmpty) continue;

      results.add(OverpassResult(
        osmId: osmId,
        name: name,
        lat: lat,
        lng: lng,
        address: _buildAddress(tags),
        phone: tags['contact:phone'] ?? tags['phone'],
        email: tags['contact:email'] ?? tags['email'],
        website: tags['contact:website'] ?? tags['website'],
      ));
    }
    return results;
  }

  String? _buildAddress(Map<String, String> tags) {
    final parts = [
      if (tags['addr:housenumber'] != null && tags['addr:street'] != null)
        '${tags['addr:housenumber']} ${tags['addr:street']}'
      else
        tags['addr:street'],
      tags['addr:city'],
      tags['addr:state'],
      tags['addr:postcode'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }
}
