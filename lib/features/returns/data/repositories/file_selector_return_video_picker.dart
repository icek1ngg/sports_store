import 'package:file_selector/file_selector.dart';

import '../../domain/models/return_request_submission.dart';
import '../../domain/repositories/return_video_picker.dart';

final class FileSelectorReturnVideoPicker implements ReturnVideoPicker {
  const FileSelectorReturnVideoPicker();

  @override
  Future<ReturnVideoFile?> pickVideo() async {
    final XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Video',
            extensions: ReturnVideoFile.extensions,
            mimeTypes: [
              'video/mp4',
              'video/quicktime',
              'video/x-m4v',
              'video/webm',
              'video/3gpp',
            ],
            uniformTypeIdentifiers: ['public.movie'],
          ),
        ],
      );
    } catch (_) {
      throw const ReturnVideoPickFailure('Không mở được trình chọn tệp.');
    }
    if (file == null) return null;
    if (!ReturnVideoFile.isSupportedName(file.name)) {
      throw const ReturnVideoPickFailure(
        'Chỉ nhận video MP4, MOV, M4V, WEBM hoặc 3GP.',
      );
    }
    final size = await file.length().timeout(const Duration(seconds: 30));
    if (size <= 0 || size > ReturnVideoFile.maxBytes) {
      throw const ReturnVideoPickFailure(
        'Video cần có dung lượng từ 1 byte đến 100 MB.',
      );
    }
    return ReturnVideoFile(
      name: file.name,
      bytes: await file.readAsBytes().timeout(const Duration(seconds: 60)),
      mimeType: ReturnVideoFile.mimeTypeFor(file.name),
    );
  }
}
