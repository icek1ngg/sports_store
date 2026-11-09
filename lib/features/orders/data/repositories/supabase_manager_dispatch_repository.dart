import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/manager_dispatch_repository.dart';

class SupabaseManagerDispatchRepository implements ManagerDispatchRepository {
  SupabaseManagerDispatchRepository(this.client);
  final SupabaseClient client;

  @override
  Future<List<DispatchShipper>> loadShippers() async {
    try {
      final rows = await client
          .from('profiles')
          .select('id,full_name')
          .eq('role', 'shipper')
          .order('full_name')
          .timeout(const Duration(seconds: 15));
      return rows
          .map(
            (r) => DispatchShipper(
              id: r['id'] as String,
              name: (r['full_name'] as String?)?.trim().isNotEmpty == true
                  ? r['full_name'] as String
                  : 'Shipper',
            ),
          )
          .toList();
    } catch (_) {
      throw const DispatchFailure(
        'Không tải được danh sách shipper. Vui lòng thử lại.',
      );
    }
  }

  @override
  Future<void> prepareAndAssign({
    required String orderId,
    required String shipperId,
    required String requestId,
  }) async {
    try {
      final result = await client
          .rpc(
            'prepare_and_assign_delivery',
            params: {
              'p_order_id': orderId,
              'p_shipper_id': shipperId,
              'p_request_id': requestId,
              'p_prepared': true,
            },
          )
          .retry(enabled: false)
          .timeout(const Duration(seconds: 30));
      if (result is! Map ||
          result['order_id'] != orderId ||
          result['shipper_id'] != shipperId ||
          result['request_id'] != requestId ||
          result['order_status'] != 'awaiting_pickup') {
        throw const DispatchFailure(
          'Chưa xác nhận được kết quả phân công. Thử lại với cùng shipper.',
          ambiguous: true,
        );
      }
    } on DispatchFailure {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == '42501' || e.code == 'PT401' || e.code == 'PT403') {
        throw const DispatchFailure(
          'Bạn không còn quyền phân công. Vui lòng tải lại màn hình.',
        );
      }
      if (e.code == 'PT409' || e.code == '22023' || e.code == 'PT422') {
        throw const DispatchFailure(
          'Đơn hoặc shipper đã thay đổi, hoặc hàng chưa được xác nhận chuẩn bị. Đóng hộp thoại và tải lại đơn.',
        );
      }
      if (e.code == 'PGRST202' || e.code == '42883') {
        throw const DispatchFailure(
          'Chức năng chuẩn bị và phân công chưa được triển khai trên máy chủ.',
        );
      }
      throw const DispatchFailure(
        'Chưa rõ kết quả phân công. Hãy thử lại với cùng shipper.',
        ambiguous: true,
      );
    } catch (_) {
      throw const DispatchFailure(
        'Mất kết nối khi phân công. Thử lại với cùng shipper để tránh tạo trùng.',
        ambiguous: true,
      );
    }
  }
}
