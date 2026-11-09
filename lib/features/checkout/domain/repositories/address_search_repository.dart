import '../models/address_suggestion.dart';

abstract interface class AddressSearchRepository {
  Future<List<AddressSuggestion>> search(String query);
}

enum AddressSearchFailureCode {
  network,
  unavailable,
  invalidData,
  invalidQuery,
}

/// Does not retain query strings, addresses, HTTP payloads or transport errors.
class AddressSearchFailure implements Exception {
  const AddressSearchFailure(this.code);

  final AddressSearchFailureCode code;

  String get userMessage => switch (code) {
    AddressSearchFailureCode.network =>
      'Không kết nối được dịch vụ tìm địa chỉ. Kiểm tra mạng rồi thử lại.',
    AddressSearchFailureCode.unavailable =>
      'Dịch vụ tìm địa chỉ đang bận. Vui lòng thử lại sau.',
    AddressSearchFailureCode.invalidData =>
      'Không đọc được kết quả địa chỉ. Vui lòng thử lại.',
    AddressSearchFailureCode.invalidQuery =>
      'Nhập tên đường, phường hoặc tòa nhà từ 3 đến 200 ký tự.',
  };

  @override
  String toString() => 'AddressSearchFailure(${code.name})';
}
