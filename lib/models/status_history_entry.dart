import 'application_status.dart';

class StatusHistoryEntry {
  final int? id;
  final int companyId;
  final ApplicationStatus status;
  final String? note;
  final DateTime timestamp;

  const StatusHistoryEntry({
    this.id,
    required this.companyId,
    required this.status,
    this.note,
    required this.timestamp,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'status': status.dbValue,
      'note': note,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory StatusHistoryEntry.fromMap(Map<String, Object?> map) {
    return StatusHistoryEntry(
      id: map['id'] as int?,
      companyId: map['company_id'] as int,
      status: ApplicationStatus.fromDbValue(map['status'] as String),
      note: map['note'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
