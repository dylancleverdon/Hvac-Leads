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

/// Thrown when every configured Overpass mirror responded 429 (rate
/// limited) — distinct from a generic failure so the UI can show something
/// actionable instead of a raw exception string.
class OverpassRateLimitException implements Exception {
  const OverpassRateLimitException();

  @override
  String toString() =>
      "OpenStreetMap's free search is busy right now — wait a bit and try again.";
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
  OverpassService({http.Client? client, Duration? passCoolOff})
      : _client = client ?? http.Client(),
        _passCoolOff = passCoolOff ?? const Duration(seconds: 8);

  // Public Overpass mirrors, tried in order, since the shared instances
  // occasionally rate-limit or go down. Only list hosts actually verified
  // to resolve/respond — a bogus hostname here fails the whole search with
  // a DNS error, which is worse than having fewer mirrors. Verified via a
  // CI runner with normal internet access (this sandbox's own network
  // policy blocks reaching Overpass directly to check).
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  final http.Client _client;
  final Duration _passCoolOff;

  String _buildQuery(double lat, double lng, double radiusMeters) {
    final around = 'around:${radiusMeters.round()},$lat,$lng';
    // Case-insensitive (the ",i" flag) since Overpass regex matching is
    // case-sensitive by default and business names aren't consistently
    // capitalized ("Acme Hvac", "ABC HEATING", etc).
    const nameRegex =
        'HVAC|heating|cooling|furnace|duct|air[- ]?condition|refrigerat';
    return '''
[out:json][timeout:25];
(
  node["craft"="hvac"]($around);
  way["craft"="hvac"]($around);
  node["name"~"$nameRegex",i]($around);
  way["name"~"$nameRegex",i]($around);
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

    // Up to two full passes over the mirror list. A fair-use rate limit is
    // often per-minute-ish, so if *every* mirror 429s in a pass, one longer
    // wait before trying them all again is more likely to actually clear
    // it than just hopping between mirrors that are all currently limited.
    const maxPasses = 2;
    Object? lastError;
    var hitOtherFailure = false;

    for (var pass = 1; pass <= maxPasses; pass++) {
      var allRateLimitedThisPass = true;

      for (final endpoint in _endpoints) {
        try {
          final response = await _client.post(Uri.parse(endpoint),
              body: {'data': query}).timeout(const Duration(seconds: 30));

          if (response.statusCode == 429) {
            lastError = Exception('Overpass returned 429');
            await _waitAfterRateLimit(response);
            continue;
          }
          allRateLimitedThisPass = false;
          if (response.statusCode != 200) {
            throw Exception('Overpass returned ${response.statusCode}');
          }
          return _parse(response.body);
        } catch (e) {
          allRateLimitedThisPass = false;
          hitOtherFailure = true;
          lastError = e;
          continue;
        }
      }

      if (allRateLimitedThisPass && pass < maxPasses) {
        await Future.delayed(_passCoolOff);
        continue;
      }
      break;
    }

    // Every attempt across every pass was specifically a 429 (no real
    // errors) — that's a distinct, actionable condition worth surfacing
    // differently than "something went wrong".
    if (!hitOtherFailure) {
      throw const OverpassRateLimitException();
    }
    throw Exception('All Overpass endpoints failed: $lastError');
  }

  /// Waits briefly before trying the next mirror after a 429, respecting
  /// the server's `Retry-After` header when it provides one (capped so the
  /// UI never stalls for long — moving to a different mirror is usually
  /// faster than waiting out one instance's limit anyway).
  Future<void> _waitAfterRateLimit(http.Response response) async {
    var waitSeconds = 1.5;
    final retryAfter = response.headers['retry-after'];
    final parsed = retryAfter != null ? int.tryParse(retryAfter) : null;
    if (parsed != null) {
      waitSeconds = parsed.clamp(0, 5).toDouble();
    }
    await Future.delayed(Duration(milliseconds: (waitSeconds * 1000).round()));
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
