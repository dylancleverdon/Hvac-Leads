import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../models/home_location.dart';
import '../services/database_service.dart';
import '../services/overpass_service.dart';
import '../utils/distance.dart';
import 'settings_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _db = DatabaseService.instance;
  final _overpass = OverpassService();
  final _mapController = MapController();

  HomeLocation? _home;
  List<OverpassResult> _results = [];
  Set<String> _savedOsmIds = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHome();
  }

  Future<void> _loadHome() async {
    final home = await _db.getHomeLocation();
    if (mounted) setState(() => _home = home);
  }

  Future<void> _search() async {
    if (_home == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _overpass.searchNearby(
        lat: _home!.lat,
        lng: _home!.lng,
        radiusMiles: _home!.radiusMiles,
      );
      final saved = await _db.getExistingOsmIds();
      results.sort((a, b) => distanceMiles(_home!.lat, _home!.lng, a.lat, a.lng)
          .compareTo(distanceMiles(_home!.lat, _home!.lng, b.lat, b.lng)));
      setState(() {
        _results = results;
        _savedOsmIds = saved;
      });
      if (results.isNotEmpty) {
        _mapController.move(ll.LatLng(_home!.lat, _home!.lng), 11);
      }
    } catch (e) {
      setState(() => _error = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(OverpassResult result) async {
    await _db.upsertCompany(result.toCompany());
    setState(() => _savedOsmIds = {..._savedOsmIds, result.osmId});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${result.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_home == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Search Nearby')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Set your home address first so we know where to search from.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                    _loadHome();
                  },
                  child: const Text('Go to Settings'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final home = _home!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Within ${home.radiusMiles.round()} mi of home'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
                _loadHome();
              },
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Map'), Tab(text: 'List')]),
        ),
        body: TabBarView(
          children: [
            _buildMap(home),
            _buildList(home),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _loading ? null : _search,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.search),
          label: Text(_loading ? 'Searching…' : 'Search Nearby'),
        ),
      ),
    );
  }

  Widget _buildMap(HomeLocation home) {
    final homePoint = ll.LatLng(home.lat, home.lng);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: homePoint, initialZoom: 11),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.dylancleverdon.hvacleads',
        ),
        CircleLayer(circles: [
          CircleMarker(
            point: homePoint,
            radius: home.radiusMiles * 1609.34,
            useRadiusInMeter: true,
            color: Colors.blue.withOpacity(0.08),
            borderColor: Colors.blue.withOpacity(0.4),
            borderStrokeWidth: 1,
          ),
        ]),
        MarkerLayer(markers: [
          Marker(
            point: homePoint,
            width: 36,
            height: 36,
            child: const Icon(Icons.home, color: Colors.blue, size: 32),
          ),
          for (final r in _results)
            Marker(
              point: ll.LatLng(r.lat, r.lng),
              width: 32,
              height: 32,
              child: Icon(
                Icons.location_on,
                color:
                    _savedOsmIds.contains(r.osmId) ? Colors.green : Colors.red,
                size: 30,
              ),
            ),
        ]),
        const RichAttributionWidget(attributions: [
          TextSourceAttribution('OpenStreetMap contributors'),
        ]),
      ],
    );
  }

  Widget _buildList(HomeLocation home) {
    if (_error != null) {
      return Center(
          child:
              Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    }
    if (_results.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'Tap "Search Nearby" to find HVAC companies around your home.'),
        ),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final r = _results[index];
        final saved = _savedOsmIds.contains(r.osmId);
        final miles = distanceMiles(home.lat, home.lng, r.lat, r.lng);
        return ListTile(
          title: Text(r.name),
          subtitle: Text([
            '${miles.toStringAsFixed(1)} mi',
            if (r.phone != null) r.phone!,
            if (r.address != null) r.address!,
          ].join(' • ')),
          trailing: saved
              ? const Icon(Icons.check_circle, color: Colors.green)
              : TextButton(onPressed: () => _save(r), child: const Text('Add')),
        );
      },
    );
  }
}
