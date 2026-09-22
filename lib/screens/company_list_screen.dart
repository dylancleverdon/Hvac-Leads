import 'package:flutter/material.dart';

import '../models/application_status.dart';
import '../models/company.dart';
import '../models/home_location.dart';
import '../services/database_service.dart';
import '../utils/distance.dart';
import 'add_manual_company_screen.dart';
import 'company_detail_screen.dart';
import 'settings_screen.dart';

enum _SortBy { name, distance, status, recentlyUpdated }

class CompanyListScreen extends StatefulWidget {
  const CompanyListScreen({super.key});

  @override
  State<CompanyListScreen> createState() => _CompanyListScreenState();
}

class _CompanyListScreenState extends State<CompanyListScreen> {
  final _db = DatabaseService.instance;
  final _searchController = TextEditingController();

  List<Company> _companies = [];
  HomeLocation? _home;
  ApplicationStatus? _statusFilter;
  _SortBy _sortBy = _SortBy.distance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() => setState(() {}));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final companies = await _db.getAllCompanies();
    final home = await _db.getHomeLocation();
    if (mounted) {
      setState(() {
        _companies = companies;
        _home = home;
        _loading = false;
      });
    }
  }

  double? _distanceFor(Company c) {
    if (_home == null) return null;
    return distanceMiles(_home!.lat, _home!.lng, c.lat, c.lng);
  }

  List<Company> get _visibleCompanies {
    final query = _searchController.text.trim().toLowerCase();
    var list = _companies.where((c) {
      if (_statusFilter != null && c.status != _statusFilter) return false;
      if (query.isEmpty) return true;
      return c.name.toLowerCase().contains(query) ||
          (c.address?.toLowerCase().contains(query) ?? false) ||
          (c.phone?.toLowerCase().contains(query) ?? false);
    }).toList();

    switch (_sortBy) {
      case _SortBy.name:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _SortBy.distance:
        list.sort((a, b) {
          final da = _distanceFor(a) ?? double.infinity;
          final db = _distanceFor(b) ?? double.infinity;
          return da.compareTo(db);
        });
        break;
      case _SortBy.status:
        list.sort((a, b) => a.status.index.compareTo(b.status.index));
        break;
      case _SortBy.recentlyUpdated:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
    }
    return list;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleCompanies;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Companies'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _load();
            },
          ),
          PopupMenuButton<_SortBy>(
            icon: const Icon(Icons.sort),
            initialValue: _sortBy,
            onSelected: (value) => setState(() => _sortBy = value),
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: _SortBy.distance, child: Text('Sort by distance')),
              PopupMenuItem(value: _SortBy.name, child: Text('Sort by name')),
              PopupMenuItem(
                  value: _SortBy.status, child: Text('Sort by status')),
              PopupMenuItem(
                  value: _SortBy.recentlyUpdated,
                  child: Text('Sort by recently updated')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by name, address, phone…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _statusChip(null, 'All'),
                for (final status in ApplicationStatus.values)
                  _statusChip(status, status.label),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                    ? Center(
                        child: Text(
                          _companies.isEmpty
                              ? 'No companies saved yet. Search nearby or add one manually.'
                              : 'No companies match your filters.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final c = visible[index];
                            final miles = _distanceFor(c);
                            return ListTile(
                              title: Text(c.name),
                              subtitle: Text([
                                if (miles != null)
                                  '${miles.toStringAsFixed(1)} mi',
                                c.status.label,
                              ].join(' • ')),
                              trailing: c.source == CompanySource.manual
                                  ? const Icon(Icons.person_outline, size: 18)
                                  : null,
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CompanyDetailScreen(companyId: c.id!),
                                  ),
                                );
                                _load();
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddManualCompanyScreen()),
          );
          _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _statusChip(ApplicationStatus? status, String label) {
    final selected = _statusFilter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _statusFilter = status),
      ),
    );
  }
}
