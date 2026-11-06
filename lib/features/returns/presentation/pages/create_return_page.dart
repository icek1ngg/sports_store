import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../domain/models/return_reason.dart';
import '../view_models/create_return_state.dart';
import '../view_models/create_return_view_model.dart';
import '../widgets/create_return_sections.dart';

/// MH13 step 1: review the delivered order, deadline and choose a reason.
///
/// All order data arrives through [order]; the page does not load anything
/// itself, so the caller (router/ViewModel) can supply Supabase data later.
class CreateReturnPage extends ConsumerWidget {
  const CreateReturnPage({
    required this.order,
    this.initialReason,
    this.onBack,
    this.onHelp,
    this.onContinue,
    super.key,
  });

  final ReturnOrderOverview order;
  final ReturnReason? initialReason;
  final VoidCallback? onBack;
  final VoidCallback? onHelp;

  /// Called with the chosen reason when the customer presses the submit
  /// button. Step 2 (video evidence + RPC) is handled by the caller.
  final ValueChanged<ReturnReason>? onContinue;

  static const stepLabel = 'Bước 1/2';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (orderId: order.orderId, initialReason: initialReason);
    final form = ref.watch(createReturnViewModelProvider(args));
    final viewModel = ref.read(createReturnViewModelProvider(args).notifier);
    final reason = form.reason;
    final eligible = order.isEligible;
    final canContinue = eligible && reason != null && onContinue != null;

    return AppTheme.notificationsScope(
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              CreateReturnHeader(
                stepLabel: stepLabel,
                onBack: onBack ?? () => Navigator.maybePop(context),
                onHelp: onHelp,
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('mh13-scroll'),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    ReturnOrderCard(order: order),
                    const SizedBox(height: 14),
                    ReturnTotalRow(totalVnd: order.totalPaidVnd),
                    const SizedBox(height: 20),
                    ReturnDeadlineNotice(order: order),
                    const SizedBox(height: 28),
                    ReturnReasonSection(
                      selected: reason,
                      onSelected: eligible ? viewModel.selectReason : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: CreateReturnSubmitBar(
          onPressed: canContinue ? () => onContinue!(reason) : null,
        ),
      ),
    );
  }
}
