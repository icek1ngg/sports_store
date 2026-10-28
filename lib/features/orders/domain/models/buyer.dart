import 'model_validators.dart';

class Buyer {
  Buyer({required String id, required this.fullName})
    : id = validateUuidValue(id);

  final String id;
  final String? fullName;

  Map<String, Object?> toMap() => {'id': id, 'full_name': fullName};
}
