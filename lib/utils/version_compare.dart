/// Compares two dotted version strings (e.g. "1.2.0" vs "v1.10.0").
///
/// Returns a negative number if [a] < [b], zero if equal, positive if
/// [a] > [b]. Leading "v"/"V" prefixes and any "+build" metadata suffix are
/// ignored. Missing/non-numeric segments are treated as 0, so "1.2" and
/// "1.2.0" compare equal.
int compareVersions(String a, String b) {
  final partsA = _parse(a);
  final partsB = _parse(b);
  final length = partsA.length > partsB.length ? partsA.length : partsB.length;
  for (var i = 0; i < length; i++) {
    final valA = i < partsA.length ? partsA[i] : 0;
    final valB = i < partsB.length ? partsB[i] : 0;
    if (valA != valB) return valA - valB;
  }
  return 0;
}

bool isNewerVersion({required String current, required String candidate}) {
  return compareVersions(candidate, current) > 0;
}

List<int> _parse(String version) {
  var v = version.trim();
  if (v.startsWith('v') || v.startsWith('V')) {
    v = v.substring(1);
  }
  final plusIndex = v.indexOf('+');
  if (plusIndex != -1) {
    v = v.substring(0, plusIndex);
  }
  return v.split('.').map((segment) {
    return int.tryParse(segment.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }).toList();
}
