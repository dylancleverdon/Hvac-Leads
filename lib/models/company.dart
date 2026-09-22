import 'application_status.dart';

enum CompanySource { osm, manual, license }

class Company {
  final int? id;
  final String? osmId;
  final String? licenseId;
  final String name;
  final double lat;
  final double lng;
  final String? address;
  final String? phone;
  final String? email;
  final String? website;
  final CompanySource source;
  final ApplicationStatus status;
  final String? notes;

  /// Only meaningful for [CompanySource.license]: whether the business
  /// name self-identifies as HVAC (vs. just carrying the combined
  /// "Plumbing, Heating, and Air-Conditioning Contractors" license
  /// category, which includes plain plumbers too).
  final bool likelyHvac;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Company({
    this.id,
    this.osmId,
    this.licenseId,
    required this.name,
    required this.lat,
    required this.lng,
    this.address,
    this.phone,
    this.email,
    this.website,
    this.source = CompanySource.manual,
    this.status = ApplicationStatus.notContacted,
    this.notes,
    this.likelyHvac = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Company copyWith({
    int? id,
    String? osmId,
    String? licenseId,
    String? name,
    double? lat,
    double? lng,
    String? address,
    String? phone,
    String? email,
    String? website,
    CompanySource? source,
    ApplicationStatus? status,
    String? notes,
    bool? likelyHvac,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Company(
      id: id ?? this.id,
      osmId: osmId ?? this.osmId,
      licenseId: licenseId ?? this.licenseId,
      name: name ?? this.name,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      website: website ?? this.website,
      source: source ?? this.source,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      likelyHvac: likelyHvac ?? this.likelyHvac,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'osm_id': osmId,
      'license_id': licenseId,
      'name': name,
      'lat': lat,
      'lng': lng,
      'address': address,
      'phone': phone,
      'email': email,
      'website': website,
      'source': source.name,
      'status': status.dbValue,
      'notes': notes,
      'likely_hvac': likelyHvac ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Company.fromMap(Map<String, Object?> map) {
    return Company(
      id: map['id'] as int?,
      osmId: map['osm_id'] as String?,
      licenseId: map['license_id'] as String?,
      name: map['name'] as String,
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      address: map['address'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      website: map['website'] as String?,
      source: CompanySource.values.firstWhere(
        (s) => s.name == map['source'],
        orElse: () => CompanySource.manual,
      ),
      status: ApplicationStatus.fromDbValue(map['status'] as String),
      notes: map['notes'] as String?,
      likelyHvac: (map['likely_hvac'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
