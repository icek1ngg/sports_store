import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/unsupported_data_exception.dart';
import 'order_mutation_receipt.dart';

enum OperationResultState {
  committed('committed'),
  failed('failed'),
  notFound('not_found');

  const OperationResultState(this.wireValue);

  final String wireValue;

  static OperationResultState parse(Object? raw) {
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: 'state',
      enumName: 'OperationResultState',
      rawValue: raw,
    );
  }
}

class OperationResult {
  const OperationResult._({
    required this.state,
    required this.receipt,
    required this.failure,
  });

  const OperationResult.committed(OrderMutationReceipt receipt)
    : this._(
        state: OperationResultState.committed,
        receipt: receipt,
        failure: null,
      );

  const OperationResult.failed(AppFailure failure)
    : this._(
        state: OperationResultState.failed,
        receipt: null,
        failure: failure,
      );

  const OperationResult.notFound()
    : this._(
        state: OperationResultState.notFound,
        receipt: null,
        failure: null,
      );

  final OperationResultState state;
  final OrderMutationReceipt? receipt;
  final AppFailure? failure;

  bool get isCommitted => state == OperationResultState.committed;
  bool get isFailed => state == OperationResultState.failed;
  bool get isNotFound => state == OperationResultState.notFound;
}
