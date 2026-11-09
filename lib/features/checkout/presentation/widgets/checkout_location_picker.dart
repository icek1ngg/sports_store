import 'package:flutter/material.dart';

import 'checkout_location_map.dart';

const _hanoiLatitude = 21.0285;
const _hanoiLongitude = 105.8542;

class CheckoutLocation {
  const CheckoutLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class CheckoutLocationPicker extends StatelessWidget {
  const CheckoutLocationPicker({
    required this.onPicked,
    this.initialLatitude = _hanoiLatitude,
    this.initialLongitude = _hanoiLongitude,
    this.showTiles = true,
    this.enabled = true,
    this.hasInitialSelection = false,
    this.addressLabel,
    this.buttonKey,
    super.key,
  });

  final ValueChanged<CheckoutLocation> onPicked;
  final double initialLatitude;
  final double initialLongitude;
  final bool showTiles;
  final bool enabled;
  final bool hasInitialSelection;
  final String? addressLabel;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => SizedBox(
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
                hasInitialSelection: hasInitialSelection,
                addressLabel: addressLabel,
              );
              if (selected != null && context.mounted) onPicked(selected);
            }
          : null,
      icon: const Icon(Icons.location_on_outlined),
      label: const Text('Chọn vị trí giao hàng trên bản đồ'),
    ),
  );
}

Future<CheckoutLocation?> showCheckoutLocationPicker(
  BuildContext context, {
  double initialLatitude = _hanoiLatitude,
  double initialLongitude = _hanoiLongitude,
  bool showTiles = true,
  bool hasInitialSelection = false,
  String? addressLabel,
}) => showDialog<CheckoutLocation>(
  context: context,
  // Keep the large picker in the protected customer Navigator. It is a dialog,
  // not an additional business screen or a separate navigation system.
  useRootNavigator: false,
  builder: (context) => CheckoutLocationDialog(
    initialLatitude: initialLatitude,
    initialLongitude: initialLongitude,
    showTiles: showTiles,
    hasInitialSelection: hasInitialSelection,
    addressLabel: addressLabel,
  ),
);

class CheckoutLocationDialog extends StatefulWidget {
  const CheckoutLocationDialog({
    this.initialLatitude = _hanoiLatitude,
    this.initialLongitude = _hanoiLongitude,
    this.showTiles = true,
    this.hasInitialSelection = false,
    this.addressLabel,
    super.key,
  });

  final double initialLatitude;
  final double initialLongitude;
  final bool showTiles;
  final bool hasInitialSelection;
  final String? addressLabel;

  @override
  State<CheckoutLocationDialog> createState() => _CheckoutLocationDialogState();
}

class _CheckoutLocationDialogState extends State<CheckoutLocationDialog> {
  late double _latitude;
  late double _longitude;
  late bool _hasSelection;
  late bool _mapReady;

  @override
  void initState() {
    super.initState();
    final validInitial = _isValid(
      widget.initialLatitude,
      widget.initialLongitude,
    );
    _latitude = validInitial ? widget.initialLatitude : _hanoiLatitude;
    _longitude = validInitial ? widget.initialLongitude : _hanoiLongitude;
    _hasSelection = widget.hasInitialSelection && validInitial;
    _mapReady = !widget.showTiles;
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm =
        _hasSelection && _mapReady && _isValid(_latitude, _longitude);
    final address = widget.addressLabel?.trim();
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const ValueKey('checkout-location-cancel'),
            tooltip: 'Hủy chọn vị trí',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('Vị trí nhận hàng'),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Text(
                  'Kéo bản đồ để đưa ghim đến đúng nơi nhận hàng',
                  key: ValueKey('checkout-location-instruction'),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => CheckoutLocationMap(
                    latitude: _latitude,
                    longitude: _longitude,
                    showTiles: widget.showTiles,
                    hasSelection: _hasSelection,
                    centerPin: true,
                    height: constraints.maxHeight,
                    mapKey: const ValueKey('checkout-location-map'),
                    onPicked: (point) {
                      if (!mounted ||
                          !_isValid(point.latitude, point.longitude)) {
                        return;
                      }
                      setState(() {
                        _latitude = point.latitude;
                        _longitude = point.longitude;
                        _hasSelection = true;
                      });
                    },
                    onReadyChanged: (ready) {
                      if (mounted && ready != _mapReady) {
                        setState(() => _mapReady = ready);
                      }
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (address != null && address.isNotEmpty) ...[
                      Text(
                        address,
                        key: const ValueKey('checkout-location-address-label'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      !_hasSelection
                          ? 'Kéo bản đồ để chọn điểm nhận hàng.'
                          : !_mapReady
                          ? 'Đang kiểm tra bản đồ tại ghim…'
                          : 'Vị trí đã được chọn',
                      key: const ValueKey('checkout-location-selection-status'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('checkout-location-confirm'),
                      onPressed: canConfirm
                          ? () => Navigator.of(context).pop(
                              CheckoutLocation(
                                latitude: _latitude,
                                longitude: _longitude,
                              ),
                            )
                          : null,
                      child: const Text('Xác nhận vị trí'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isValid(double latitude, double longitude) =>
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -85.05112878 &&
    latitude <= 85.05112878 &&
    longitude >= -180 &&
    longitude <= 180;
