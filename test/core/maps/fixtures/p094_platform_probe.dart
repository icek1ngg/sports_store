import 'package:flutter/material.dart';
import 'package:sports_store/core/maps/map_directions.dart';
import 'package:sports_store/core/maps/map_location.dart';
import 'package:sports_store/features/deliveries/data/repositories/platform_delivery_phone_dialer.dart';

/// Explicit platform probe, not an app route or production task repository.
/// Public Hanoi centre coordinate; no account/task/customer data is loaded.
void main() => runApp(const MaterialApp(home: _PlatformProbe()));

class _PlatformProbe extends StatefulWidget {
  const _PlatformProbe();
  @override
  State<_PlatformProbe> createState() => _PlatformProbeState();
}

class _PlatformProbeState extends State<_PlatformProbe> {
  String _result = 'No launch requested';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P09.4 PLATFORM PROBE — FIXTURE ONLY')),
    body: Column(
      children: [
        const Text('Public coordinate fixture. No Supabase/session/task data.'),
        FilledButton(
          onPressed: () async {
            // Reproduce asynchronous authorization latency before OS handoff.
            await Future<void>.delayed(const Duration(milliseconds: 500));
            final result = await const GoogleMapsDirectionsLauncher()
                .openLocation(
                  const MapLocation(latitude: 21.028511, longitude: 105.804817),
                );
            if (mounted) {
              setState(() => _result = 'Navigation request: $result');
            }
          },
          child: const Text('Open navigation after async delay'),
        ),
        OutlinedButton(
          onPressed: () async {
            final result = await const PlatformDeliveryPhoneDialer().openDialer(
              Uri.parse('tel:0900000000'),
            );
            if (mounted) setState(() => _result = 'Dialer request: $result');
          },
          child: const Text('Open dialer only — fixture number'),
        ),
        Text(_result),
      ],
    ),
  );
}
