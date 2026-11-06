import '../models/manager_return.dart';

/// Picks one local evidence file (photo or PDF). Returns null on cancel and
/// throws [ManagerEvidencePickFailure] for unsupported or oversized files.
abstract interface class ManagerEvidencePicker {
  Future<ManagerEvidenceFile?> pickEvidence();
}

class ManagerEvidencePickFailure implements Exception {
  const ManagerEvidencePickFailure(this.message);

  final String message;
}
