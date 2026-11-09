import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../app/theme/storefront_theme.dart';
import '../../../catalog/presentation/widgets/catalog_formatters.dart';
import '../../../catalog/presentation/widgets/catalog_image.dart';
import 'checkout_location_map.dart';

class CheckoutSection extends StatelessWidget {
  const CheckoutSection({required this.child, this.title, super.key});
  final String? title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: StorefrontTheme.cloud,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
        ],
        child,
      ],
    ),
  );
}

class CheckoutBrandStrip extends StatelessWidget {
  const CheckoutBrandStrip({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    color: StorefrontTheme.cloud,
    child: Row(
      children: [
        const CircleAvatar(
          radius: 17,
          backgroundColor: StorefrontTheme.ink,
          child: Icon(
            Icons.local_shipping_outlined,
            color: Colors.white,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'STRIDE • HÀ NỘI',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontFamily: 'BarlowCondensed',
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Giao hàng và thanh toán khi nhận',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'COD',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
        ),
      ],
    ),
  );
}

class CheckoutProductRow extends StatelessWidget {
  const CheckoutProductRow({
    required this.name,
    required this.variantLabel,
    required this.quantity,
    required this.amountVnd,
    this.imagePath,
    super.key,
  });
  final String name;
  final String variantLabel;
  final int quantity;
  final int? amountVnd;
  final String? imagePath;
  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '$variantLabel • SL: $quantity',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            amountVnd == null
                ? 'Giá không còn khả dụng'
                : formatVnd(amountVnd!),
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CatalogProductImage(
          imagePath: imagePath,
          width: 64,
          height: 70,
          fit: BoxFit.contain,
          borderRadius: 4,
          compact: true,
        ),
        const SizedBox(width: 10),
        Expanded(child: details),
      ],
    );
  }
}

class CheckoutCodCard extends StatelessWidget {
  const CheckoutCodCard({super.key});
  @override
  Widget build(BuildContext context) => CheckoutSection(
    title: 'PHƯƠNG THỨC THANH TOÁN',
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xffdedede)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.payments_outlined, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thanh toán khi nhận hàng (COD)',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Thanh toán tổng tiền đơn hàng cho nhân viên giao hàng.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.radio_button_checked, size: 20),
        ],
      ),
    ),
  );
}

/// Compact destination map; customers can tap here or open the larger picker.
class CheckoutMapPreview extends StatelessWidget {
  const CheckoutMapPreview({
    required this.latitude,
    required this.longitude,
    required this.showTiles,
    this.hasSelection = true,
    this.onPicked,
    super.key,
  });
  final double latitude;
  final double longitude;
  final bool showTiles;
  final bool hasSelection;
  final ValueChanged<LatLng>? onPicked;

  @override
  Widget build(BuildContext context) => CheckoutLocationMap(
    latitude: latitude,
    longitude: longitude,
    showTiles: showTiles,
    hasSelection: hasSelection,
    onPicked: onPicked,
    height: 140,
  );
}
