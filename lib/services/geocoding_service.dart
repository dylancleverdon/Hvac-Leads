import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodeResult {
  final String displayName;
  final double lat;
  final double lng;

  const GeocodeResult({
    required this.displayName,
    required this.lat,
    required this.lng,
  });
}

/// Wraps OpenStreetMap's free Nominatim geocoder.
///
/// Nominatim's usage policy requires a descriptive User-Agent and caps
/// public-instance usage at ~1 request/second — this service enforces both
/// so the app stays a good citizen of a shared free resource.
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://nominatim.openstreetmap.org';
  static const _userAgent = 'HvacLeads/1.0 (personal job-hunt tracker app)';
  static const _minInterval = Duration(seconds: 1);

  final http.Client _client;
  DateTime? _lastRequestAt;

  Future<void> _throttle() async {
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < _minInterval) {
        await Future.delayed(_minInterval - elapsed);
      }
    }
    _lastRequestAt = DateTime.now();
  }

  /// Turns a free-text address into coordinates. Returns null if nothing
  /// matched.
  Future<GeocodeResult?> geocode(String address) async {
    await _throttle();
    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'q': address,
      'format': 'json',
      'limit': '1',
    });
    final response =
        await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) {
      throw Exception('Geocoding failed (${response.statusCode})');
    }
    final results = jsonDecode(response.body) as List<dynamic>;
    if (results.isEmpty) return null;
    final first = results.first as Map<String, dynamic>;
    return GeocodeResult(
      displayName: first['display_name'] as String,
      lat: double.parse(first['lat'] as String),
      lng: double.parse(first['lon'] as String),
    );
  }

  /// Turns coordinates back into a human-readable address (used for "use my
  /// current GPS location").
  Future<String> reverseGeocode(double lat, double lng) async {
    await _throttle();
    final uri = Uri.parse('$_baseUrl/reverse').replace(queryParameters: {
      'lat': lat.toString(),
      'lon': lng.toString(),
      'format': 'json',
    });
    final response =
        await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) {
      throw Exception('Reverse geocoding failed (${response.statusCode})');
    }
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    return (result['display_name'] as String?) ?? '$lat, $lng';
  }
}
