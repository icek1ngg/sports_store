import 'package:flutter/material.dart';
import 'package:sports_store/features/orders/domain/models/buyer.dart';
import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_notification_theme.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_contact_actions.dart';

const _mh09Heading = TextStyle(
  fontFamily: 'Inter',
  fontSize: 20,
  height: 1.3,
  fontWeight: FontWeight.w600,
  color: OrderNotificationTheme.ink,
);

class Mh09RecipientSection extends StatelessWidget {
  const Mh09RecipientSection({
    required this.order,
    this.buyer,
    this.onCall,
    this.onChat,
    this.contactEnabled = true,
    super.key,
  });

  final Order order;
  final Buyer? buyer;
  final VoidCallback? onCall;
  final VoidCallback? onChat;
  final bool contactEnabled;

  @override
  Widget build(BuildContext context) {
    final phone = order.recipientPhone.trim();
    final callReason = _contactReason(
      action: 'Gọi',
      callback: onCall,
      contactEnabled: contactEnabled,
      hasPhone: phone.isNotEmpty,
    );
    final chatReason = _contactReason(
      action: 'Nhắn tin',
      callback: onChat,
      contactEnabled: contactEnabled,
      hasPhone: phone.isNotEmpty,
    );

    Widget infoRow(String label, String value) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 108, child: Text(label)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, softWrap: true)),
        ],
      );
    }

    return Card(
      key: const ValueKey('mh09-recipient-card'),
      color: OrderNotificationTheme.cloud,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              header: true,
              child: const Text('Người mua và người nhận', style: _mh09Heading),
            ),
            const SizedBox(height: 16),
            infoRow('Người mua', _buyerName(buyer)),
            const SizedBox(height: 8),
            infoRow(
              'Người nhận',
              _displayValue(order.recipientName, 'Chưa có tên người nhận'),
            ),
            const SizedBox(height: 8),
            infoRow(
              'Số điện thoại',
              _displayValue(phone, 'Chưa có số điện thoại'),
            ),
            const SizedBox(height: 8),
            infoRow(
              'Địa chỉ nhận hàng',
              _displayValue(order.addressDetail, 'Chưa có địa chỉ nhận hàng'),
            ),
            const SizedBox(height: 16),
            Mh09ContactActions(
              callEnabled: callReason == null,
              chatEnabled: chatReason == null,
              callReason: callReason,
              chatReason: chatReason,
              onCall: onCall,
              onChat: onChat,
            ),
          ],
        ),
      ),
    );
  }
}

String _buyerName(Buyer? buyer) {
  if (buyer == null) return 'Chưa có thông tin tài khoản';
  final name = buyer.fullName?.trim();
  return name == null || name.isEmpty ? 'Chưa có tên tài khoản' : name;
}

String _displayValue(String value, String fallback) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

String? _contactReason({
  required String action,
  required VoidCallback? callback,
  required bool contactEnabled,
  required bool hasPhone,
}) {
  if (!contactEnabled) return 'Liên hệ hiện không khả dụng.';
  if (action == 'Gọi' && !hasPhone) {
    return 'Chưa có số điện thoại người nhận.';
  }
  return callback == null
      ? action == 'Gọi'
            ? 'Tính năng gọi chưa khả dụng.'
            : 'Điều hướng trò chuyện chưa khả dụng.'
      : null;
}
