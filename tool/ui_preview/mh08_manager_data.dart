import 'package:sports_store/features/orders/domain/models/order_status.dart';

import 'mh08_manager_record.dart';

export 'mh08_manager_record.dart' show mh08PreviewAsOf;

/// Deterministic, read-only MH08 data. Values exercise every manager-list
/// state without pretending to be a live Supabase response.
List<Mh08ManagerRecord> buildMh08ManagerRecords() => [
  const Mh08ManagerSeed(
    index: 1,
    status: OrderStatus.pendingConfirmation,
    accountName: 'Nguyễn Minh Anh',
    managerActions: true,
    items: [
      Mh08ManagerItemSpec('Giày chạy bộ AirFlex', 'Đen / 42', 1290000, 1),
      Mh08ManagerItemSpec('Áo thể thao DryFit', 'Xanh navy / M', 320000, 2),
    ],
  ),
  const Mh08ManagerSeed(
    index: 2,
    status: OrderStatus.pendingConfirmation,
    accountName: 'Trần Quốc Bảo',
    managerActions: false,
    items: [
      Mh08ManagerItemSpec('Vợt cầu lông Carbon Pro', '4U / G5', 890000, 1),
    ],
  ),
  const Mh08ManagerSeed(
    index: 3,
    status: OrderStatus.preparing,
    accountName: 'Lê Hoàng Nam',
    managerActions: false,
    items: [Mh08ManagerItemSpec('Bóng đá sân cỏ Select', 'Size 5', 560000, 1)],
  ),
  const Mh08ManagerSeed(
    index: 4,
    status: OrderStatus.delivering,
    accountName: 'Phạm Thu Hà',
    managerActions: false,
    items: [Mh08ManagerItemSpec('Ba lô chạy trail', '18L / Đen', 740000, 1)],
  ),
  const Mh08ManagerSeed(
    index: 5,
    status: OrderStatus.delivered,
    accountName: 'Vũ Gia Hân',
    managerActions: false,
    items: [Mh08ManagerItemSpec('Tất chạy Cushion', 'Đen / L', 115000, 3)],
  ),
  const Mh08ManagerSeed(
    index: 6,
    status: OrderStatus.awaitingRedelivery,
    accountName: 'Đỗ Thanh Tùng',
    managerActions: false,
    items: [
      Mh08ManagerItemSpec('Giày bóng rổ Court', 'Trắng / 43', 1590000, 1),
    ],
  ),
  const Mh08ManagerSeed(
    index: 7,
    status: OrderStatus.awaitingPickup,
    accountName: null,
    managerActions: false,
    nullProjection: true,
    items: [Mh08ManagerItemSpec('Thảm yoga Eco', '6mm / Tím', 430000, 1)],
  ),
  const Mh08ManagerSeed(
    index: 8,
    status: OrderStatus.delivered,
    accountName: 'Nguyễn Thảo Vy',
    managerActions: false,
    items: [
      Mh08ManagerItemSpec('Áo jersey bóng đá', 'L / Đỏ', 610000, 1),
      Mh08ManagerItemSpec('Quần short training', 'M / Đen', 420000, 1),
      Mh08ManagerItemSpec('Bình nước thể thao', '750ml / Xanh', 190000, 2),
    ],
  ),
  const Mh08ManagerSeed(
    index: 9,
    status: OrderStatus.delivering,
    accountName:
        'Cửa hàng thể thao Thành phố Hà Nội – Bộ phận mua sắm doanh nghiệp',
    managerActions: false,
    recipient:
        'Người nhận hàng tại Trung tâm thể thao Thành phố Hà Nội, quầy số 12',
    address: 'Tầng 7, tòa nhà thể thao Thành phố Hà Nội, 18 phố Huế, quận Hai Bà Trưng, Hà Nội',
    items: [
      Mh08ManagerItemSpec(
        'Áo khoác gió Runner phiên bản giới hạn dành cho câu lạc bộ',
        'Xám / XXL',
        980000,
        4,
      ),
    ],
  ),
  const Mh08ManagerSeed(
    index: 10,
    status: OrderStatus.rejected,
    accountName: 'Trương Minh Khoa',
    managerActions: false,
    items: [Mh08ManagerItemSpec('Dây nhảy Speed Rope', 'Đen / 3m', 180000, 1)],
  ),
].map(Mh08ManagerRecord.fromSeed).toList(growable: false);
