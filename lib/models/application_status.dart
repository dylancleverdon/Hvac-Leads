/// Where a company stands in the user's job hunt.
enum ApplicationStatus {
  notContacted,
  researching,
  applied,
  interviewScheduled,
  interviewed,
  offer,
  rejected,
  notInterested;

  String get label {
    switch (this) {
      case ApplicationStatus.notContacted:
        return 'Not Contacted';
      case ApplicationStatus.researching:
        return 'Researching';
      case ApplicationStatus.applied:
        return 'Applied';
      case ApplicationStatus.interviewScheduled:
        return 'Interview Scheduled';
      case ApplicationStatus.interviewed:
        return 'Interviewed';
      case ApplicationStatus.offer:
        return 'Offer';
      case ApplicationStatus.rejected:
        return 'Rejected';
      case ApplicationStatus.notInterested:
        return 'Not Interested';
    }
  }

  /// Stored in SQLite as plain text so the schema stays human-readable.
  String get dbValue => name;

  static ApplicationStatus fromDbValue(String value) {
    return ApplicationStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ApplicationStatus.notContacted,
    );
  }
}
