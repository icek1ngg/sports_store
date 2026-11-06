import 'dart:typed_data';

import 'return_reason.dart';

/// A locally selected unboxing video. Bytes stay in memory only until upload.
class ReturnVideoFile {
  const ReturnVideoFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  static const maxBytes = 100 * 1024 * 1024;
  static const extensions = ['mp4', 'mov', 'm4v', 'webm', '3gp'];

  final String name;
  final Uint8List bytes;
  final String mimeType;

  int get sizeBytes => bytes.length;

  String get extension => _extensionOf(name) ?? 'mp4';

  static String? _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    return extensions.contains(ext) ? ext : null;
  }

  static bool isSupportedName(String fileName) =>
      _extensionOf(fileName) != null;

  static String mimeTypeFor(String fileName) =>
      switch (_extensionOf(fileName)) {
        'mov' => 'video/quicktime',
        'm4v' => 'video/x-m4v',
        'webm' => 'video/webm',
        '3gp' => 'video/3gpp',
        _ => 'video/mp4',
      };
}

/// Exact payload of `submit_return_request`. [requestId] is the idempotency
/// key and must be reused unchanged when retrying an ambiguous attempt.
class ReturnRequestCommand {
  const ReturnRequestCommand({
    required this.orderId,
    required this.requestId,
    required this.reason,
    required this.description,
    required this.videoObjectPath,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
  });

  final String orderId;
  final String requestId;
  final ReturnReason reason;
  final String description;
  final String videoObjectPath;
  final String bankName;
  final String accountNumber;
  final String accountHolder;

  Map<String, Object?> toRpcParams() => {
    'p_order_id': orderId,
    'p_request_id': requestId,
    'p_reason': reason.wireValue,
    'p_description': description,
    'p_video_object_path': videoObjectPath,
    'p_bank_name': bankName,
    'p_account_number': accountNumber,
    'p_account_holder': accountHolder,
  };
}

class ReturnRequestReceipt {
  const ReturnRequestReceipt({
    required this.returnRequestId,
    required this.orderId,
    required this.status,
    required this.submittedAt,
    required this.replayed,
  });

  final String returnRequestId;
  final String orderId;
  final String status;
  final DateTime submittedAt;
  final bool replayed;
}
