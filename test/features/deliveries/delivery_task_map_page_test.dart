import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/maps/map_tile_source.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_query.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_repository.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_map_page.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_providers.dart';
import 'package:sports_store/core/maps/map_providers.dart';
import 'package:sports_store/core/maps/map_display_adapter.dart';
import 'package:sports_store/core/maps/map_location.dart';
import 'package:sports_store/core/maps/map_directions.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_phone_dialer.dart';
import 'package:sports_store/features/deliveries/presentation/widgets/delivery_call_action.dart';

import 'fixtures/delivery_dtos.dart';

/// Fake tile source used to prove MH18 retains the authorized address when the
/// external tile provider is unavailable. It is not production map data.
final class _FailingTileSource implements MapTileSource {
  @override
  String get attribution => '© OpenStreetMap contributors';

  @override
  Future<void> dispose() async {}

  @override
  Future<Uint8List> loadTile(Uri uri) =>
      Future<Uint8List>.error(StateError('fake tile outage'));

  @override
  Uri tileUri({required int zoom, required int x, required int y}) =>
      Uri.parse('https://tiles.invalid/$zoom/$x/$y.png');
}

final class _FakeRepository implements DeliveryRepository {
  String kind = 'outbound';
  String phone = '0900000000';
  Object? failure;
  bool missingCoordinates = false;
  bool restricted = false;
  Completer<DeliveryTaskDetails>? pending;
  final pendingReads = <Completer<DeliveryTaskDetails>>[];
  int reads = 0;

  DeliveryTaskDetails details() => DeliveryTaskDetails(
    task: DeliveryTaskDto.fromJson(
      restricted
          ? maskedTaskDto()
          : {
              ...currentTaskDto(
                kind: kind,
                amount: kind == 'outbound' ? 550000 : 0,
                returnRequest: kind == 'outbound' ? null : returnRequestId,
                itemSource: kind == 'outbound'
                    ? 'order_snapshot'
                    : 'return_plan',
              ),
              'destination_phone': phone,
              if (missingCoordinates) 'destination_latitude': null,
            },
      allowMissingDestinationCoordinates: true,
    ).toDomain(),
    items: const [],
  );
  @override
  Future<DeliveryTaskDetails> getTaskDetails(String taskId) async {
    reads++;
    if (failure != null) throw failure!;
    if (pendingReads.isNotEmpty) return pendingReads.removeAt(0).future;
    if (pending != null) return pending!.future;
    return details();
  }

  @override
  Future<DeliveryTaskSnapshot> getTask(String taskId) =>
      Future.error(UnimplementedError());

  @override
  Future<List<DeliveryTaskSnapshot>> listTasks() =>
      Future.error(UnimplementedError());

  @override
  Future<DeliveryTaskPage> queryTasks(DeliveryTaskQuery query) =>
      Future.error(UnimplementedError());
}

/// Coordinate-only test display; no real tiles or sample production records.
final class _Display implements MapDisplayAdapter {
  MapLocation? location;
  int token = -1;
  @override
  Widget buildMap({
    Key? key,
    required MapLocation location,
    int recenterToken = 0,
    double height = 320,
    ValueChanged<Object>? onTileError,
  }) {
    this.location = location;
    token = recenterToken;
    return SizedBox(
      key: key,
      height: height,
      child: const Center(
        child: Icon(
          Icons.location_on,
          key: ValueKey('test-destination-marker'),
        ),
      ),
    );
  }
}

final class _Navigation implements MapNavigationAdapter {
  final locations = <MapLocation>[];
  MapDirectionsOutcome result = MapDirectionsOutcome.unavailable;
  @override
  Future<MapDirectionsOutcome> openLocation(MapLocation location) async {
    locations.add(location);
    return result;
  }
}

final class _Dialer implements DeliveryPhoneDialer {
  final uris = <Uri>[];
  DialerOpenOutcome result = DialerOpenOutcome.opened;
  @override
  Future<DialerOpenOutcome> openDialer(Uri telephoneUri) async {
    uris.add(telephoneUri);
    return result;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _mount(
  WidgetTester tester,
  _FakeRepository repo,
  StreamController<OperationalSession> sessions, {
  _Display? display,
  _Navigation? navigation,
  _Dialer? dialer,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deliveryRepositoryProvider.overrideWithValue(repo),
        operationalSessionProvider.overrideWith((ref) => sessions.stream),
        mapDisplayAdapterProvider.overrideWithValue(display ?? _Display()),
        mapNavigationAdapterProvider.overrideWithValue(
          navigation ?? _Navigation(),
        ),
        deliveryPhoneDialerProvider.overrideWithValue(dialer ?? _Dialer()),
      ],
      child: const MaterialApp(home: DeliveryTaskMapPage(taskId: taskId)),
    ),
  );
  sessions.add(const OperationalSession(userId: 'shipper-a', generation: 1));
  await _settle(tester);
}

void main() {
  testWidgets(
    'rapid resume keeps periodic checks blocked until all pending checks finish',
    (tester) async {
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);
      final repo = _FakeRepository();
      await _mount(tester, repo, sessions);
      final first = Completer<DeliveryTaskDetails>();
      final second = Completer<DeliveryTaskDetails>();
      repo.pendingReads.addAll([first, second]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(repo.reads, 3);
      first.complete(repo.details());
      await _settle(tester);
      await tester.pump(const Duration(seconds: 15));
      expect(repo.reads, 3);
      expect(find.byKey(const ValueKey('mh18-address')), findsNothing);
      second.complete(repo.details());
      await _settle(tester);
      expect(find.byKey(const ValueKey('mh18-address')), findsOneWidget);
    },
  );
  for (final outcome in MapDirectionsOutcome.values) {
    testWidgets('navigation $outcome preserves address without false success', (
      tester,
    ) async {
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);
      final nav = _Navigation()..result = outcome;
      await _mount(tester, _FakeRepository(), sessions, navigation: nav);
      await tester.tap(find.byKey(const ValueKey('mh18-directions')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('mh18-address')), findsOneWidget);
      expect(find.textContaining('Đã mở Google Maps'), findsNothing);
      if (outcome == MapDirectionsOutcome.opened) {
        expect(
          find.text('Đã gửi yêu cầu mở dịch vụ chỉ đường.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mh18-navigation-error')),
          findsNothing,
        );
      } else {
        expect(
          find.byKey(const ValueKey('mh18-navigation-error')),
          findsOneWidget,
        );
        nav.result = MapDirectionsOutcome.opened;
        await tester.tap(find.byKey(const ValueKey('mh18-directions')));
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('mh18-navigation-error')),
          findsNothing,
        );
      }
    });
  }

  for (final result in [
    DialerOpenOutcome.failed,
    DialerOpenOutcome.unavailable,
  ]) {
    testWidgets('dialer $result retains address and reports error', (
      tester,
    ) async {
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);
      await _mount(
        tester,
        _FakeRepository(),
        sessions,
        dialer: _Dialer()..result = result,
      );
      await tester.tap(find.byKey(const ValueKey('mh18-call')));
      await _settle(tester);
      expect(
        find.text('Không mở được trình quay số trên thiết bị này.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mh18-address')), findsOneWidget);
    });
  }

  testWidgets(
    'foreground check detects idle reassignment without an external action',
    (tester) async {
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);
      final repo = _FakeRepository();
      await _mount(tester, repo, sessions);
      repo.failure = const OperationalFailure(
        OperationalFailureCode.staleAssignment,
      );
      await tester.pump(const Duration(seconds: 15));
      await _settle(tester);
      expect(find.byKey(const ValueKey('mh18-address')), findsNothing);
      expect(
        find.byKey(const ValueKey('test-destination-marker')),
        findsNothing,
      );
    },
  );

  for (final failure in [
    null,
    OperationalFailureCode.staleAssignment,
    OperationalFailureCode.network,
  ]) {
    testWidgets(
      'background protects PII; resume $failure requires fresh permission',
      (tester) async {
        final sessions = StreamController<OperationalSession>.broadcast();
        addTearDown(sessions.close);
        final repo = _FakeRepository();
        await _mount(tester, repo, sessions);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('mh18-address')), findsNothing);
        if (failure != null) repo.failure = OperationalFailure(failure);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('mh18-address')),
          failure == null ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  for (final action in ['call', 'copy', 'directions']) {
    testWidgets(
      'background cancels pending $action even after foreground returns',
      (tester) async {
        final sessions = StreamController<OperationalSession>.broadcast();
        addTearDown(sessions.close);
        final repo = _FakeRepository();
        final nav = _Navigation();
        final dialer = _Dialer();
        var copied = false;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') copied = true;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await _mount(tester, repo, sessions, navigation: nav, dialer: dialer);
        repo.pending = Completer<DeliveryTaskDetails>();
        await tester.tap(find.byKey(ValueKey('mh18-$action')));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        repo.pending!.complete(repo.details());
        repo.pending = null;
        await _settle(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await _settle(tester);
        expect(nav.locations, isEmpty);
        expect(dialer.uris, isEmpty);
        expect(copied, isFalse);
      },
    );
  }
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    // The whole read-only card is visible at this mobile test viewport.
    view.physicalSize = const Size(430, 1200);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });
  for (final missing in [true, false]) {
    testWidgets(
      'missing location preserves permitted text; restricted ($missing) hides recipient',
      (tester) async {
        final sessions = StreamController<OperationalSession>.broadcast();
        addTearDown(sessions.close);
        await _mount(
          tester,
          _FakeRepository()
            ..missingCoordinates = missing
            ..restricted = !missing,
          sessions,
        );
        expect(
          find.byKey(const ValueKey('test-destination-marker')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('mh18-phone')),
          missing ? findsOneWidget : findsNothing,
        );
        if (missing) {
          expect(
            find.byKey(const ValueKey('mh18-no-coordinates')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('mh18-directions')),
                )
                .onPressed,
            isNull,
          );
        } else {
          expect(find.byKey(const ValueKey('mh18-directions')), findsNothing);
          expect(find.byKey(const ValueKey('mh18-retry')), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'narrow viewport and enlarged text remain scrollable without overflow',
    (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      tester.view.physicalSize = const Size(320, 640);
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);
      final repo = _FakeRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deliveryRepositoryProvider.overrideWithValue(repo),
            operationalSessionProvider.overrideWith((ref) => sessions.stream),
            mapDisplayAdapterProvider.overrideWithValue(_Display()),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const DeliveryTaskMapPage(taskId: taskId),
          ),
        ),
      );
      sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await _settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mh18-copy')),
        180,
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('mh18-copy')), findsOneWidget);
    },
  );

  for (final action in ['call', 'copy', 'directions']) {
    testWidgets('denied $action performs no external handoff', (tester) async {
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);
      final repo = _FakeRepository();
      final dialer = _Dialer();
      final nav = _Navigation();
      var copied = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied = true;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _mount(tester, repo, sessions, navigation: nav, dialer: dialer);
      repo.failure = const OperationalFailure(
        OperationalFailureCode.permissionDenied,
      );
      await tester.tap(find.byKey(ValueKey('mh18-$action')));
      await _settle(tester);
      expect(dialer.uris, isEmpty);
      expect(nav.locations, isEmpty);
      expect(copied, isFalse);
      expect(find.byKey(const ValueKey('mh18-address')), findsNothing);
    });
  }

  testWidgets('copy writes freshly authorized address only', (tester) async {
    final sessions = StreamController<OperationalSession>.broadcast();
    addTearDown(sessions.close);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final repo = _FakeRepository();
    await _mount(tester, repo, sessions);
    await tester.tap(find.byKey(const ValueKey('mh18-copy')));
    await _settle(tester);
    expect(copied, ['Hà Nội']);
    expect(repo.reads, 2);
    expect(find.text('Đã sao chép địa chỉ điểm đến.'), findsOneWidget);
  });

  testWidgets(
    'missing coordinates still allow freshly authorized copy and dialer',
    (tester) async {
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final dialer = _Dialer();
      final nav = _Navigation();
      final repo = _FakeRepository()..missingCoordinates = true;
      await _mount(tester, repo, sessions, navigation: nav, dialer: dialer);
      await tester.tap(find.byKey(const ValueKey('mh18-copy')));
      await _settle(tester);
      expect(copied, ['Hà Nội']);
      await tester.tap(find.byKey(const ValueKey('mh18-call')));
      await _settle(tester);
      expect(dialer.uris.single.toString(), 'tel:0900000000');
      expect(nav.locations, isEmpty);
      expect(repo.reads, 3);
      expect(find.byKey(const ValueKey('mh18-coordinates')), findsNothing);
    },
  );
  for (final variant in {
    'outbound': 'Điểm giao hàng',
    'return_pickup': 'Điểm nhận hàng trả',
    'redelivery': 'Điểm giao lại',
  }.entries) {
    testWidgets('${variant.key}: exact saved marker and read-only recipient', (
      tester,
    ) async {
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);
      final display = _Display();
      await _mount(
        tester,
        _FakeRepository()..kind = variant.key,
        sessions,
        display: display,
      );
      expect(find.text(variant.value), findsOneWidget);
      expect(
        display.location,
        const MapLocation(latitude: 21.028511, longitude: 105.804817),
      );
      expect(
        find.byKey(const ValueKey('test-destination-marker')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Lần 1'),
        variant.key == 'outbound' ? findsOneWidget : findsNothing,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.textContaining('COD'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mh18-recenter')));
      await tester.pump();
      expect(display.token, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'rechecks actions, blocks double taps and passes only coordinates to navigation',
    (tester) async {
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);
      final repo = _FakeRepository();
      final nav = _Navigation();
      final dialer = _Dialer();
      await _mount(tester, repo, sessions, navigation: nav, dialer: dialer);
      final call = find.byKey(const ValueKey('mh18-call'));
      await tester.ensureVisible(call);
      repo.pending = Completer<DeliveryTaskDetails>();
      await tester.tap(call);
      await tester.pump();
      expect(tester.widget<OutlinedButton>(call).onPressed, isNull);
      repo.pending!.complete(repo.details());
      repo.pending = null;
      await _settle(tester);
      expect(dialer.uris.single.toString(), 'tel:0900000000');
      final directions = find.byKey(const ValueKey('mh18-directions'));
      await tester.ensureVisible(directions);
      await tester.tap(directions);
      await _settle(tester);
      expect(
        nav.locations.single,
        const MapLocation(latitude: 21.028511, longitude: 105.804817),
      );
      expect(find.textContaining('không có ứng dụng/dịch vụ'), findsWidgets);
      expect(repo.reads, 3);
    },
  );

  testWidgets(
    'changed contact requires a new tap; revoked access removes PII',
    (tester) async {
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);
      final repo = _FakeRepository();
      final dialer = _Dialer();
      await _mount(tester, repo, sessions, dialer: dialer);
      repo.phone = '0911111111';
      final call = find.byKey(const ValueKey('mh18-call'));
      await tester.ensureVisible(call);
      await tester.tap(call);
      await _settle(tester);
      expect(dialer.uris, isEmpty);
      expect(find.text('0911111111'), findsOneWidget);
      repo.failure = const OperationalFailure(
        OperationalFailureCode.staleAssignment,
      );
      await tester.tap(call);
      await _settle(tester);
      expect(find.byKey(const ValueKey('mh18-address')), findsNothing);
      expect(dialer.uris, isEmpty);
    },
  );

  testWidgets('loading, denied and retry never manufacture destination', (
    tester,
  ) async {
    final sessions = StreamController<OperationalSession>.broadcast();
    addTearDown(sessions.close);
    final repo = _FakeRepository()..pending = Completer<DeliveryTaskDetails>();
    await _mount(tester, repo, sessions);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.pending!.completeError(
      const OperationalFailure(OperationalFailureCode.permissionDenied),
    );
    repo.pending = null;
    await _settle(tester);
    expect(find.byKey(const ValueKey('mh18-address')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mh18-retry')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('mh18-address')), findsOneWidget);
  });

  testWidgets(
    'logout during copy prevents clipboard handoff and clears contact',
    (tester) async {
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final repo = _FakeRepository();
      await _mount(tester, repo, sessions);
      final copy = find.byKey(const ValueKey('mh18-copy'));
      await tester.ensureVisible(copy);
      repo.pending = Completer<DeliveryTaskDetails>();
      await tester.tap(copy);
      sessions.add(const OperationalSession(userId: null, generation: 2));
      await tester.pump();
      repo.pending!.complete(repo.details());
      await _settle(tester);
      expect(copied, isEmpty);
      expect(find.byKey(const ValueKey('mh18-address')), findsNothing);
    },
  );
  testWidgets(
    'renders authorized destination and keeps address on tile outage',
    (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deliveryRepositoryProvider.overrideWithValue(_FakeRepository()),
            mapTileSourceProvider.overrideWithValue(_FailingTileSource()),
            operationalSessionProvider.overrideWith((ref) => sessions.stream),
          ],
          child: const MaterialApp(home: DeliveryTaskMapPage(taskId: taskId)),
        ),
      );
      sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await tester.pump();
      for (var index = 0; index < 10; index++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byKey(const ValueKey('mh18-address')), findsOneWidget);
      expect(find.text('Hà Nội'), findsWidgets);
      expect(find.byKey(const ValueKey('mh18-directions')), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsWidgets);
    },
  );
}
