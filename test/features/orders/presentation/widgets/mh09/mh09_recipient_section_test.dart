import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/features/orders/domain/models/buyer.dart';
import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_recipient_section.dart';

import 'mh09_test_support.dart';

const _buyerId = '20000000-0000-4000-8000-000000000001';

Buyer _buyer([String? name = 'Tài khoản người mua minh họa']) =>
    Buyer(id: _buyerId, fullName: name);

Mh09RecipientSection _section({
  Order? order,
  Buyer? buyer,
  VoidCallback? onCall,
  VoidCallback? onChat,
  bool contactEnabled = true,
}) {
  return Mh09RecipientSection(
    order: order ?? mh09Order(),
    buyer: buyer,
    onCall: onCall,
    onChat: onChat,
    contactEnabled: contactEnabled,
  );
}

bool _semanticsEnabled(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isEnabled ==
    Tristate.isTrue;

bool _hasSemanticTap(WidgetTester tester, Finder finder) {
  final data = tester.getSemantics(finder).getSemanticsData();
  return data.actions & SemanticsAction.tap.index != 0;
}

void _performSemanticTap(WidgetTester tester, Finder finder) {
  final node = tester.getSemantics(finder);
  node.owner!.performAction(node.id, SemanticsAction.tap);
}

void main() {
  testWidgets('keeps buyer account and recipient snapshot distinct', (
    tester,
  ) async {
    final order = mh09Order(
      recipientName: 'Người nhận có tên rất dài để đọc đủ trong thẻ',
      addressDetail:
          'Tầng 7, số 25 Nguyễn Chí Thanh, phường Láng Thượng, Hà Nội',
    );
    await pumpMh09(tester, _section(order: order, buyer: _buyer()));

    expect(find.text('Người mua và người nhận'), findsOneWidget);
    expect(find.text('Người mua'), findsOneWidget);
    expect(find.text('Tài khoản người mua minh họa'), findsOneWidget);
    expect(find.text('Người nhận'), findsOneWidget);
    expect(find.text(order.recipientName), findsOneWidget);
    expect(find.text(order.addressDetail), findsOneWidget);
  });

  testWidgets('uses truthful fallbacks for missing buyer name', (tester) async {
    await pumpMh09(tester, _section(buyer: null));
    expect(find.text('Chưa có thông tin tài khoản'), findsOneWidget);

    await pumpMh09(tester, _section(buyer: _buyer(null)));
    expect(find.text('Chưa có tên tài khoản'), findsOneWidget);

    await pumpMh09(tester, _section(buyer: _buyer('   ')));
    expect(find.text('Chưa có tên tài khoản'), findsOneWidget);
  });

  testWidgets('contact callbacks fire and targets remain at least 48 pixels', (
    tester,
  ) async {
    var calls = 0;
    var chats = 0;
    await pumpMh09(
      tester,
      _section(buyer: _buyer(), onCall: () => calls++, onChat: () => chats++),
    );

    final call = find.byKey(const ValueKey('mh09-recipient-call'));
    final chat = find.byKey(const ValueKey('mh09-recipient-chat'));
    expect(tester.getSize(call).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(chat).height, greaterThanOrEqualTo(48));
    await tester.tap(call);
    await tester.tap(chat);
    expect(calls, 1);
    expect(chats, 1);
  });

  testWidgets('contact call has one labelled semantic button and tap action', (
    tester,
  ) async {
    var calls = 0;
    await pumpMh09(tester, _section(buyer: _buyer(), onCall: () => calls++));

    final call = find.byKey(const ValueKey('mh09-recipient-call'));
    final data = tester.getSemantics(call).getSemanticsData();
    expect(find.bySemanticsLabel('Gọi'), findsOneWidget);
    expect(data.label, 'Gọi');
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, Tristate.isTrue);
    expect(_hasSemanticTap(tester, call), isTrue);

    _performSemanticTap(tester, call);
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('missing callbacks are disabled with a visible explanation', (
    tester,
  ) async {
    await pumpMh09(tester, _section(buyer: _buyer()));

    expect(find.textContaining('Tính năng gọi chưa khả dụng'), findsOneWidget);
    expect(
      find.textContaining('Điều hướng trò chuyện chưa khả dụng'),
      findsOneWidget,
    );
    expect(
      _semanticsEnabled(
        tester,
        find.byKey(const ValueKey('mh09-recipient-call')),
      ),
      isFalse,
    );
    expect(
      _semanticsEnabled(
        tester,
        find.byKey(const ValueKey('mh09-recipient-chat')),
      ),
      isFalse,
    );
  });

  testWidgets('contact gate disables both actions and explains why', (
    tester,
  ) async {
    await pumpMh09(
      tester,
      _section(
        buyer: _buyer(),
        onCall: () {},
        onChat: () {},
        contactEnabled: false,
      ),
    );

    expect(find.textContaining('Liên hệ hiện không khả dụng'), findsOneWidget);
    expect(
      _semanticsEnabled(
        tester,
        find.byKey(const ValueKey('mh09-recipient-call')),
      ),
      isFalse,
    );
  });

  testWidgets('disabled contact call has no semantic tap action', (
    tester,
  ) async {
    var calls = 0;
    await pumpMh09(
      tester,
      _section(buyer: _buyer(), onCall: () => calls++, contactEnabled: false),
    );

    final call = find.byKey(const ValueKey('mh09-recipient-call'));
    final data = tester.getSemantics(call).getSemanticsData();
    expect(data.label, 'Gọi. Liên hệ hiện không khả dụng.');
    expect(find.bySemanticsLabel(data.label), findsOneWidget);
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    expect(_hasSemanticTap(tester, call), isFalse);

    _performSemanticTap(tester, call);
    await tester.pump();
    expect(calls, 0);
  });

  testWidgets('legacy blank phone and address stay unavailable defensively', (
    tester,
  ) async {
    var chats = 0;
    await pumpMh09(
      tester,
      _section(
        order: _LegacyOrderWithoutContact(),
        buyer: null,
        onCall: () {},
        onChat: () => chats++,
      ),
    );

    expect(find.text('Chưa có số điện thoại'), findsOneWidget);
    expect(find.text('Chưa có địa chỉ nhận hàng'), findsOneWidget);
    expect(
      find.textContaining('Chưa có số điện thoại người nhận'),
      findsOneWidget,
    );
    expect(
      _semanticsEnabled(
        tester,
        find.byKey(const ValueKey('mh09-recipient-call')),
      ),
      isFalse,
    );
    expect(
      _semanticsEnabled(
        tester,
        find.byKey(const ValueKey('mh09-recipient-chat')),
      ),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('mh09-recipient-chat')));
    expect(chats, 1);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('reflows at width $width and text scale $scale', (
        tester,
      ) async {
        await pumpMh09(
          tester,
          _section(
            buyer: _buyer('Tên tài khoản rất dài để kiểm tra xuống dòng'),
            order: mh09Order(
              recipientName: 'Người nhận có tên dài ' * 3,
              addressDetail: 'Địa chỉ giao hàng rất dài tại Hà Nội ' * 4,
            ),
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('mh09-recipient-call')))
              .height,
          greaterThanOrEqualTo(48),
        );
      });
    }
  }
}

/// Legacy boundary used only to prove the renderer does not crash on blank
/// contact snapshots. Valid production Order construction rejects these values.
class _LegacyOrderWithoutContact implements Order {
  @override
  String get id => '10000000-0000-4000-8000-000000000001';
  @override
  String get customerId => '20000000-0000-4000-8000-000000000001';
  @override
  String get requestId => '30000000-0000-4000-8000-000000000001';
  @override
  OrderStatus get status => OrderStatus.pendingConfirmation;
  @override
  String get recipientName => 'Người nhận cũ';
  @override
  String get recipientPhone => ' ';
  @override
  String get addressDetail => ' ';
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
