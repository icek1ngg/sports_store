import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/delivery_reporting.dart';
import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_task_command.dart';
import '../../domain/repositories/delivery_reporting_repository.dart';
import '../models/delivery_reporting_dto.dart';
import '../models/dto_readers.dart';
import 'operational_read_access.dart';

/// Production adapter for the P07.5 shipper reporting context and writes.
///
/// The context is read only through its dedicated RPC.  Writes use the two
/// deployed P07.4 RPCs and never fall back to table reads or client-side state
/// transitions.  Every RPC call explicitly disables the SDK retry layer so a
/// caller can retry with the same request UUID only after an uncertain result.
final class SupabaseDeliveryReportingRepository
    implements DeliveryReportingRepository {
  const SupabaseDeliveryReportingRepository({required this.access});

  final OperationalReadAccess access;

  @override
  Future<ReportingContext> getContext(String taskId) async {
    try {
      DeliveryDtoReaders.checkUuid(taskId, 'p_task_id');
    } on FormatException {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }

    final outcome = await access.run<_ContextOutcome>(
      roles: const {'shipper'},
      action: (identity) async {
        identity.ensureCurrent();
        dynamic raw;
        try {
          raw = await access.client
              .rpc(
                'get_my_delivery_reporting_context',
                params: <String, dynamic>{'p_task_id': taskId},
              )
              .retry(enabled: false)
              .timeout(access.readTimeout);
        } on PostgrestException catch (error) {
          final mapped = _mapPostgrestError(error);
          if (mapped is OutboundBusinessFailure) {
            identity.ensureCurrent();
            return _ContextOutcome.failure(mapped);
          }
          throw mapped;
        }
        identity.ensureCurrent();

        try {
          final dto = ReportingContextDto.fromJson(
            _object(raw, 'reporting context'),
            requestedTaskId: taskId,
          );
          identity.ensureCurrent();
          return _ContextOutcome.success(dto.toDomain());
        } on FormatException catch (_) {
          return _ContextOutcome.failure(
            const OperationalFailure(OperationalFailureCode.invalidData),
          );
        } on TypeError catch (_) {
          return _ContextOutcome.failure(
            const OperationalFailure(OperationalFailureCode.invalidData),
          );
        }
      },
    );
    final failure = outcome.failure;
    if (failure != null) throw failure;
    final context = outcome.context;
    if (context == null) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
    return context;
  }

  @override
  Future<ReportingAck> execute(ReportingCommand command) async {
    try {
      _validateCommand(command);
    } on FormatException {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }

    final capturedSession = access.currentSession;
    var dispatched = false;
    final outcome = await access
        .run<_AckOutcome>(
          roles: const {'shipper'},
          action: (identity) async {
            identity.ensureCurrent();
            dynamic raw;
            try {
              dispatched = true;
              raw = await access.client
                  .rpc(command.operation.rpcName, params: _paramsFor(command))
                  .retry(enabled: false)
                  .timeout(access.readTimeout);
            } on PostgrestException catch (error) {
              final mapped = _mapPostgrestError(error);
              if (mapped is OutboundBusinessFailure) {
                identity.ensureCurrent();
                return _AckOutcome.failure(mapped);
              }
              throw mapped;
            }
            identity.ensureCurrent();

            try {
              final dto = ReportingAckDto.fromJson(
                _object(raw, 'reporting acknowledgement'),
                command: command,
              );
              identity.ensureCurrent();
              return _AckOutcome.success(dto.toDomain());
            } on FormatException catch (_) {
              // A response after dispatch is not proof of a committed write.
              // Keep the caller's request UUID and require an explicit retry.
              return _AckOutcome.failure(
                const OutboundAcknowledgementFailure(),
              );
            } on TypeError catch (_) {
              return _AckOutcome.failure(
                const OutboundAcknowledgementFailure(),
              );
            }
          },
        )
        .catchError((Object error) {
          final current = access.currentSession;
          if (dispatched &&
              error is OperationalFailure &&
              error.code == OperationalFailureCode.sessionExpired &&
              !identical(capturedSession, current) &&
              current.userId != null &&
              current.userId == capturedSession.userId &&
              current.failure == null) {
            // The RPC may have committed before a same-user token refresh.
            // Preserve the command envelope rather than issuing a new key.
            throw const OutboundAcknowledgementFailure();
          }
          throw error;
        });

    final failure = outcome.failure;
    if (failure != null) throw failure;
    final ack = outcome.ack;
    if (ack == null) {
      throw const OutboundAcknowledgementFailure();
    }
    return ack;
  }

  static Map<String, dynamic> _paramsFor(ReportingCommand command) {
    if (command.operation == ReportingOperation.handover) {
      return <String, dynamic>{
        'p_task_id': command.taskId,
        'p_request_id': command.requestId,
        // Never send product/variant text, price, order identity or any
        // client-owned state. The server re-reads its immutable snapshot.
        'p_items': command.items
            .map(
              (item) => <String, dynamic>{
                'order_item_id': item.orderItemId,
                'quantity': item.quantity,
              },
            )
            .toList(growable: false),
      };
    }
    return <String, dynamic>{
      'p_task_id': command.taskId,
      'p_request_id': command.requestId,
      'p_incident_kind': command.incidentKind!.value,
      'p_reason': command.reason!.trim(),
    };
  }

  static void _validateCommand(ReportingCommand command) {
    DeliveryDtoReaders.checkUuid(command.taskId, 'p_task_id');
    DeliveryDtoReaders.checkUuid(command.requestId, 'p_request_id');

    switch (command.operation) {
      case ReportingOperation.handover:
        if (command.incidentKind != null ||
            command.reason != null ||
            command.items.isEmpty) {
          throw DeliveryDtoReaders.invalid('command', 'handover items only');
        }
        _validateItems(command.items);
      case ReportingOperation.incident:
        final reason = command.reason?.trim();
        if (command.items.isNotEmpty ||
            command.incidentKind == null ||
            reason == null ||
            reason.isEmpty) {
          throw DeliveryDtoReaders.invalid(
            'command',
            'incident kind and a non-blank reason only',
          );
        }
    }
  }

  static void _validateItems(List<ReportItem> items) {
    String? previous;
    final seen = <String>{};
    for (final item in items) {
      DeliveryDtoReaders.checkUuid(item.orderItemId, 'order_item_id');
      if (item.quantity < 1 || item.quantity > maxReportingItemQuantity) {
        throw DeliveryDtoReaders.invalid(
          'quantity',
          'a positive 32-bit integer',
        );
      }
      final id = item.orderItemId.toLowerCase();
      if (!seen.add(id)) {
        throw DeliveryDtoReaders.invalid('p_items', 'unique order item UUIDs');
      }
      // The deployed RPC requires the canonical UUID ascending order.  This
      // also makes the outgoing payload deterministic for an idempotency key.
      if (previous != null && id.compareTo(previous) < 0) {
        throw DeliveryDtoReaders.invalid(
          'p_items',
          'order item UUIDs in ascending order',
        );
      }
      previous = id;
    }
  }

  static Map<String, dynamic> _object(dynamic raw, String label) {
    if (raw is! Map) throw FormatException('Expected $label object');
    try {
      return Map<String, dynamic>.from(raw);
    } on TypeError {
      throw FormatException('Expected a string-keyed $label object');
    }
  }
}

final class _ContextOutcome {
  const _ContextOutcome.success(this.context) : failure = null;
  const _ContextOutcome.failure(this.failure) : context = null;

  final ReportingContext? context;
  final Object? failure;
}

final class _AckOutcome {
  const _AckOutcome.success(this.ack) : failure = null;
  const _AckOutcome.failure(this.failure) : ack = null;

  final ReportingAck? ack;
  final Object? failure;
}

Object _mapPostgrestError(PostgrestException error) {
  if (error.code == 'PT409' || error.code == 'P0001') {
    return switch (error.message.trim()) {
      'STATE_CONFLICT' => const OutboundBusinessFailure(
        OutboundBusinessFailureCode.stateConflict,
      ),
      'IDEMPOTENCY_CONFLICT' => const OutboundBusinessFailure(
        OutboundBusinessFailureCode.idempotencyConflict,
      ),
      'CUSTODY_UNRESOLVED' => const OutboundBusinessFailure(
        OutboundBusinessFailureCode.custodyUnresolved,
      ),
      'ITEMS_MISMATCH' => const OutboundBusinessFailure(
        OutboundBusinessFailureCode.itemsMismatch,
      ),
      'INVALID_ARGUMENT' => const OperationalFailure(
        OperationalFailureCode.invalidData,
      ),
      // Unsupported pickup/redelivery contexts are intentionally not given a
      // fabricated success or a new public error class.
      'UNSUPPORTED_TASK_KIND' => const OperationalFailure(
        OperationalFailureCode.invalidData,
      ),
      _ => const OperationalFailure(OperationalFailureCode.unexpected),
    };
  }
  if (error.code == '42501' || error.code == '403') {
    return const OperationalFailure(OperationalFailureCode.permissionDenied);
  }
  if (error.code == '22023' || error.code == '22P02') {
    return const OperationalFailure(OperationalFailureCode.invalidData);
  }
  if (error.code == '404' ||
      error.code == '42883' ||
      error.code == '42P01' ||
      error.code == 'PGRST202' ||
      error.code == 'PGRST205' ||
      error.code == '500' ||
      error.code == '502' ||
      error.code == '503' ||
      error.code == '504') {
    return const OperationalFailure(OperationalFailureCode.backendUnavailable);
  }
  return mapOperationalFailure(error);
}

// Feature-qualified alias retained for dependency wiring that names adapters
// after the feature rather than the Supabase implementation.
typedef DeliveryReportingRepositoryImpl = SupabaseDeliveryReportingRepository;
