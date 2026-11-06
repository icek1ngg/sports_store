import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

const _hanoiLatitude = 21.0285;
const _hanoiLongitude = 105.8542;

class CheckoutLocation {
  const CheckoutLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// A compact MH16 button that opens the map picker dialog.
class CheckoutLocationPicker extends StatelessWidget {
  const CheckoutLocationPicker({
    required this.onPicked,
    this.initialLatitude = _hanoiLatitude,
    this.initialLongitude = _hanoiLongitude,
    this.showTiles = true,
    this.enabled = true,
    this.buttonKey,
    super.key,
  });

  final ValueChanged<CheckoutLocation> onPicked;
  final double initialLatitude;
  final double initialLongitude;
  final bool showTiles;
  final bool enabled;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: buttonKey,
        onPressed: enabled
            ? () async {
                final selected = await showCheckoutLocationPicker(
                  context,
                  initialLatitude: initialLatitude,
                  initialLongitude: initialLongitude,
                  showTiles: showTiles,
                );
                if (selected != null) onPicked(selected);
              }
            : null,
        icon: const Icon(Icons.location_on_outlined),
        label: const Text('Chọn vị trí giao hàng trên bản đồ'),
      ),
    );
  }
}

Future<CheckoutLocation?> showCheckoutLocationPicker(
  BuildContext context, {
  double initialLatitude = _hanoiLatitude,
  double initialLongitude = _hanoiLongitude,
  bool showTiles = true,
}) {
  return showDialog<CheckoutLocation>(
    context: context,
    // Keep the picker inside the protected customer Navigator so session
    // rechecks hide/disable the dialog together with the checkout form.
    useRootNavigator: false,
    builder: (context) => CheckoutLocationDialog(
      initialLatitude: initialLatitude,
      initialLongitude: initialLongitude,
      showTiles: showTiles,
    ),
  );
}

class CheckoutLocationDialog extends StatefulWidget {
  const CheckoutLocationDialog({
    this.initialLatitude = _hanoiLatitude,
    this.initialLongitude = _hanoiLongitude,
    this.showTiles = true,
    super.key,
  });

  final double initialLatitude;
  final double initialLongitude;
  final bool showTiles;

  @override
  State<CheckoutLocationDialog> createState() => _CheckoutLocationDialogState();
}

class _CheckoutLocationDialogState extends State<CheckoutLocationDialog> {
  late double _latitude;
  late double _longitude;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;

  @override
  void initState() {
    super.initState();
    _latitude = _validOrDefault(widget.initialLatitude, _hanoiLatitude);
    _longitude = _validOrDefault(widget.initialLongitude, _hanoiLongitude);
    _latitudeController = TextEditingController(
      text: _formatCoordinate(_latitude),
    );
    _longitudeController = TextEditingController(
      text: _formatCoordinate(_longitude),
    );
  }

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(_latitude, _longitude);
    final enteredLatitude = double.tryParse(
      _latitudeController.text.replaceAll(',', '.'),
    );
    final enteredLongitude = double.tryParse(
      _longitudeController.text.replaceAll(',', '.'),
    );
    final validInput =
        enteredLatitude != null &&
        enteredLongitude != null &&
        _isValid(enteredLatitude, enteredLongitude);
    return AlertDialog(
      title: const Text('Chọn vị trí giao hàng'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chạm vào bản đồ để đặt ghim. Máy chủ sẽ kiểm tra lại khu vực Hà Nội khi đặt đơn.',
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    key: const ValueKey('checkout-location-map'),
                    options: MapOptions(
                      initialCenter: point,
                      initialZoom: 12,
                      onTap: (_, selected) =>
                          _select(selected.latitude, selected.longitude),
                    ),
                    children: [
                      if (widget.showTiles)
                        TileLayer(
                          urlTemplate: const String.fromEnvironment(
                            'CHECKOUT_TILE_URL',
                            defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          ),
                          userAgentPackageName: 'com.example.sports_store',
                        ),
                      if (!widget.showTiles)
                        const ColoredBox(
                          color: Color(0xffe3eef3),
                          child: Center(
                            child: Text(
                              'Bản đồ tắt tile để kiểm thử ngoại tuyến',
                            ),
                          ),
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: point,
                            width: 42,
                            height: 42,
                            alignment: Alignment.topCenter,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 38,
                            ),
                          ),
                        ],
                      ),
                      RichAttributionWidget(
                        showFlutterMapAttribution: false,
                        attributions: [
                          TextSourceAttribution(
                            '© Cộng đồng OpenStreetMap',
                            onTap: () => launchUrl(
                              Uri.parse('https://openstreetmap.org/copyright'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('checkout-location-latitude'),
                      controller: _latitudeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Vĩ độ',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => _updateFromText(value, true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('checkout-location-longitude'),
                      controller: _longitudeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Kinh độ',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => _updateFromText(value, false),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const ValueKey('checkout-location-confirm'),
          onPressed: validInput
              ? () => Navigator.of(context).pop(
                  CheckoutLocation(latitude: _latitude, longitude: _longitude),
                )
              : null,
          child: const Text('Dùng vị trí này'),
        ),
      ],
    );
  }

  void _select(double latitude, double longitude) {
    if (!_isValid(latitude, longitude)) return;
    setState(() {
      _latitude = latitude;
      _longitude = longitude;
      _latitudeController.text = _formatCoordinate(latitude);
      _longitudeController.text = _formatCoordinate(longitude);
    });
  }

  void _updateFromText(String value, bool latitude) {
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    setState(() {
      if (parsed == null || !parsed.isFinite) return;
      if (latitude && parsed >= -90 && parsed <= 90) {
        _latitude = parsed;
      } else if (!latitude && parsed >= -180 && parsed <= 180) {
        _longitude = parsed;
      }
    });
  }
}

double _validOrDefault(double value, double fallback) =>
    value.isFinite ? value : fallback;

bool _isValid(double latitude, double longitude) =>
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;

String _formatCoordinate(double value) => value.toStringAsFixed(6);
