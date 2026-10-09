import 'package:flutter/material.dart';

import '../../core/errors/app_failure.dart';

/// Renders one of the common async states used by list and detail surfaces.
///
/// The caller decides whether content is authoritative. When [isStale] is
/// true, the existing [child] remains available for read-only use and receives
/// a visible freshness notice. An error object itself is never rendered; pass
/// a safe, localized [errorMessage] from the ViewModel instead. Session access
/// failures always take precedence over [child] so private data is not left
/// visible after expiry or permission loss.
class AsyncContent extends StatelessWidget {
  const AsyncContent({
    required this.child,
    this.hasData = false,
    this.isInitialLoading = false,
    this.isRefreshing = false,
    this.isEmpty = false,
    this.failure,
    this.errorMessage,
    this.isStale = false,
    this.isSessionUnavailable = false,
    this.isSessionExpired = false,
    this.onRetry,
    this.onSessionAction,
    this.emptyMessage = 'Chưa có dữ liệu',
    this.emptyActionLabel,
    this.onEmptyAction,
    this.staleMessage = 'Dữ liệu có thể chưa cập nhật',
    this.loadingLabel = 'Đang tải dữ liệu',
    this.errorTitle = 'Không thể tải dữ liệu',
    this.retryLabel = 'Thử lại',
    super.key,
  });

  final Widget child;

  /// Whether [child] represents an accepted snapshot from the server.
  ///
  /// This is separate from [isEmpty]: an accepted empty list has data and
  /// should render the empty state, while a null snapshot must render loading
  /// or error without exposing placeholder content.
  final bool hasData;
  final bool isInitialLoading;
  final bool isRefreshing;
  final bool isEmpty;

  /// A normalized failure from the feature ViewModel. Raw transport errors
  /// must be converted before reaching this widget.
  final AppFailure? failure;
  final String? errorMessage;
  final bool isStale;

  /// Use these flags for an unavailable/expired session when no AppFailure is
  /// available, such as an unresolved Auth scope during initial startup.
  final bool isSessionUnavailable;
  final bool isSessionExpired;
  final VoidCallback? onRetry;
  final VoidCallback? onSessionAction;
  final String emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final String staleMessage;
  final String loadingLabel;
  final String errorTitle;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final sessionExpired =
        isSessionExpired || failure?.code == AppFailure.unauthenticated;
    final sessionUnavailable =
        !sessionExpired &&
        (isSessionUnavailable ||
            failure?.code == AppFailure.forbiddenOrUnavailable);
    if (sessionExpired) {
      return SessionExpiredState(
        onAction: onSessionAction,
        actionLabel: onSessionAction == null ? null : 'Đăng nhập lại',
      );
    }
    if (sessionUnavailable) {
      return SessionUnavailableState(
        onAction: onSessionAction,
        actionLabel: onSessionAction == null ? null : 'Thử lại',
      );
    }

    if (isInitialLoading && !hasData) {
      return LoadingState(label: loadingLabel);
    }

    final hasError =
        failure != null ||
        (errorMessage != null && errorMessage!.trim().isNotEmpty);
    if (hasError && !hasData) {
      return ErrorState(
        title: errorTitle,
        message: errorMessage ?? _safeFailureMessage(failure),
        retryLabel: retryLabel,
        onRetry: onRetry,
      );
    }

    if (!hasData || isEmpty) {
      final empty = EmptyState(
        message: emptyMessage,
        actionLabel: emptyActionLabel,
        onAction: onEmptyAction,
      );
      if (isStale || hasError) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaleDataBanner(message: staleMessage),
            empty,
          ],
        );
      }
      return empty;
    }

    final showStale = isStale || hasError;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showStale) StaleDataBanner(message: staleMessage),
        if (isRefreshing)
          const SizedBox(
            height: 2,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        Flexible(child: child),
      ],
    );

    // A Column with a Flexible child cannot be laid out in an unbounded
    // height (for example inside a ListView). Use a simple wrapper in that
    // case while retaining the same stale/loading affordances.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showStale) StaleDataBanner(message: staleMessage),
              if (isRefreshing)
                const SizedBox(
                  height: 2,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              child,
            ],
          );
        }
        return content;
      },
    );
  }
}

String _safeFailureMessage(AppFailure? failure) {
  return switch (failure?.code) {
    AppFailure.network => 'Kiểm tra kết nối và thử lại.',
    AppFailure.externalDependencyUnavailable =>
      'Dịch vụ phụ trợ hiện chưa khả dụng.',
    AppFailure.unsupportedData => 'Dữ liệu không thể hiển thị lúc này.',
    _ => 'Không thể tải dữ liệu. Vui lòng thử lại.',
  };
}

class SessionExpiredState extends StatelessWidget {
  const SessionExpiredState({
    this.title = 'Phiên đăng nhập đã hết hạn',
    this.message = 'Vui lòng đăng nhập lại để tiếp tục.',
    this.actionLabel = 'Đăng nhập lại',
    this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _AccessState(
      icon: Icons.lock_clock_outlined,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class SessionUnavailableState extends StatelessWidget {
  const SessionUnavailableState({
    this.title = 'Không thể truy cập dữ liệu',
    this.message = 'Phiên đăng nhập hoặc quyền truy cập hiện không khả dụng.',
    this.actionLabel = 'Thử lại',
    this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _AccessState(
      icon: Icons.lock_outline,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class _AccessState extends StatelessWidget {
  const _AccessState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
              semanticLabel: title,
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({this.label = 'Đang tải dữ liệu', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: label,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.message,
    this.title = 'Không thể tải dữ liệu',
    this.retryLabel = 'Thử lại',
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
        ),
      ),
    );
  }
}

class StaleDataBanner extends StatelessWidget {
  const StaleDataBanner({
    this.message = 'Dữ liệu có thể chưa cập nhật',
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        width: double.infinity,
        color: colors.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.sync_problem_outlined, size: 18, color: colors.outline),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
