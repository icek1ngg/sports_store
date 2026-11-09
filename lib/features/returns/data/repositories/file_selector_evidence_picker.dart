import 'package:file_selector/file_selector.dart';

import '../../domain/models/manager_return.dart';
import '../../domain/repositories/manager_evidence_picker.dart';

/// `file_selector` adapter for inspection / transfer evidence.
final class FileSelectorEvidencePicker implements ManagerEvidencePicker {
  const FileSelectorEvidencePicker();

  static const _types = XTypeGroup(
    label: 'Ảnh hoặc PDF',
    extensions: ManagerEvidenceFile.extensions,
    mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'],
  );

  @override
  Future<ManagerEvidenceFile?> pickEvidence() async {
    final file = await openFile(acceptedTypeGroups: const [_types]);
    if (file == null) return null;
    final name = file.name;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (!ManagerEvidenceFile.extensions.contains(ext)) {
      throw const ManagerEvidencePickFailure(
        'Chỉ nhận ảnh JPG, PNG, WEBP hoặc tệp PDF.',
      );
    }
    final size = await file.length().timeout(const Duration(seconds: 30));
    if (size <= 0 || size > ManagerEvidenceFile.maxBytes) {
      throw const ManagerEvidencePickFailure('Tệp phải nhỏ hơn 10 MB.');
    }
    return ManagerEvidenceFile(
      name: name,
      bytes: await file.readAsBytes().timeout(const Duration(seconds: 60)),
      mimeType: switch (ext) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      },
    );
  }
}
