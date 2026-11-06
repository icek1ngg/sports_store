import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/state/foundation_providers.dart';
import '../../../../../shared/widgets/async_content.dart';
import '../../providers/notification_providers.dart';
import '../../providers/notification_snapshot_projection.dart';
import 'notification_context_handle.dart';
import 'notification_context_sheet.dart';

/// Parent pushes the route; this widget owns guards until route disposal.
/// A route builder must capture only [handle], never a NotificationItem/Page.
class Mh17NotificationContextModal extends ConsumerStatefulWidget {
  const Mh17NotificationContextModal({required this.handle, super.key});
  final NotificationContextHandle handle;

  @override
  ConsumerState<Mh17NotificationContextModal> createState() =>
      _ContextModalState();
}

class _ContextModalState extends ConsumerState<Mh17NotificationContextModal> {
  final _subscriptions = <ProviderSubscription<Object?>>[];
  void Function()? _cancelHandle;
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _cancelHandle = widget.handle.listen(_changed);
    _subscriptions.add(
      ref.listenManual(
        featureSessionScopeProvider,
        (_, _) => _check(),
        fireImmediately: true,
      ),
    );
    _subscriptions.add(
      ref.listenManual(
        epochCacheProvider,
        (_, _) => _check(),
        fireImmediately: true,
      ),
    );
    final countSubscription = ref.listenManual(unreadCountFoundationProvider, (
      _,
      value,
    ) {
      if (NotificationSnapshotProjection.isAccessFailure(
        value.asData?.value.failure,
      )) {
        widget.handle.revoke();
      }
    }, fireImmediately: true);
    _subscriptions.add(countSubscription);
    final pageSubscription = ref.listenManual(
      notificationPageFoundationProvider(widget.handle.query),
      (_, value) {
        if (NotificationSnapshotProjection.isAccessFailure(
          value.asData?.value.failure,
        )) {
          widget.handle.revoke();
        }
      },
      fireImmediately: true,
    );
    _subscriptions.add(pageSubscription);
  }

  void _check() {
    if (!mounted) return;
    widget.handle.read(
      ref.read(featureSessionScopeProvider),
      ref.read(epochCacheProvider),
    );
  }

  void _changed() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    if (_queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (mounted) setState(() {});
    });
  }

  void _detach() {
    _cancelHandle?.call();
    _cancelHandle = null;
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    _subscriptions.clear();
  }

  @override
  void didUpdateWidget(covariant Mh17NotificationContextModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.handle, oldWidget.handle)) return;
    _detach();
    oldWidget.handle.release();
    _attach();
  }

  @override
  void dispose() {
    _detach();
    widget.handle.release();
    super.dispose();
  }

  void _close() {
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(featureSessionScopeProvider);
    final cache = ref.watch(epochCacheProvider);
    final count = ref.watch(unreadCountFoundationProvider).asData?.value;
    final page = ref
        .watch(notificationPageFoundationProvider(widget.handle.query))
        .asData
        ?.value;
    if (NotificationSnapshotProjection.isAccessFailure(count?.failure) ||
        NotificationSnapshotProjection.isAccessFailure(page?.failure)) {
      widget.handle.revoke();
    }
    final content = widget.handle.read(scope, cache);
    if (content == null) {
      return scope.userId == null || !cache.canRead
          ? const SessionExpiredState()
          : const SessionUnavailableState();
    }
    return Mh17NotificationContextSheet(
      title: content.title,
      body: content.body,
      onClose: _close,
    );
  }
}
