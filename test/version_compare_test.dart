import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_leads/utils/version_compare.dart';

void main() {
  group('compareVersions', () {
    test('equal versions', () {
      expect(compareVersions('1.2.0', '1.2.0'), 0);
    });

    test('treats missing segments as zero', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
    });

    test('strips leading v', () {
      expect(compareVersions('v1.3.0', '1.2.9'), greaterThan(0));
    });

    test('numeric comparison, not lexical', () {
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
    });

    test('strips build metadata', () {
      expect(compareVersions('1.2.0+5', '1.2.0+42'), 0);
    });
  });

  group('isNewerVersion', () {
    test('candidate ahead of current', () {
      expect(isNewerVersion(current: '1.0.0', candidate: 'v1.0.1'), isTrue);
    });

    test('candidate equal to current', () {
      expect(isNewerVersion(current: '1.0.0', candidate: 'v1.0.0'), isFalse);
    });

    test('candidate behind current', () {
      expect(isNewerVersion(current: '2.0.0', candidate: 'v1.9.9'), isFalse);
    });
  });
}
