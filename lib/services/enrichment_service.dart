import 'package:http/http.dart' as http;

class EnrichmentResult {
  final String? phone;
  final String? email;

  const EnrichmentResult({this.phone, this.email});

  bool get isEmpty => phone == null && email == null;
}

/// Best-effort contact-info lookup: fetches a company's homepage and scans
/// the raw HTML for `mailto:`/`tel:` links (and a loose phone-number
/// pattern as a fallback). This is user-triggered per company from the
/// Company Detail screen — never automatic — since it's a network request
/// to a third-party site.
class EnrichmentService {
  EnrichmentService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final _mailtoRegex = RegExp(
      r'mailto:([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})',
      caseSensitive: false);
  static final _telRegex =
      RegExp(r'tel:([+0-9()\-.\s]{7,20})', caseSensitive: false);
  static final _phoneTextRegex = RegExp(r'\(?\d{3}\)?[\s.\-]\d{3}[\s.\-]\d{4}');

  Future<EnrichmentResult> lookup(String website) async {
    var url = website.trim();
    if (!url.startsWith('http')) url = 'https://$url';

    final response = await _client.get(Uri.parse(url), headers: {
      'User-Agent': 'HvacLeads/1.0'
    }).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Could not load $url (${response.statusCode})');
    }

    final body = response.body;
    final email = _mailtoRegex.firstMatch(body)?.group(1);
    final phone = _telRegex.firstMatch(body)?.group(1)?.trim() ??
        _phoneTextRegex.firstMatch(body)?.group(0);

    return EnrichmentResult(phone: phone, email: email);
  }
}
