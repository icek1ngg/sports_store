import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../view_models/checkout_address_providers.dart';
import '../view_models/checkout_address_editor_draft.dart';
import 'checkout_design_widgets.dart';
import 'checkout_location_picker.dart';

typedef CheckoutAddressDraft = ({
  String addressDetail,
  double? latitude,
  double? longitude,
});

/// Address-first form. Only an explicitly confirmed draft reaches checkout.
class CheckoutAddressSection extends ConsumerStatefulWidget {
  const CheckoutAddressSection({
    required this.enabled,
    required this.showTiles,
    required this.onChanged,
    this.initialAddress = '',
    this.initialLatitude,
    this.initialLongitude,
    this.restoreKey,
    this.initialEditorDraft,
    this.onEditorChanged,
    super.key,
  });

  final bool enabled;
  final bool showTiles;
  final ValueChanged<CheckoutAddressDraft> onChanged;
  final String initialAddress;
  final double? initialLatitude;
  final double? initialLongitude;
  final String? restoreKey;
  final CheckoutAddressEditorDraft? initialEditorDraft;
  final ValueChanged<CheckoutAddressEditorDraft>? onEditorChanged;

  @override
  ConsumerState<CheckoutAddressSection> createState() =>
      _CheckoutAddressSectionState();
}

class _CheckoutAddressSectionState
    extends ConsumerState<CheckoutAddressSection> {
  final _queryController = TextEditingController();
  final _detailController = TextEditingController();
  String? _selectedLabel;
  double? _latitude;
  double? _longitude;
  bool _confirmed = false;
  bool _adjusted = false;
  int _editingVersion = 0;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(covariant CheckoutAddressSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.restoreKey != oldWidget.restoreKey) _restore();
  }

  void _restore() {
    _editingVersion++;
    final draft = widget.initialEditorDraft;
    if (draft != null) {
      _queryController.text = draft.query;
      _detailController.text = draft.detail;
      _selectedLabel = draft.selectedLabel;
      _latitude = draft.latitude;
      _longitude = draft.longitude;
      _confirmed = draft.confirmed;
      _adjusted = draft.adjusted;
      return;
    }
    _queryController.clear();
    _detailController.text = widget.initialAddress;
    _selectedLabel = null;
    _latitude = widget.initialLatitude;
    _longitude = widget.initialLongitude;
    _confirmed =
        widget.initialAddress.trim().isNotEmpty &&
        _latitude != null &&
        _longitude != null;
    _adjusted = false;
  }

  @override
  void dispose() {
    _queryController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  String get _fullAddress => [
    _detailController.text.trim(),
    ?_selectedLabel,
  ].where((part) => part.isNotEmpty).join(', ');

  bool get _canConfirm =>
      _detailController.text.trim().isNotEmpty &&
      _fullAddress.length >= 5 &&
      _fullAddress.length <= 500 &&
      _latitude != null &&
      _latitude!.isFinite &&
      _latitude!.abs() <= 85.05112878 &&
      _longitude != null &&
      _longitude!.isFinite &&
      _longitude!.abs() <= 180;

  void _emit() {
    widget.onEditorChanged?.call(
      CheckoutAddressEditorDraft(
        query: _queryController.text,
        detail: _detailController.text,
        selectedLabel: _selectedLabel,
        latitude: _latitude,
        longitude: _longitude,
        confirmed: _confirmed,
        adjusted: _adjusted,
      ),
    );
    widget.onChanged((
      addressDetail: _confirmed ? _fullAddress : '',
      latitude: _confirmed ? _latitude : null,
      longitude: _confirmed ? _longitude : null,
    ));
  }

  void _queryChanged(String _) {
    _editingVersion++;
    ref.read(addressSearchProvider.notifier).clear();
    setState(() {
      _selectedLabel = null;
      _latitude = null;
      _longitude = null;
      _confirmed = false;
      _adjusted = false;
    });
    _emit();
  }

  void _select(AddressSuggestion suggestion) {
    if (!widget.enabled) return;
    _editingVersion++;
    ref.read(addressSearchProvider.notifier).clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedLabel = suggestion.label;
      _latitude = suggestion.latitude;
      _longitude = suggestion.longitude;
      _confirmed = false;
      _adjusted = false;
    });
    _emit();
  }

  Future<void> _search() async {
    if (!widget.enabled) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(addressSearchProvider.notifier)
        .search(_queryController.text);
  }

  Future<void> _adjustLocation() async {
    if (!widget.enabled) return;
    FocusScope.of(context).unfocus();
    final version = _editingVersion;
    final point = await showCheckoutLocationPicker(
      context,
      initialLatitude: _latitude ?? 21.0285,
      initialLongitude: _longitude ?? 105.8542,
      hasInitialSelection: _latitude != null && _longitude != null,
      showTiles: widget.showTiles,
      addressLabel: _fullAddress.isEmpty ? null : _fullAddress,
    );
    if (!mounted ||
        !widget.enabled ||
        version != _editingVersion ||
        point == null) {
      return;
    }
    setState(() {
      _latitude = point.latitude;
      _longitude = point.longitude;
      _confirmed = false;
      _adjusted = true;
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(addressSearchProvider);
    final hasPoint = _latitude != null && _longitude != null;
    return CheckoutSection(
      title: 'ĐỊA CHỈ GIAO HÀNG • HÀ NỘI',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('checkout-address-search'),
            controller: _queryController,
            enabled: widget.enabled,
            maxLength: 200,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: 'Tìm địa chỉ ở Hà Nội',
              hintText: 'Tên đường, phường hoặc tòa nhà',
              prefixIcon: Icon(Icons.search),
              counterText: '',
            ),
            onChanged: _queryChanged,
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('checkout-address-search-button'),
            onPressed: widget.enabled && !search.isLoading ? _search : null,
            icon: const Icon(Icons.search),
            label: const Text('Tìm địa chỉ'),
          ),
          if (search.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(
                key: ValueKey('checkout-address-search-loading'),
              ),
            ),
          if (search.failure != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                search.failure!.userMessage,
                key: const ValueKey('checkout-address-search-error'),
              ),
            ),
          if (search.hasSearched &&
              !search.isLoading &&
              search.failure == null &&
              search.suggestions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Chưa tìm thấy địa chỉ. Thử tên đường gần đó hoặc chọn trên bản đồ.',
                key: ValueKey('checkout-address-search-empty'),
              ),
            ),
          for (final suggestion in search.suggestions)
            Card(
              margin: const EdgeInsets.only(top: 6),
              child: ListTile(
                key: ValueKey('checkout-address-suggestion-${suggestion.id}'),
                leading: const Icon(Icons.location_on_outlined),
                title: Text(suggestion.label),
                onTap: widget.enabled ? () => _select(suggestion) : null,
              ),
            ),
          if (_selectedLabel != null) ...[
            const SizedBox(height: 12),
            Text(
              _selectedLabel!,
              key: const ValueKey('checkout-selected-address'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('checkout-address'),
            controller: _detailController,
            enabled: widget.enabled,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: _selectedLabel == null
                  ? 'Địa chỉ chi tiết'
                  : 'Số nhà, ngõ, tầng/phòng',
              hintText: _selectedLabel == null
                  ? 'Số nhà, đường, phường/xã, Hà Nội'
                  : 'Ví dụ: số 12, ngõ 5, tầng 2',
              counterText: '',
              errorText: _fullAddress.length > 500
                  ? 'Địa chỉ tối đa 500 ký tự. Vui lòng rút ngắn phần chi tiết.'
                  : null,
            ),
            onChanged: (_) {
              _editingVersion++;
              setState(() {
                _confirmed = false;
                // In manual mode this field is the whole street address.
                // A new street must not inherit the previous destination pin.
                if (_selectedLabel == null) {
                  _latitude = null;
                  _longitude = null;
                  _adjusted = false;
                }
              });
              _emit();
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('checkout-location'),
            onPressed: widget.enabled ? _adjustLocation : null,
            icon: const Icon(Icons.map_outlined),
            label: Text(hasPoint ? 'Chỉnh vị trí' : 'Chọn vị trí trên bản đồ'),
          ),
          if (_adjusted)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Đã chỉnh vị trí. Kiểm tra số nhà và tên đường trước khi xác nhận.',
              ),
            ),
          const SizedBox(height: 8),
          Text(
            _confirmed
                ? 'Đã xác nhận địa chỉ nhận hàng.'
                : hasPoint
                ? 'Kiểm tra địa chỉ và xác nhận để tiếp tục đặt hàng.'
                : 'Chọn một gợi ý hoặc chọn vị trí trên bản đồ.',
            key: const ValueKey('checkout-address-status'),
          ),
          if (widget.enabled) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('checkout-address-confirm'),
              onPressed: _canConfirm && !_confirmed
                  ? () {
                      setState(() => _confirmed = true);
                      _emit();
                    }
                  : null,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Xác nhận địa chỉ'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Chỉ giao hàng tại Hà Nội. Khu vực được kiểm tra lại khi đặt đơn.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton(
            onPressed: () async {
              try {
                await launchUrl(
                  Uri.parse('https://www.openstreetmap.org/copyright'),
                  mode: LaunchMode.externalApplication,
                );
              } on Object {
                if (!context.mounted) return;
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text('Không mở được thông tin bản quyền.'),
                  ),
                );
              }
            },
            child: const Text('Dữ liệu địa chỉ © OpenStreetMap'),
          ),
        ],
      ),
    );
  }
}
