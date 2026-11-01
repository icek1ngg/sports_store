import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/models/return_reason.dart';
import '../../domain/models/return_request_submission.dart';
import 'create_return_sections.dart';

const _sectionTitle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
  height: 1.3,
  color: AppColors.ink,
);
const _helper = TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.mute);
const _errorStyle = TextStyle(fontSize: 12.5, color: AppColors.sale);

class ReturnFormSection extends StatelessWidget {
  const ReturnFormSection({
    required this.title,
    required this.child,
    this.helper,
    super.key,
  });

  final String title;
  final String? helper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: _sectionTitle),
        if (helper != null) ...[
          const SizedBox(height: 2),
          Text(helper!, style: _helper),
        ],
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class ReturnReasonSummary extends StatelessWidget {
  const ReturnReasonSummary({
    required this.reason,
    required this.onChange,
    super.key,
  });

  final ReturnReason reason;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: ReturnPalette.selectedSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairlineSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Lý do trả hàng', style: _helper),
                const SizedBox(height: 2),
                Text(
                  reason.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('mh13-change-reason'),
            onPressed: onChange,
            style: TextButton.styleFrom(foregroundColor: AppColors.info),
            child: const Text('Đổi'),
          ),
        ],
      ),
    );
  }
}

InputDecoration returnInputDecoration({
  required String label,
  String? hint,
  String? error,
}) => InputDecoration(
  labelText: label,
  hintText: hint,
  errorText: error,
  filled: true,
  fillColor: AppColors.surface,
  alignLabelWithHint: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.hairlineSoft),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.hairline),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.info, width: 1.5),
  ),
);

class ReturnTextField extends StatelessWidget {
  const ReturnTextField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.onChanged,
    required this.enabled,
    this.hint,
    this.error,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    super.key,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? error;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: AppColors.ink),
      decoration: returnInputDecoration(label: label, hint: hint, error: error),
    );
  }
}

class ReturnVideoField extends StatelessWidget {
  const ReturnVideoField({
    required this.video,
    required this.onPick,
    required this.onRemove,
    this.error,
    this.pickLabel = 'Chọn video mở kiện',
    this.pickKey = const ValueKey('mh13-pick-video'),
    super.key,
  });

  final ReturnVideoFile? video;
  final VoidCallback? onPick;
  final VoidCallback? onRemove;
  final String? error;
  final String pickLabel;
  final Key pickKey;

  @override
  Widget build(BuildContext context) {
    final selected = video;
    final borderColor = error != null ? AppColors.sale : AppColors.hairline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected == null)
          Material(
            color: AppColors.softCloud,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: borderColor),
            ),
            child: InkWell(
              key: pickKey,
              borderRadius: BorderRadius.circular(14),
              onTap: onPick,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 22,
                  horizontal: 16,
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.video_call_outlined,
                      size: 30,
                      color: AppColors.ink,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pickLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'MP4, MOV, WEBM · tối đa 100 MB',
                      style: _helper,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Container(
            key: const ValueKey('mh13-video-selected'),
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairlineSoft),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.onPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(_formatSize(selected.sizeBytes), style: _helper),
                    ],
                  ),
                ),
                TextButton(
                  key: const ValueKey('mh13-replace-video'),
                  onPressed: onPick,
                  style: TextButton.styleFrom(foregroundColor: AppColors.info),
                  child: const Text('Đổi'),
                ),
                IconButton(
                  key: const ValueKey('mh13-remove-video'),
                  tooltip: 'Xóa video',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, color: AppColors.mute),
                ),
              ],
            ),
          ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error!, style: _errorStyle),
        ],
      ],
    );
  }
}

String _formatSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1).replaceAll('.', ',')} MB';
  }
  final kb = (bytes / 1024).ceil();
  return '$kb KB';
}

class ReturnFailureBanner extends StatelessWidget {
  const ReturnFailureBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.sale),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.saleDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReturnSubmitBar extends StatelessWidget {
  const ReturnSubmitBar({
    required this.label,
    required this.onPressed,
    required this.note,
    this.busyLabel,
    super.key,
  });

  final String label;
  final String? busyLabel;
  final VoidCallback? onPressed;
  final String note;

  @override
  Widget build(BuildContext context) {
    final busy = busyLabel != null;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: FilledButton(
                  key: const ValueKey('mh13-send'),
                  onPressed: busy ? null : onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: AppColors.surfaceContainerHigh,
                    disabledForegroundColor: AppColors.ash,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: busy
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.ash,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(busyLabel!),
                          ],
                        )
                      : Text(label),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                note,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.mute),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
