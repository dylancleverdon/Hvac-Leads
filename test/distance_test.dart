import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_leads/utils/distance.dart';

void main() {
  test('same point is zero distance', () {
    expect(distanceMiles(40.0, -75.0, 40.0, -75.0), closeTo(0, 0.0001));
  });

  test('roughly matches known distance (NYC to Philadelphia, ~80 mi)', () {
    final miles = distanceMiles(40.7128, -74.0060, 39.9526, -75.1652);
    expect(miles, inInclusiveRange(75, 85));
  });
}
