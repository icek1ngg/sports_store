import '../models/cod_receipt.dart';

/// Manager-only command contract for confirming a full COD handover.
abstract interface class CodReceiptRepository {
  Future<CodReceipt> confirmReceipt(CodReceiptCommand command);
}
