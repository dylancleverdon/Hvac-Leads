import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/company.dart';

enum ExportFormat { csv, json }

/// Serializes saved companies to a file for a manual backup/export, since
/// there's no cloud sync in this app — the phone's local database is the
/// only copy otherwise.
class ExportService {
  static const _csvHeaders = [
    'name',
    'status',
    'phone',
    'email',
    'website',
    'address',
    'lat',
    'lng',
    'source',
    'notes',
    'created_at',
    'updated_at',
  ];

  Future<File> exportToFile(
      List<Company> companies, ExportFormat format) async {
    final dir = await getTemporaryDirectory();
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final extension = format == ExportFormat.csv ? 'csv' : 'json';
    final file = File('${dir.path}/hvac_leads_export_$timestamp.$extension');
    final content =
        format == ExportFormat.csv ? _toCsv(companies) : _toJson(companies);
    return file.writeAsString(content);
  }

  String _toCsv(List<Company> companies) {
    final buffer = StringBuffer();
    buffer.writeln(_csvHeaders.map(_csvField).join(','));
    for (final c in companies) {
      buffer.writeln([
        c.name,
        c.status.label,
        c.phone ?? '',
        c.email ?? '',
        c.website ?? '',
        c.address ?? '',
        c.lat.toString(),
        c.lng.toString(),
        c.source.name,
        c.notes ?? '',
        c.createdAt.toIso8601String(),
        c.updatedAt.toIso8601String(),
      ].map(_csvField).join(','));
    }
    return buffer.toString();
  }

  String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  String _toJson(List<Company> companies) {
    final list = companies
        .map((c) => {
              'name': c.name,
              'status': c.status.label,
              'phone': c.phone,
              'email': c.email,
              'website': c.website,
              'address': c.address,
              'lat': c.lat,
              'lng': c.lng,
              'source': c.source.name,
              'notes': c.notes,
              'created_at': c.createdAt.toIso8601String(),
              'updated_at': c.updatedAt.toIso8601String(),
            })
        .toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }
}
