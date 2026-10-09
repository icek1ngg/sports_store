import 'model_validators.dart';
import 'order_status.dart';

class OrderWarning {
  OrderWarning({
    required this.code,
    required String sourceId,
    required String message,
    String? rawCode,
  }) : sourceId = validateUuidValue(sourceId, field: 'sourceId'),
       message = validateNonBlank(message, field: 'message'),
       rawCode = validateNonBlank(rawCode ?? code.wireValue, field: 'rawCode');

  final WarningCode code;
  final String sourceId;
  final String message;
  final String rawCode;

  Map<String, Object?> toMap() => {
    'code': rawCode,
    'source_id': sourceId,
    'message': message,
  };
}
