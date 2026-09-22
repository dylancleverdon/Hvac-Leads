import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/home_location.dart';
import '../services/database_service.dart';
import '../services/geocoding_service.dart';
import '../services/update_service.dart';
import 'export_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _addressController = TextEditingController();
  final _geocoding = GeocodingService();
  final _db = DatabaseService.instance;
  final _updateService = UpdateService();

  double _radiusMiles = 15;
  double? _lat;
  double? _lng;
  bool _busy = false;
  bool _checkingForUpdate = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final home = await _db.getHomeLocation();
    if (home != null && mounted) {
      setState(() {
        _addressController.text = home.address;
        _lat = home.lat;
        _lng = home.lng;
        _radiusMiles = home.radiusMiles;
      });
    }
  }

  Future<void> _geocodeAndSave() async {
    if (_addressController.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _geocoding.geocode(_addressController.text.trim());
      if (result == null) {
        setState(() =>
            _error = "Couldn't find that address. Try adding city/state.");
        return;
      }
      await _db.saveHomeLocation(HomeLocation(
        address: result.displayName,
        lat: result.lat,
        lng: result.lng,
        radiusMiles: _radiusMiles,
        updatedAt: DateTime.now(),
      ));
      setState(() {
        _addressController.text = result.displayName;
        _lat = result.lat;
        _lng = result.lng;
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Home location saved')));
      }
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _error = 'Location permission denied.');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      final address = await _geocoding.reverseGeocode(
          position.latitude, position.longitude);
      await _db.saveHomeLocation(HomeLocation(
        address: address,
        lat: position.latitude,
        lng: position.longitude,
        radiusMiles: _radiusMiles,
        updatedAt: DateTime.now(),
      ));
      setState(() {
        _addressController.text = address;
        _lat = position.latitude;
        _lng = position.longitude;
      });
    } catch (e) {
      setState(() => _error = 'Could not get your location: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveRadius(double value) async {
    setState(() => _radiusMiles = value);
    if (_lat != null && _lng != null) {
      await _db.saveHomeLocation(HomeLocation(
        address: _addressController.text,
        lat: _lat!,
        lng: _lng!,
        radiusMiles: value,
        updatedAt: DateTime.now(),
      ));
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checkingForUpdate = true);
    try {
      final update = await _updateService.checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("You're on the latest version")));
      } else {
        await _updateService.showUpdateDialog(context, update);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update check failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _checkingForUpdate = false);
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Home base', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(
              labelText: 'Home address',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _geocodeAndSave,
                  child: const Text('Save address'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _useCurrentLocation,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Use GPS'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 24),
          Text('Search radius: ${_radiusMiles.round()} mi',
              style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _radiusMiles,
            min: 5,
            max: 60,
            divisions: 11,
            label: '${_radiusMiles.round()} mi',
            onChanged: (value) => setState(() => _radiusMiles = value),
            onChangeEnd: _saveRadius,
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Export companies'),
            subtitle: const Text('Back up your data as CSV or JSON'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExportScreen()),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: _checkingForUpdate
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update),
            title: const Text('Check for updates'),
            onTap: _checkingForUpdate ? null : _checkForUpdate,
          ),
        ],
      ),
    );
  }
}
