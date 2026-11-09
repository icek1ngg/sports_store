import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/foundation_providers.dart';
import '../../core/state/session_scope.dart';
import '../../features/auth/presentation/view_models/auth_providers.dart';
import '../../shared/widgets/feature_access_gate.dart';

/// Strict UUID validation shared by the order routes.
///
/// Route parameters are untrusted input. Keeping this check at the route
/// boundary prevents a malformed identifier from reaching a feature read.
final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool isStrictUuid(String value) => _uuidPattern.hasMatch(value);

/// Session boundary for the four order/notification-owned screens.
///
/// [FeatureAccessGate] remains the single presentation access policy: an
/// unresolved scope is loading, a signed-out/expired scope is hidden, and a
/// role mismatch is denied. The extra keyed subtree is intentional. Auth
/// generation changes must dispose the entire feature subtree rather than
/// allowing local UI state from the previous account to be reused. The router
/// separately closes root-level popup routes when this scope changes.
class FourScreenRouteBoundary extends ConsumerStatefulWidget {
  const FourScreenRouteBoundary({
    required this.roles,
    required this.child,
    this.invalidId = false,
    this.invalidIdMessage = 'Mã truy cập không hợp lệ.',
    super.key,
  });

  final Set<String> roles;
  final Widget child;
  final bool invalidId;
  final String invalidIdMessage;

  @override
  ConsumerState<FourScreenRouteBoundary> createState() =>
      _FourScreenRouteBoundaryState();
}

class _FourScreenRouteBoundaryState
    extends ConsumerState<FourScreenRouteBoundary> {
  var _profileRevalidationRequested = false;

  @override
  Widget build(BuildContext context) {
    if (widget.invalidId) {
      return _FourScreenInvalidIdPage(message: widget.invalidIdMessage);
    }

    // A route entry is an opportunity to revalidate a cached Auth profile.
    // This is not a second authority: featureSessionScopeProvider remains the
    // only value consumed by the gate. The request is one-shot per route
    // mount, so scope changes cannot create an invalidation loop.
    if (!_profileRevalidationRequested) {
      _profileRevalidationRequested = true;
      scheduleMicrotask(() {
        if (mounted) ref.invalidate(currentProfileProvider);
      });
    }

    // Watch the canonical Auth-owned scope here as well as inside the gate.
    // This gives the subtree a fresh identity for every trusted generation,
    // including a role/account switch where the route URI is unchanged.
    final scope = ref.watch(featureSessionScopeProvider);
    return FeatureAccessGate(
      roles: widget.roles,
      child: KeyedSubtree(
        key: ValueKey<_ScopeGeneration>(_ScopeGeneration.fromScope(scope)),
        child: widget.child,
      ),
    );
  }
}

/// A value key carrying the complete trusted scope, not a user-editable role
/// or identifier. Equality tracks the generation and therefore tears down
/// nested modal state whenever Auth invalidates the session.
class _ScopeGeneration {
  const _ScopeGeneration({
    required this.userId,
    required this.role,
    required this.generation,
    required this.roleResolved,
  });

  factory _ScopeGeneration.fromScope(SessionScope scope) => _ScopeGeneration(
    userId: scope.userId,
    role: scope.role,
    generation: scope.generation,
    roleResolved: scope.roleResolved,
  );

  final String? userId;
  final String? role;
  final int generation;
  final bool roleResolved;

  @override
  bool operator ==(Object other) =>
      other is _ScopeGeneration &&
      userId == other.userId &&
      role == other.role &&
      generation == other.generation &&
      roleResolved == other.roleResolved;

  @override
  int get hashCode => Object.hash(userId, role, generation, roleResolved);
}

class _FourScreenInvalidIdPage extends StatelessWidget {
  const _FourScreenInvalidIdPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sports Store')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            key: const ValueKey('navigation-invalid-id'),
            liveRegion: true,
            label: message,
            child: Text(message),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Quay lại'),
          ),
        ],
      ),
    ),
  );
}
