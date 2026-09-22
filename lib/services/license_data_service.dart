import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/company.dart';
import '../utils/distance.dart';

class LicenseResult {
  final String id;
  final String name;
  final String address;
  final String? phone;
  final bool likelyHvac;
  final double lat;
  final double lng;

  const LicenseResult({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.likelyHvac,
    required this.lat,
    required this.lng,
  });

  Company toCompany() {
    final now = DateTime.now();
    return Company(
      licenseId: id,
      name: name,
      lat: lat,
      lng: lng,
      address: address,
      phone: phone,
      likelyHvac: likelyHvac,
      source: CompanySource.license,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Serves the bundled snapshot of Seattle-area business license records
/// (NAICS 238220, "Plumbing, Heating, and Air-Conditioning Contractors" —
/// see assets/data/seattle_hvac_licenses.json and README for provenance).
/// Entirely offline: no network, no rate limits, unlike OverpassService.
/// Coverage is limited to whatever the source snapshot covers (Puget Sound
/// metro) — outside that area this just contributes nothing.
class LicenseDataService {
  LicenseDataService({Future<String> Function()? loadJson})
      : _loadJson = loadJson ?? (() => rootBundle.loadString(_assetPath));

  static const _assetPath = 'assets/data/seattle_hvac_licenses.json';

  final Future<String> Function() _loadJson;
  List<LicenseResult>? _cache;

  Future<List<LicenseResult>> _loadAll() async {
    if (_cache != null) return _cache!;
    final raw = await _loadJson();
    final decoded = jsonDecode(raw) as List<dynamic>;
    _cache = decoded.map((e) {
      final map = e as Map<String, dynamic>;
      return LicenseResult(
        id: map['id'] as String,
        name: map['name'] as String,
        address: map['address'] as String,
        phone: map['phone'] as String?,
        likelyHvac: map['likelyHvac'] as bool? ?? false,
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
      );
    }).toList();
    return _cache!;
  }

  Future<List<LicenseResult>> withinRadius({
    required double homeLat,
    required double homeLng,
    required double radiusMiles,
  }) async {
    final all = await _loadAll();
    return all
        .where(
            (r) => distanceMiles(homeLat, homeLng, r.lat, r.lng) <= radiusMiles)
        .toList();
  }
}
