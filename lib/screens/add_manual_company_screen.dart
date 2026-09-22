import 'package:flutter/material.dart';

import '../models/company.dart';
import '../services/database_service.dart';
import '../services/geocoding_service.dart';

class AddManualCompanyScreen extends StatefulWidget {
  const AddManualCompanyScreen({super.key});

  @override
  State<AddManualCompanyScreen> createState() => _AddManualCompanyScreenState();
}

class _AddManualCompanyScreenState extends State<AddManualCompanyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();
  final _notesController = TextEditingController();

  final _db = DatabaseService.instance;
  final _geocoding = GeocodingService();
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    double? lat;
    double? lng;
    String? warning;
    final address = _addressController.text.trim();

    if (address.isNotEmpty) {
      try {
        final geocoded = await _geocoding.geocode(address);
        if (geocoded != null) {
          lat = geocoded.lat;
          lng = geocoded.lng;
        }
      } catch (_) {
        // fall through to home-location fallback below
      }
    }

    if (lat == null || lng == null) {
      final home = await _db.getHomeLocation();
      if (home != null) {
        lat = home.lat;
        lng = home.lng;
        if (address.isNotEmpty) {
          warning =
              "Couldn't pin the exact address, so this was placed at your home location.";
        }
      } else {
        lat = 0;
        lng = 0;
      }
    }

    final now = DateTime.now();
    await _db.upsertCompany(Company(
      name: _nameController.text.trim(),
      lat: lat,
      lng: lng,
      address: address.isEmpty ? null : address,
      phone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      website: _websiteController.text.trim().isEmpty
          ? null
          : _websiteController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      source: CompanySource.manual,
      createdAt: now,
      updatedAt: now,
    ));

    if (!mounted) return;
    if (warning != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(warning)));
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Company')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                  labelText: 'Company name', border: OutlineInputBorder()),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Name is required'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                helperText: "We'll look up its location if you provide one",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Phone', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _websiteController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Website', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Notes', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save company'),
            ),
          ],
        ),
      ),
    );
  }
}
