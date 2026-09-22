import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/version_compare.dart';

class UpdateInfo {
  final String version;
  final String releaseNotes;
  final String apkDownloadUrl;

  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.apkDownloadUrl,
  });
}

/// Checks GitHub Releases for a newer build of this app and installs it.
///
/// This app is sideloaded (no Play Store), so it uses the GitHub repo itself
/// as a free "release server": `.github/workflows/release.yml` publishes a
/// GitHub Release with a signed APK attached whenever a `v*` tag is pushed,
/// and this service just polls the public "latest release" endpoint.
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const _repo = 'dylancleverdon/hvac-leads';
  static const _latestReleaseUrl =
      'https://api.github.com/repos/$_repo/releases/latest';

  final http.Client _client;

  Future<UpdateInfo?> checkForUpdate() async {
    final response = await _client.get(
      Uri.parse(_latestReleaseUrl),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode == 404) {
      // No releases published yet.
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception('GitHub API returned ${response.statusCode}');
    }

    final release = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = release['tag_name'] as String?;
    if (tagName == null) return null;

    final assets = (release['assets'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final apkAsset = assets.firstWhere(
      (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
      orElse: () => const {},
    );
    final downloadUrl = apkAsset['browser_download_url'] as String?;
    if (downloadUrl == null) return null;

    final currentVersion = (await PackageInfo.fromPlatform()).version;
    if (!isNewerVersion(current: currentVersion, candidate: tagName)) {
      return null;
    }

    return UpdateInfo(
      version: tagName,
      releaseNotes: (release['body'] as String?)?.trim().isNotEmpty == true
          ? release['body'] as String
          : 'No release notes provided.',
      apkDownloadUrl: downloadUrl,
    );
  }

  Future<File> downloadApk(
    UpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(update.apkDownloadUrl));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw Exception('Download failed (${response.statusCode})');
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/hvac_leads_${update.version}.apk');
    final sink = file.openWrite();

    final total = response.contentLength ?? 0;
    var received = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
    await sink.close();
    return file;
  }

  Future<void> installApk(File apkFile) async {
    final result = await OpenFilex.open(apkFile.path);
    if (result.type != ResultType.done) {
      throw Exception(
        '${result.message}. You may need to allow "Install unknown apps" '
        'for this app in Android Settings.',
      );
    }
  }

  /// Shows the update-available dialog with a progress state for
  /// download + install, driven from a single stateful builder so the
  /// dialog can be reused from anywhere (Settings, startup banner, ...).
  Future<void> showUpdateDialog(BuildContext context, UpdateInfo update) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _UpdateDialog(update: update, service: this),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo update;
  final UpdateService service;

  const _UpdateDialog({required this.update, required this.service});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _error;

  Future<void> _startUpdate() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final file = await widget.service.downloadApk(
        widget.update,
        onProgress: (p) => setState(() => _progress = p),
      );
      await widget.service.installApk(file);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = '$e';
        _progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Update available: ${widget.update.version}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.update.releaseNotes),
            if (_progress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: _progress != null ? null : _startUpdate,
          child: const Text('Update'),
        ),
      ],
    );
  }
}
