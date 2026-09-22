class HomeLocation {
  final String address;
  final double lat;
  final double lng;
  final double radiusMiles;
  final DateTime updatedAt;

  const HomeLocation({
    required this.address,
    required this.lat,
    required this.lng,
    this.radiusMiles = 15,
    required this.updatedAt,
  });

  HomeLocation copyWith({
    String? address,
    double? lat,
    double? lng,
    double? radiusMiles,
    DateTime? updatedAt,
  }) {
    return HomeLocation(
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusMiles: radiusMiles ?? this.radiusMiles,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': 1,
      'address': address,
      'lat': lat,
      'lng': lng,
      'radius_miles': radiusMiles,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory HomeLocation.fromMap(Map<String, Object?> map) {
    return HomeLocation(
      address: map['address'] as String,
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      radiusMiles: (map['radius_miles'] as num).toDouble(),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
