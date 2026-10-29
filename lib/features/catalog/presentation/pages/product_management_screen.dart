import 'package:flutter/material.dart';

import '../../../../shared/widgets/prm_preview_widgets.dart';

class _Product {
  _Product({
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    required this.image,
    this.imageUrl = '',
    this.photoIndex = -1,
    this.active = true,
    this.variant = 'M / L / XL',
  });
  String name;
  String category;
  int price;
  int stock;
  IconData image;
  String imageUrl;
  int photoIndex;
  bool active;
  bool selected = false;
  String variant;
}

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key});
  @override
  State<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  final _search = TextEditingController();
  String _category = 'Tất cả danh mục';
  String _status = 'Trạng thái';
  int _page = 1;
  final List<_Product> _products = [
    _Product(
      name: 'Giày chạy bộ Nike Air Zoom',
      category: 'Giày thể thao',
      price: 2890000,
      stock: 50,
      image: Icons.directions_run_rounded,
      photoIndex: 0,
      variant: 'Trắng / Xám',
    ),
    _Product(
      name: 'Áo thun thể thao nam',
      category: 'Áo thể thao',
      price: 350000,
      stock: 120,
      image: Icons.checkroom_rounded,
      photoIndex: 1,
      variant: 'S / M / L / XL',
    ),
    _Product(
      name: 'Quần short thể thao',
      category: 'Quần áo',
      price: 290000,
      stock: 80,
      image: Icons.short_text_rounded,
      photoIndex: 2,
      variant: 'M / L / XL',
    ),
    _Product(
      name: 'Mũ thể thao Nike',
      category: 'Phụ kiện',
      price: 450000,
      stock: 30,
      image: Icons.sports_baseball_rounded,
      active: false,
      variant: 'Đen',
    ),
    _Product(
      name: 'Vợt cầu lông Yonex',
      category: 'Dụng cụ thể thao',
      price: 1990000,
      stock: 20,
      image: Icons.sports_tennis_rounded,
      photoIndex: 3,
      variant: '4U / 5U',
    ),
  ];
  final _categories = const [
    'Giày thể thao',
    'Áo thể thao',
    'Quần áo',
    'Phụ kiện',
    'Dụng cụ thể thao',
  ];
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Product> get _filtered => _products.where((p) {
    final q = _search.text.trim().toLowerCase();
    return (q.isEmpty || p.name.toLowerCase().contains(q)) &&
        (_category == 'Tất cả danh mục' || p.category == _category) &&
        (_status == 'Trạng thái' ||
            (_status == 'Đang bán' && p.active) ||
            (_status == 'Tạm ngưng' && !p.active));
  }).toList();

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pages = (filtered.length / 5).ceil().clamp(1, 999).toInt();
    final page = _page.clamp(1, pages).toInt();
    final rows = filtered.skip((page - 1) * 5).take(5).toList();
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(17, 12, 17, 12),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _adminHeader(),
                      const SizedBox(height: 15),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sản phẩm',
                                  style: TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.45,
                                    color: ink,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Quản lý danh sách sản phẩm, thêm, sửa hoặc ngừng bán.',
                                  style: TextStyle(fontSize: 10, color: muted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _openEditor,
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text(
                              'Thêm sản phẩm',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: forest,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() => _page = 1),
                        decoration: const InputDecoration(
                          hintText: 'Tìm kiếm sản phẩm...',
                          prefixIcon: Icon(Icons.search_rounded, size: 19),
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: line),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _filter(
                              value: _category,
                              options: ['Tất cả danh mục', ..._categories],
                              onChanged: (v) => setState(() {
                                _category = v ?? 'Tất cả danh mục';
                                _page = 1;
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _filter(
                              value: _status,
                              options: const [
                                'Trạng thái',
                                'Đang bán',
                                'Tạm ngưng',
                              ],
                              onChanged: (v) => setState(() {
                                _status = v ?? 'Trạng thái';
                                _page = 1;
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                    ],
                  ),
                ),
              ),
              if (rows.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'Không có sản phẩm phù hợp.',
                      style: TextStyle(color: muted),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  sliver: SliverList.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 5),
                    itemBuilder: (context, i) => _productRow(rows[i]),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                sliver: SliverToBoxAdapter(
                  child: _pagination(filtered.length, page, pages),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _adminHeader() => Row(
    children: [
      const BrandMark(compact: true),
      const Spacer(),
      Container(
        width: 29,
        height: 29,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFE7EEE9),
          shape: BoxShape.circle,
        ),
        child: const Text(
          'A',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
      ),
    ],
  );

  Widget _filter({
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: const InputDecoration(
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      isDense: true,
    ),
    style: const TextStyle(
      fontSize: 10,
      color: ink,
      fontWeight: FontWeight.w600,
    ),
    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 17),
    items: options
        .map(
          (o) => DropdownMenuItem(
            value: o,
            child: Text(o, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: onChanged,
  );

  Widget _productRow(_Product p) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFEAF0F2)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 22,
          child: Checkbox(
            value: p.selected,
            onChanged: (v) => setState(() => p.selected = v ?? false),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            activeColor: forest,
            side: const BorderSide(color: Color(0xFFCCD4D7)),
          ),
        ),
        const SizedBox(width: 5),
        _ProductThumbnail(product: p),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                p.category,
                style: const TextStyle(fontSize: 9, color: muted),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Text(
                    _money(p.price),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5),
                    child: Text('|', style: TextStyle(color: line)),
                  ),
                  Text(
                    'Tồn kho: ${p.stock}',
                    style: const TextStyle(fontSize: 9, color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _statusBadge(p.active),
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 140),
              iconSize: 17,
              onSelected: (v) {
                if (v == 'edit') {
                  _openEditor(p);
                } else {
                  setState(() => p.active = !p.active);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(p.active ? 'Ngừng bán' : 'Kích hoạt'),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  Widget _statusBadge(bool active) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: active ? const Color(0xFFE5F4EC) : const Color(0xFFFFE7E7),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      active ? 'Đang bán' : 'Tạm ngưng',
      style: TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.w700,
        color: active ? forest : const Color(0xFFD86666),
      ),
    ),
  );

  Widget _pagination(int total, int page, int pages) => Row(
    children: [
      Expanded(
        child: Text(
          'Hiển thị ${total == 0 ? 0 : (page - 1) * 5 + 1}–${(page * 5).clamp(0, total)} của $total sản phẩm',
          style: const TextStyle(fontSize: 9, color: muted),
        ),
      ),
      IconButton(
        onPressed: page > 1 ? () => setState(() => _page = page - 1) : null,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.chevron_left_rounded, size: 18),
      ),
      ...List.generate(
        pages.clamp(1, 5),
        (i) => GestureDetector(
          onTap: () => setState(() => _page = i + 1),
          child: Container(
            width: 25,
            height: 25,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: page == i + 1 ? ink : Colors.white,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: line),
            ),
            child: Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 9,
                color: page == i + 1 ? Colors.white : ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
      IconButton(
        onPressed: page < pages ? () => setState(() => _page = page + 1) : null,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.chevron_right_rounded, size: 18),
      ),
    ],
  );

  String _money(int value) =>
      '${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')} ₫';

  Future<void> _openEditor([_Product? product]) async {
    final result = await showModalBottomSheet<_Product>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductEditor(product: product, categories: _categories),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (product == null) _products.insert(0, result);
    });
    showNotice(
      context,
      product == null
          ? 'Đã thêm vào dữ liệu xem thử.'
          : 'Đã cập nhật dữ liệu xem thử.',
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({required this.product});
  final _Product product;
  @override
  Widget build(BuildContext context) {
    final placeholder = Image.asset(
      'assets/images/stride-products.png',
      fit: BoxFit.cover,
      alignment: Alignment(
        product.image == Icons.sports_baseball_rounded ? 0.9 : 0.1,
        0,
      ),
    );
    const offsets = <Offset>[
      Offset.zero,
      Offset(-53, 0),
      Offset(0, -53),
      Offset(-53, -53),
    ];
    final sprite = product.photoIndex >= 0
        ? SizedBox(
            width: 53,
            height: 53,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: offsets[product.photoIndex.clamp(0, 3).toInt()].dx,
                  top: offsets[product.photoIndex.clamp(0, 3).toInt()].dy,
                  width: 106,
                  height: 106,
                  child: Image.asset(
                    'assets/images/stride-product-grid.png',
                    width: 106,
                    height: 106,
                    fit: BoxFit.fill,
                  ),
                ),
              ],
            ),
          )
        : placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 53,
        height: 53,
        child: product.imageUrl.isEmpty
            ? sprite
            : Image.network(
                product.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => sprite,
              ),
      ),
    );
  }
}

class _ProductEditor extends StatefulWidget {
  const _ProductEditor({this.product, required this.categories});
  final _Product? product;
  final List<String> categories;
  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _image;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _variant;
  late final TextEditingController _stock;
  late String _category;
  late bool _active;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name);
    _image = TextEditingController(text: p?.imageUrl ?? '');
    _description = TextEditingController();
    _price = TextEditingController(text: p == null ? '' : '${p.price}');
    _variant = TextEditingController(text: p?.variant ?? 'M / L / XL');
    _stock = TextEditingController(text: p == null ? '' : '${p.stock}');
    _category = p?.category ?? widget.categories.first;
    _active = p?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _image.dispose();
    _description.dispose();
    _price.dispose();
    _variant.dispose();
    _stock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      18,
      9,
      18,
      MediaQuery.viewInsetsOf(context).bottom + 18,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: line,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.product == null
                          ? 'Thêm sản phẩm'
                          : 'Chỉnh sửa sản phẩm',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Text(
                'Điền đầy đủ thông tin sản phẩm',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 13),
              const Text(
                'Hình ảnh sản phẩm',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 5),
              InkWell(
                onTap: _chooseImage,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 88,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFCFC),
                    border: Border.all(color: const Color(0xFFC9D3D6)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: _image.text.isEmpty
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_outlined,
                                size: 22,
                                color: muted,
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Kéo thả ảnh vào đây hoặc nhấn để chọn ảnh',
                                style: TextStyle(fontSize: 10, color: muted),
                              ),
                              Text(
                                'Hỗ trợ JPG, PNG (tối đa 5 MB)',
                                style: TextStyle(fontSize: 8, color: muted),
                              ),
                            ],
                          )
                        : Image.network(
                            _image.text,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.image_not_supported_outlined,
                              color: muted,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _field(
                _name,
                'Tên sản phẩm *',
                'Nhập tên sản phẩm',
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Tên sản phẩm là bắt buộc'
                    : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Danh mục *',
                  isDense: true,
                ),
                items: widget.categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 8),
              _field(
                _description,
                'Mô tả sản phẩm',
                'Nhập mô tả sản phẩm...',
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      _price,
                      'Giá bán (₫) *',
                      '0',
                      number: true,
                      validator: (v) =>
                          int.tryParse(v ?? '') == null || int.parse(v!) < 0
                          ? 'Nhập giá hợp lệ'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _field(
                      _stock,
                      'Tồn kho *',
                      '0',
                      number: true,
                      validator: (v) =>
                          int.tryParse(v ?? '') == null || int.parse(v!) < 0
                          ? 'Nhập tồn kho hợp lệ'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _field(_variant, 'Phân loại / biến thể', 'Size, màu sắc...'),
              const SizedBox(height: 5),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Đang bán',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                value: _active,
                activeThumbColor: forest,
                onChanged: (v) => setState(() => _active = v),
              ),
              PrimaryButton(
                label: widget.product == null ? 'Lưu sản phẩm' : 'Lưu thay đổi',
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    bool number = false,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    keyboardType: number ? TextInputType.number : TextInputType.text,
    maxLines: maxLines,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    validator: validator,
  );
  Future<void> _chooseImage() async {
    final c = TextEditingController(text: _image.text);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm ảnh sản phẩm'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: 'Đường dẫn ảnh',
            hintText: 'https://...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('Dùng ảnh'),
          ),
        ],
      ),
    );
    if (value != null) setState(() => _image.text = value);
    c.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (_image.text.trim().isEmpty && widget.product == null) {
      showNotice(context, 'Vui lòng thêm đường dẫn ảnh sản phẩm.');
      return;
    }
    final p = _Product(
      name: _name.text.trim(),
      category: _category,
      price: int.parse(_price.text),
      stock: int.parse(_stock.text),
      image: widget.product?.image ?? Icons.checkroom_rounded,
      photoIndex: widget.product?.photoIndex ?? -1,
      imageUrl: _image.text.trim(),
      active: _active,
      variant: _variant.text.trim().isEmpty
          ? 'Không có biến thể'
          : _variant.text.trim(),
    );
    if (widget.product != null) {
      widget.product!
        ..name = p.name
        ..category = p.category
        ..price = p.price
        ..stock = p.stock
        ..imageUrl = p.imageUrl
        ..photoIndex = p.photoIndex
        ..active = p.active
        ..variant = p.variant;
      Navigator.pop(context, widget.product);
    } else {
      Navigator.pop(context, p);
    }
  }
}
