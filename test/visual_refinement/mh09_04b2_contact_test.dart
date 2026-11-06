import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/buyer.dart';
import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_contact_actions.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_recipient_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_notification_theme.dart';

import '../features/orders/presentation/widgets/mh09/mh09_test_support.dart';
import 'mh09_04a_capture.dart' show loadMh09AuditFonts;

const _buyerId = '20000000-0000-4000-8000-000000000001';

Buyer _buyer([String? name = 'Tài khoản người mua minh họa']) =>
    Buyer(id: _buyerId, fullName: name);

Mh09RecipientSection _section({
  Order? order,
  Buyer? buyer,
  VoidCallback? onCall,
  VoidCallback? onChat,
  bool contactEnabled = true,
}) => Mh09RecipientSection(
  order: order ?? mh09Order(),
  buyer: buyer,
  onCall: onCall,
  onChat: onChat,
  contactEnabled: contactEnabled,
);

bool _enabled(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isEnabled ==
    Tristate.isTrue;

bool _hasTap(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().actions &
        SemanticsAction.tap.index !=
    0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadMh09AuditFonts);

  testWidgets('keeps the exact heading and authoritative recipient fields', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final order = mh09Order(
      recipientName: 'Người nhận có tên minh họa',
      addressDetail: '25 Nguyễn Chí Thanh, phường Láng Thượng, Hà Nội',
    );
    try {
      await pumpMh09(tester, _section(order: order, buyer: _buyer()));

      expect(find.text('Người mua và người nhận'), findsOneWidget);
      expect(find.bySemanticsLabel('Người mua và người nhận'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Người mua và người nhận'))
            .getSemanticsData()
            .flagsCollection
            .isHeader,
        isTrue,
      );
      expect(find.text('Tài khoản người mua minh họa'), findsOneWidget);
      expect(find.text(order.recipientName), findsOneWidget);
      expect(find.text(order.recipientPhone), findsOneWidget);
      expect(find.text(order.addressDetail), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('balances contact controls across the 390px card content', (
    tester,
  ) async {
    var calls = 0;
    var chats = 0;
    await pumpMh09(
      tester,
      _section(buyer: _buyer(), onCall: () => calls++, onChat: () => chats++),
      width: 390,
      scale: 1,
    );

    final call = find.byKey(const ValueKey('mh09-recipient-call'));
    final chat = find.byKey(const ValueKey('mh09-recipient-chat'));
    final actions = find.byType(Mh09ContactActions);
    final callRect = tester.getRect(call);
    final chatRect = tester.getRect(chat);
    final actionsRect = tester.getRect(actions);
    expect(callRect.width, closeTo(155, .1));
    expect(chatRect.width, closeTo(155, .1));
    expect(chatRect.left - callRect.right, closeTo(8, .1));
    expect(chatRect.top, closeTo(callRect.top, .1));
    expect(callRect.left, closeTo(actionsRect.left, .1));
    expect(chatRect.right, closeTo(actionsRect.right, .1));
    expect(actionsRect.width, greaterThan(callRect.width + 8));
    expect(callRect.height, greaterThanOrEqualTo(48));
    expect(chatRect.height, greaterThanOrEqualTo(48));

    await tester.tap(call);
    await tester.tap(chat);
    expect(calls, 1);
    expect(chats, 1);
  });

  testWidgets('stacks full-width controls at 320px and reflows landscape', (
    tester,
  ) async {
    await pumpMh09(
      tester,
      _section(
        buyer: _buyer('Tên tài khoản rất dài để kiểm tra xuống dòng'),
        order: mh09Order(
          recipientName: 'Người nhận có tên rất dài để kiểm tra xuống dòng',
          addressDetail: 'Địa chỉ giao hàng rất dài tại Hà Nội ' * 4,
        ),
        onCall: () {},
        onChat: () {},
      ),
      width: 320,
      height: 844,
      scale: 2,
    );
    final narrowCall = find.byKey(const ValueKey('mh09-recipient-call'));
    final narrowChat = find.byKey(const ValueKey('mh09-recipient-chat'));
    final narrowCallRect = tester.getRect(narrowCall);
    final narrowChatRect = tester.getRect(narrowChat);
    expect(narrowCallRect.width, closeTo(248, .1));
    expect(narrowChatRect.width, closeTo(248, .1));
    expect(narrowChatRect.top - narrowCallRect.bottom, closeTo(8, .1));
    expect(find.text('Gọi'), findsOneWidget);
    expect(find.text('Nhắn tin'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpMh09(
      tester,
      _section(buyer: _buyer(), onCall: () {}, onChat: () {}),
      width: 844,
      height: 390,
      scale: 2,
    );
    final landscapeCall = tester.getRect(narrowCall);
    final landscapeChat = tester.getRect(narrowChat);
    expect(landscapeCall.width, closeTo(382, .1));
    expect(landscapeChat.width, closeTo(382, .1));
    expect(landscapeChat.left - landscapeCall.right, closeTo(8, .1));
    expect(landscapeChat.top, closeTo(landscapeCall.top, .1));
    expect(landscapeCall.height, greaterThanOrEqualTo(48));
    expect(landscapeChat.height, greaterThanOrEqualTo(48));
    expect(find.text('Gọi'), findsOneWidget);
    expect(find.text('Nhắn tin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 412.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('stacks contact controls at $width px and scale $scale', (
        tester,
      ) async {
        await pumpMh09(
          tester,
          _section(
            buyer: _buyer('Tên tài khoản dài để kiểm tra khả năng reflow'),
            order: mh09Order(
              recipientName: 'Người nhận có tên rất dài để đọc đủ',
              addressDetail: 'Địa chỉ giao hàng rất dài tại Hà Nội ' * 3,
            ),
            onCall: () {},
            onChat: () {},
          ),
          width: width,
          scale: scale,
        );
        final call = find.byKey(const ValueKey('mh09-recipient-call'));
        final chat = find.byKey(const ValueKey('mh09-recipient-chat'));
        final callRect = tester.getRect(call);
        final chatRect = tester.getRect(chat);
        final expectedWidth = width - 72;
        expect(callRect.width, closeTo(expectedWidth, .1));
        expect(chatRect.width, closeTo(expectedWidth, .1));
        expect(chatRect.top - callRect.bottom, closeTo(8, .1));
        expect(callRect.height, greaterThanOrEqualTo(48));
        expect(chatRect.height, greaterThanOrEqualTo(48));
        expect(find.text('Gọi'), findsOneWidget);
        expect(find.text('Nhắn tin'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('keeps callbacks and availability reasons independent', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var calls = 0;
    var chats = 0;
    try {
      await pumpMh09(
        tester,
        _section(
          order: _BlankPhoneOrder(),
          buyer: null,
          onCall: () => calls++,
          onChat: () => chats++,
        ),
      );
      final call = find.byKey(const ValueKey('mh09-recipient-call'));
      final chat = find.byKey(const ValueKey('mh09-recipient-chat'));
      expect(_enabled(tester, call), isFalse);
      expect(_enabled(tester, chat), isTrue);
      expect(_hasTap(tester, call), isFalse);
      expect(_hasTap(tester, chat), isTrue);
      expect(
        find.textContaining('Gọi: Chưa có số điện thoại người nhận.'),
        findsOneWidget,
      );
      expect(find.text('Chưa có thông tin tài khoản'), findsOneWidget);
      final reason = tester.widget<Text>(
        find.textContaining('Gọi: Chưa có số điện thoại người nhận.'),
      );
      expect(reason.style?.fontSize, 12);
      expect(reason.style?.color, OrderNotificationTheme.muted);
      await tester.tap(chat);
      expect(calls, 0);
      expect(chats, 1);

      await pumpMh09(tester, _section(buyer: _buyer()));
      expect(
        find.textContaining('Tính năng gọi chưa khả dụng.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Điều hướng trò chuyện chưa khả dụng.'),
        findsOneWidget,
      );
      expect(_enabled(tester, call), isFalse);
      expect(_enabled(tester, chat), isFalse);
      expect(_hasTap(tester, call), isFalse);
      expect(_hasTap(tester, chat), isFalse);

      await pumpMh09(
        tester,
        _section(
          buyer: _buyer(),
          onCall: () => calls++,
          onChat: () => chats++,
          contactEnabled: false,
        ),
      );
      expect(
        find.textContaining('Gọi: Liên hệ hiện không khả dụng.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Nhắn tin: Liên hệ hiện không khả dụng.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Gọi. Liên hệ hiện không khả dụng.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Nhắn tin. Liên hệ hiện không khả dụng.'),
        findsOneWidget,
      );
      expect(_enabled(tester, call), isFalse);
      expect(_enabled(tester, chat), isFalse);
      expect(_hasTap(tester, call), isFalse);
      expect(_hasTap(tester, chat), isFalse);
    } finally {
      semantics.dispose();
    }
  });
}

class _BlankPhoneOrder implements Order {
  @override
  String get id => '10000000-0000-4000-8000-000000000001';
  @override
  String get customerId => _buyerId;
  @override
  String get requestId => '30000000-0000-4000-8000-000000000001';
  @override
  OrderStatus get status => OrderStatus.pendingConfirmation;
  @override
  String get recipientName => 'Người nhận cũ';
  @override
  String get recipientPhone => ' ';
  @override
  String get addressDetail => '25 Nguyễn Chí Thanh, Hà Nội';
  @override
  double get latitude => 21.028;
  @override
  double get longitude => 105.834;
  @override
  int get subtotalVnd => 3450000;
  @override
  int get deliveryFeeVnd => 30000;
  @override
  int get totalCodVnd => 3480000;
  @override
  int get deliveryAttemptCount => 0;
  @override
  DateTime get placedAt => DateTime.utc(2026, 10, 8, 3, 32);
  @override
  DateTime? get confirmedAt => null;
  @override
  OrderConfirmationSource? get source => null;
  @override
  String? get confirmedBy => null;
  @override
  DateTime? get deliveredAt => null;
  @override
  String? get cancelReason => null;
  @override
  DateTime get createdAt => placedAt;
  @override
  DateTime get updatedAt => placedAt;
  @override
  Map<String, Object?> toMap() => const {};
  @override
  bool operator ==(Object other) => identical(this, other);
  @override
  int get hashCode => identityHashCode(this);
}
