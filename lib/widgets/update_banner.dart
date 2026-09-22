import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Wraps the app's home screen and silently checks for a new release on
/// launch, surfacing a dismissible banner (not a blocking dialog) if one is
/// found. A manual "Check for Updates" action also exists in Settings.
class UpdateBanner extends StatefulWidget {
  final Widget child;

  const UpdateBanner({super.key, required this.child});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  final _updateService = UpdateService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSilently());
  }

  Future<void> _checkSilently() async {
    try {
      final update = await _updateService.checkForUpdate();
      if (update == null || !mounted) return;
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: Text('Version ${update.version} is available.'),
          actions: [
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              },
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                _updateService.showUpdateDialog(context, update);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Silent failure on startup (e.g. offline) is fine; Settings has a
      // manual check that surfaces errors.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
