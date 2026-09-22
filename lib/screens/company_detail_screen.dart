import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/application_status.dart';
import '../models/company.dart';
import '../models/status_history_entry.dart';
import '../services/database_service.dart';
import '../services/enrichment_service.dart';

class CompanyDetailScreen extends StatefulWidget {
  final int companyId;

  const CompanyDetailScreen({super.key, required this.companyId});

  @override
  State<CompanyDetailScreen> createState() => _CompanyDetailScreenState();
}

class _CompanyDetailScreenState extends State<CompanyDetailScreen> {
  final _db = DatabaseService.instance;
  final _enrichment = EnrichmentService();

  Company? _company;
  List<StatusHistoryEntry> _history = [];
  bool _loading = true;
  bool _dirty = false;
  bool _enriching = false;

  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _websiteController;
  late TextEditingController _addressController;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _emailController = TextEditingController();
    _websiteController = TextEditingController();
    _addressController = TextEditingController();
    _notesController = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final company = await _db.getCompanyById(widget.companyId);
    final history = await _db.getStatusHistory(widget.companyId);
    if (company == null || !mounted) return;
    setState(() {
      _company = company;
      _history = history;
      _phoneController.text = company.phone ?? '';
      _emailController.text = company.email ?? '';
      _websiteController.text = company.website ?? '';
      _addressController.text = company.address ?? '';
      _notesController.text = company.notes ?? '';
      _loading = false;
      _dirty = false;
    });
  }

  Future<void> _saveFields() async {
    final company = _company;
    if (company == null) return;
    final updated = company.copyWith(
      phone: _emptyToNull(_phoneController.text),
      email: _emptyToNull(_emailController.text),
      website: _emptyToNull(_websiteController.text),
      address: _emptyToNull(_addressController.text),
      notes: _emptyToNull(_notesController.text),
      updatedAt: DateTime.now(),
    );
    await _db.updateCompany(updated);
    setState(() {
      _company = updated;
      _dirty = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  String? _emptyToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();

  Future<void> _changeStatus(ApplicationStatus newStatus) async {
    final company = _company;
    if (company == null || newStatus == company.status) return;

    final note = await showDialog<String>(
      context: context,
      builder: (context) => _StatusNoteDialog(newStatusLabel: newStatus.label),
    );
    if (note == null) return; // user cancelled

    final now = DateTime.now();
    final updated = company.copyWith(status: newStatus, updatedAt: now);
    await _db.updateCompany(updated);
    await _db.addStatusHistoryEntry(StatusHistoryEntry(
      companyId: company.id!,
      status: newStatus,
      note: note.trim().isEmpty ? null : note.trim(),
      timestamp: now,
    ));
    await _load();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete company?'),
        content: Text(
            'This removes ${_company?.name} and its history. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && _company?.id != null) {
      await _db.deleteCompany(_company!.id!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _call() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _email() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    await launchUrl(Uri(scheme: 'mailto', path: email));
  }

  Future<void> _findContactInfo() async {
    final website = _websiteController.text.trim();
    if (website.isEmpty) return;
    setState(() => _enriching = true);
    try {
      final result = await _enrichment.lookup(website);
      if (result.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No contact info found on that site')));
        }
        return;
      }
      setState(() {
        if (result.phone != null && _phoneController.text.trim().isEmpty) {
          _phoneController.text = result.phone!;
          _dirty = true;
        }
        if (result.email != null && _emailController.text.trim().isEmpty) {
          _emailController.text = result.email!;
          _dirty = true;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lookup failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _enriching = false);
    }
  }

  Future<void> _openWebsite() async {
    var url = _websiteController.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http')) url = 'https://$url';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _company == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final company = _company!;

    return Scaffold(
      appBar: AppBar(
        title: Text(company.name),
        actions: [
          if (_dirty)
            IconButton(icon: const Icon(Icons.save), onPressed: _saveFields),
          IconButton(
              icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<ApplicationStatus>(
            value: company.status,
            decoration: const InputDecoration(
                labelText: 'Status', border: OutlineInputBorder()),
            items: [
              for (final s in ApplicationStatus.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (value) {
              if (value != null) _changeStatus(value);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _phoneController.text.trim().isEmpty ? null : _call,
                  icon: const Icon(Icons.call),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _emailController.text.trim().isEmpty ? null : _email,
                  icon: const Icon(Icons.email),
                  label: const Text('Email'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _websiteController.text.trim().isEmpty
                      ? null
                      : _openWebsite,
                  icon: const Icon(Icons.language),
                  label: const Text('Site'),
                ),
              ),
            ],
          ),
          if (_websiteController.text.trim().isNotEmpty &&
              (_phoneController.text.trim().isEmpty ||
                  _emailController.text.trim().isEmpty)) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _enriching ? null : _findContactInfo,
              icon: _enriching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.travel_explore),
              label: Text(_enriching
                  ? 'Looking…'
                  : 'Try to find phone/email from website'),
            ),
          ],
          const SizedBox(height: 24),
          _field(_phoneController, 'Phone', TextInputType.phone),
          _field(_emailController, 'Email', TextInputType.emailAddress),
          _field(_websiteController, 'Website', TextInputType.url),
          _field(_addressController, 'Address', TextInputType.streetAddress),
          _field(_notesController, 'Notes', TextInputType.multiline,
              maxLines: 4),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _dirty ? _saveFields : null,
            child: const Text('Save changes'),
          ),
          const Divider(height: 40),
          Text('History', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            const Text('No status changes yet.')
          else
            for (final entry in _history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text(entry.status.label),
                subtitle: entry.note != null ? Text(entry.note!) : null,
                trailing: Text(
                  '${entry.timestamp.month}/${entry.timestamp.day}/${entry.timestamp.year}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
        ],
      ),
    );
  }

  Widget _field(
      TextEditingController controller, String label, TextInputType type,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: type,
        maxLines: maxLines,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        onChanged: (_) => setState(() => _dirty = true),
      ),
    );
  }
}

class _StatusNoteDialog extends StatefulWidget {
  final String newStatusLabel;

  const _StatusNoteDialog({required this.newStatusLabel});

  @override
  State<_StatusNoteDialog> createState() => _StatusNoteDialogState();
}

class _StatusNoteDialogState extends State<_StatusNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Mark as "${widget.newStatusLabel}"'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Note (optional)'),
        maxLines: 3,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
