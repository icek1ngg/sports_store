import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/return_reason.dart';
import 'create_return_state.dart';

/// Identifies one MH13 form. `initialReason` lets a caller restore a draft.
typedef CreateReturnFormArgs = ({String orderId, ReturnReason? initialReason});

final createReturnViewModelProvider = NotifierProvider.autoDispose
    .family<CreateReturnViewModel, CreateReturnFormState, CreateReturnFormArgs>(
      CreateReturnViewModel.new,
    );

/// Step 1 of MH13: holds the selected reason. Submission (video evidence and
/// the server RPC) belongs to step 2 and is not implemented here.
class CreateReturnViewModel extends Notifier<CreateReturnFormState> {
  CreateReturnViewModel(this.args);

  final CreateReturnFormArgs args;

  @override
  CreateReturnFormState build() =>
      CreateReturnFormState(reason: args.initialReason);

  void selectReason(ReturnReason reason) {
    if (state.reason == reason) return;
    state = CreateReturnFormState(reason: reason);
  }
}
