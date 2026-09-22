import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/database_service.dart';
import '../services/export_service.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final _db = DatabaseService.instance;
  final _exportService = ExportService();
  bool _busy = false;

  Future<void> _export(ExportFormat format) async {
    setState(() => _busy = true);
    try {
      final companies = await _db.getAllCompanies();
      if (companies.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No companies to export yet')));
        }
        return;
      }
      final file = await _exportService.exportToFile(companies, format);
      await Share.shareXFiles([XFile(file.path)],
          text: 'HVAC Leads export (${companies.length} companies)');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Export every saved company (contact info, status, and notes) '
              'to a file you can share, print, or keep as a backup. There is '
              'no cloud sync, so this is your safety net if you lose the phone.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : () => _export(ExportFormat.csv),
              icon: const Icon(Icons.table_chart),
              label: const Text('Export as CSV'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _export(ExportFormat.json),
              icon: const Icon(Icons.data_object),
              label: const Text('Export as JSON'),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}
