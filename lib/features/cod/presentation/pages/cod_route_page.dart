import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/cod_providers.dart';
import 'shipper_cod_page.dart';
import '../widgets/manager_cod_panel.dart';

/// One MH12 route with server-role-scoped shipper/manager presentations.
class CodRoutePage extends ConsumerWidget {
  const CodRoutePage({this.orderId, super.key});

  final String? orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(codScreenRoleProvider);
    return Semantics(
      key: ValueKey('mh12-outlet'),
      label: 'Đối soát COD',
      child: role.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: ref.read(retryCodScreenRoleProvider),
            child: const Text('Không thể kiểm tra quyền. Thử lại'),
          ),
        ),
        data: (value) => value == 'shipper'
            ? ShipperCodPage(orderId: orderId)
            : value == 'manager'
            ? ManagerCodPanel(orderId: orderId)
            : const Center(child: Text('Bạn không có quyền truy cập.')),
      ),
    );
  }
}
