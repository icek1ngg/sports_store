class OrderCapabilities {
  const OrderCapabilities({
    required this.canCancelCustomer,
    required this.canConfirm,
    required this.canReject,
    required this.canCancelExceptional,
    required this.canAssign,
    required this.canReassign,
    required this.canArrangeSecondAttempt,
    required this.canRequestEarlyReturn,
    required this.canReceiveUndelivered,
    required this.canOpenReturnCreation,
  });

  const OrderCapabilities.none()
    : canCancelCustomer = false,
      canConfirm = false,
      canReject = false,
      canCancelExceptional = false,
      canAssign = false,
      canReassign = false,
      canArrangeSecondAttempt = false,
      canRequestEarlyReturn = false,
      canReceiveUndelivered = false,
      canOpenReturnCreation = false;

  final bool canCancelCustomer;
  final bool canConfirm;
  final bool canReject;
  final bool canCancelExceptional;
  final bool canAssign;
  final bool canReassign;
  final bool canArrangeSecondAttempt;
  final bool canRequestEarlyReturn;
  final bool canReceiveUndelivered;
  final bool canOpenReturnCreation;

  Map<String, bool> toMap() => {
    'can_cancel_customer': canCancelCustomer,
    'can_confirm': canConfirm,
    'can_reject': canReject,
    'can_cancel_exceptional': canCancelExceptional,
    'can_assign': canAssign,
    'can_reassign': canReassign,
    'can_arrange_second_attempt': canArrangeSecondAttempt,
    'can_request_early_return': canRequestEarlyReturn,
    'can_receive_undelivered': canReceiveUndelivered,
    'can_open_return_creation': canOpenReturnCreation,
  };
}
