import '../../domain/models/checkout_failure.dart';
import '../../domain/models/placement_request.dart';
import '../../domain/models/placement_result.dart';
import '../../../cart/domain/models/cart_item.dart';

class CheckoutState {
  CheckoutState({
    required List<CartItem> items,
    this.isSubmitting = false,
    this.isRecovering = false,
    this.recoveryNotFound = false,
    this.failure,
    this.pendingRequest,
    this.result,
    this.userId,
  }) : items = List<CartItem>.unmodifiable(items);

  final List<CartItem> items;
  final bool isSubmitting;
  final bool isRecovering;
  final bool recoveryNotFound;
  final CheckoutFailure? failure;
  final PlacementRequest? pendingRequest;
  final PlacementResult? result;
  final String? userId;

  int get subtotalVnd =>
      items.fold<int>(0, (total, item) => total + (item.lineTotalVnd ?? 0));

  int get deliveryFeeVnd => 30000;

  int get estimatedTotalVnd => subtotalVnd + deliveryFeeVnd;

  /// Uses the server receipt after placement; before that it is an estimate
  /// from the current cart snapshot.
  int get displayedTotalVnd => result?.totalCodVnd ?? estimatedTotalVnd;

  bool get isEmpty => items.isEmpty;
  bool get hasPendingPlacement => pendingRequest != null;
  bool get isSuccess => result != null;
  bool get hasUnavailableItems => items.any((item) => !item.canCheckout);

  bool get canSubmit =>
      items.isNotEmpty &&
      !hasUnavailableItems &&
      !isSubmitting &&
      !isRecovering &&
      pendingRequest == null &&
      result == null;

  CheckoutState copyWith({
    List<CartItem>? items,
    bool? isSubmitting,
    bool? isRecovering,
    bool? recoveryNotFound,
    CheckoutFailure? failure,
    bool clearFailure = false,
    PlacementRequest? pendingRequest,
    bool clearPendingRequest = false,
    PlacementResult? result,
    bool clearResult = false,
    String? userId,
  }) => CheckoutState(
    items: items ?? this.items,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    isRecovering: isRecovering ?? this.isRecovering,
    recoveryNotFound: recoveryNotFound ?? this.recoveryNotFound,
    failure: clearFailure ? null : (failure ?? this.failure),
    pendingRequest: clearPendingRequest
        ? null
        : (pendingRequest ?? this.pendingRequest),
    result: clearResult ? null : (result ?? this.result),
    userId: userId ?? this.userId,
  );
}
