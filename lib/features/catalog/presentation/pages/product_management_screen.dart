import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/prm_preview_widgets.dart';
import '../../domain/models/managed_product.dart';
import '../../domain/models/product_image.dart';
import '../view_models/product_management_view_model.dart';

class ProductManagementScreen extends ConsumerStatefulWidget {
  const ProductManagementScreen({super.key});
  @override
  ConsumerState<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState
    extends ConsumerState<ProductManagementScreen> {
  final _search = TextEditingController();
  String? _category;
  bool? _active;
  int _page = 0;
  bool _busy = false;
  final Map<String, ({String request, ManagedProduct command})>
  _toggleRequests = {};
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit(CatalogSnapshot data, [ManagedProduct? product]) async {
    if (data.categories.isEmpty) {
      showNotice(
        context,
        'Chưa có danh mục sản phẩm. Vui lòng liên hệ quản trị viên.',
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => _ProductEditor(
        product: product,
        categories: data.categories,
        save: (value, request) => ref
            .read(productManagementViewModelProvider.notifier)
            .save(value, requestId: request),
        uploadImage: () => ref
            .read(productManagementViewModelProvider.notifier)
            .pickAndUploadImage(),
      ),
    );
  }

  Future<void> _toggle(ManagedProduct product) async {
    if (_busy) return;
    final request = _toggleRequests.putIfAbsent(
      product.id!,
      () => (
        request: newCatalogRequestId(),
        command: product.withActive(!product.active),
      ),
    );
    setState(() => _busy = true);
    try {
      await ref
          .read(productManagementViewModelProvider.notifier)
          .save(request.command, requestId: request.request);
      _toggleRequests.remove(product.id);
      if (mounted) {
        showNotice(
          context,
          product.active ? 'Đã ngừng bán sản phẩm.' : 'Đã kích hoạt sản phẩm.',
        );
      }
    } catch (error) {
      if (error is CatalogFailure && !error.outcomeUnknown) {
        _toggleRequests.remove(product.id);
      }
      if (mounted) showNotice(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productManagementViewModelProvider);
    return state.when(
      skipLoadingOnReload: false,
      skipLoadingOnRefresh: false,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref
                    .read(productManagementViewModelProvider.notifier)
                    .reload(),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      ),
      data: (data) {
        final query = _search.text.trim().toLowerCase();
        final filtered = data.products
            .where(
              (p) =>
                  (query.isEmpty ||
                      p.name.toLowerCase().contains(query) ||
                      p.variants.any(
                        (v) => v.sku.toLowerCase().contains(query),
                      )) &&
                  (_category == null || p.categoryId == _category) &&
                  (_active == null || p.active == _active),
            )
            .toList();
        final pages = (filtered.length / 10).ceil().clamp(1, 999999);
        final page = _page.clamp(0, pages - 1);
        final rows = filtered.skip(page * 10).take(10).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandMark(compact: true),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Sản phẩm',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tải lại',
                        onPressed: _busy
                            ? null
                            : () => ref
                                  .read(
                                    productManagementViewModelProvider.notifier,
                                  )
                                  .reload(),
                        icon: const Icon(Icons.refresh),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _edit(data),
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm sản phẩm'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Quản lý sản phẩm, giá và tồn kho theo từng biến thể.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() => _page = 0),
                    decoration: const InputDecoration(
                      labelText: 'Tìm tên sản phẩm hoặc SKU',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _category,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Danh mục',
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Tất cả danh mục'),
                            ),
                            ...data.categories.map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) => setState(() {
                            _category = value;
                            _page = 0;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<bool>(
                          initialValue: _active,
                          decoration: const InputDecoration(
                            labelText: 'Trạng thái',
                          ),
                          items: const [
                            DropdownMenuItem<bool>(
                              value: null,
                              child: Text('Tất cả'),
                            ),
                            DropdownMenuItem(
                              value: true,
                              child: Text('Đang bán'),
                            ),
                            DropdownMenuItem(
                              value: false,
                              child: Text('Tạm ngưng'),
                            ),
                          ],
                          onChanged: (value) => setState(() {
                            _active = value;
                            _page = 0;
                          }),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Không có sản phẩm phù hợp.'))
                  : RefreshIndicator(
                      onRefresh: () => ref
                          .read(productManagementViewModelProvider.notifier)
                          .reload(),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final product = rows[index];
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: SizedBox(
                                width: 52,
                                height: 52,
                                child: product.imageUrl == null
                                    ? const Icon(Icons.inventory_2_outlined)
                                    : Image.network(
                                        product.imageUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                              ),
                              title: Text(
                                product.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${product.categoryName}\nTừ ${product.minimumPrice} ₫ · Có thể bán: ${product.available}\n${product.active ? 'Đang bán' : 'Tạm ngưng'} · ${product.variants.length} biến thể',
                              ),
                              isThreeLine: true,
                              onTap: _busy ? null : () => _edit(data, product),
                              trailing: PopupMenuButton<String>(
                                enabled: !_busy,
                                onSelected: (value) => value == 'edit'
                                    ? _edit(data, product)
                                    : _toggle(product),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Chỉnh sửa / biến thể'),
                                  ),
                                  PopupMenuItem(
                                    value: 'toggle',
                                    child: Text(
                                      product.active
                                          ? 'Ngừng bán'
                                          : 'Kích hoạt',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${filtered.length} sản phẩm · Trang ${page + 1}/$pages',
                    ),
                  ),
                  IconButton(
                    onPressed: page > 0
                        ? () => setState(() => _page = page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    onPressed: page + 1 < pages
                        ? () => setState(() => _page = page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProductEditor extends StatefulWidget {
  const _ProductEditor({
    this.product,
    required this.categories,
    required this.save,
    required this.uploadImage,
  });
  final ManagedProduct? product;
  final List<CatalogCategory> categories;
  final Future<void> Function(ManagedProduct, String) save;
  final Future<UploadedProductImage?> Function() uploadImage;
  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _description, _image;
  late final List<_VariantFields> _variants;
  late String _category;
  late bool _active;
  bool _saving = false;
  bool _uploading = false;
  UploadedProductImage? _uploadedImage;
  String? _error;
  String? _requestId;
  ManagedProduct? _pendingCommand;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name);
    _description = TextEditingController(text: p?.description);
    _image = TextEditingController(text: p?.imagePath);
    _image.addListener(_imageChanged);
    _category = p?.categoryId ?? widget.categories.first.id;
    _active = p?.active ?? true;
    _variants =
        p?.variants.map(_VariantFields.new).toList() ?? [_VariantFields(null)];
  }

  void _imageChanged() {
    if (_uploadedImage != null && _image.text != _uploadedImage!.path) {
      setState(() => _uploadedImage = null);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _image.dispose();
    for (final fields in _variants) {
      fields.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _uploading || !_form.currentState!.validate()) return;
    final product = widget.product;
    final command =
        _pendingCommand ??
        ManagedProduct(
          id: product?.id,
          updatedAt: product?.updatedAt,
          name: _name.text.trim(),
          categoryId: _category,
          description: _description.text.trim(),
          imagePath: _image.text.trim(),
          active: _active,
          variants: _variants.map((v) => v.value()).toList(),
        );
    _pendingCommand = command;
    _requestId ??= newCatalogRequestId();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(command, _requestId!);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          if (error is CatalogFailure && !error.outcomeUnknown) {
            _pendingCommand = null;
            _requestId = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadImage() async {
    if (_saving || _uploading || _pendingCommand != null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final uploaded = await widget.uploadImage();
      if (mounted && uploaded != null) {
        setState(() {
          _uploadedImage = uploaded;
          _image.text = uploaded.path;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is CatalogFailure
              ? error.message
              : 'Không thể tải ảnh lên. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && !_uploading,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.product == null
                          ? 'Thêm sản phẩm'
                          : 'Chỉnh sửa sản phẩm',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving || _uploading
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_pendingCommand != null && !_saving)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Thử lại sẽ gửi đúng nội dung vừa lưu. Đóng và tải lại để kiểm tra trước khi sửa tiếp.',
                  ),
                ),
              AbsorbPointer(
                absorbing: _saving || _uploading || _pendingCommand != null,
                child: Column(
                  children: [
                    _field(_name, 'Tên sản phẩm *'),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Danh mục *',
                      ),
                      items: widget.categories
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                '${c.name}${c.active ? '' : ' (ngừng dùng)'}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _category = value!),
                    ),
                    const SizedBox(height: 10),
                    _field(_description, 'Mô tả', required: false, lines: 3),
                    const SizedBox(height: 10),
                    _field(
                      _image,
                      'URL ảnh HTTPS hoặc đường dẫn trong product-images',
                      required: false,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _uploadImage,
                      icon: const Icon(Icons.upload_file),
                      label: Text(
                        _uploading
                            ? 'Đang chọn / tải ảnh…'
                            : 'Chọn ảnh từ thiết bị',
                      ),
                    ),
                    const Text(
                      'PNG, JPEG hoặc WebP, tối đa 5 MB. Lưu sản phẩm để áp dụng ảnh.',
                    ),
                    if (_uploadedImage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          height: 120,
                          child: Image.network(
                            _uploadedImage!.previewUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Center(
                              child: Text(
                                'Đã tải ảnh. Không thể hiển thị ảnh xem trước.',
                              ),
                            ),
                          ),
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Đang bán'),
                      value: _active,
                      onChanged: (value) => setState(() => _active = value),
                    ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Biến thể, giá và tồn kho',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._variants.asMap().entries.map(
                      (entry) => _variantEditor(entry.key, entry.value),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _variants.add(_VariantFields(null))),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm biến thể'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving || _uploading ? null : _save,
                  child: Text(
                    _saving
                        ? 'Đang lưu...'
                        : _pendingCommand != null
                        ? 'Thử lưu lại'
                        : 'Lưu sản phẩm',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = true,
    int lines = 1,
    bool number = false,
    int minimum = 0,
  }) => TextFormField(
    controller: controller,
    maxLines: lines,
    keyboardType: number ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      if (required && (value == null || value.trim().isEmpty)) {
        return 'Vui lòng nhập thông tin';
      }
      if (number &&
          (int.tryParse(value ?? '') == null || int.parse(value!) < minimum)) {
        return 'Nhập số nguyên từ $minimum';
      }
      return null;
    },
  );

  Widget _variantEditor(int index, _VariantFields fields) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Biến thể ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (fields.original?.id == null && _variants.length > 1)
                IconButton(
                  tooltip: 'Bỏ biến thể mới',
                  onPressed: () => setState(() {
                    _variants.remove(fields);
                    fields.dispose();
                  }),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          _field(fields.sku, 'SKU *'),
          const SizedBox(height: 8),
          _field(fields.label, 'Tên biến thể (size / màu) *'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _field(fields.price, 'Giá (VND) *', number: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  fields.stock,
                  'Tồn thực tế *',
                  number: true,
                  minimum: fields.original?.reserved ?? 0,
                ),
              ),
            ],
          ),
          if (fields.original != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Đã giữ: ${fields.original!.reserved} · Không giảm tồn dưới số đã giữ.',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bán biến thể này'),
            value: fields.active,
            onChanged: (value) => setState(() => fields.active = value),
          ),
        ],
      ),
    ),
  );
}

class _VariantFields {
  _VariantFields(this.original)
    : sku = TextEditingController(text: original?.sku),
      label = TextEditingController(text: original?.label),
      price = TextEditingController(text: '${original?.priceVnd ?? 0}'),
      stock = TextEditingController(text: '${original?.onHand ?? 0}'),
      active = original?.active ?? true;
  final ManagedVariant? original;
  final TextEditingController sku, label, price, stock;
  bool active;
  ManagedVariant value() => ManagedVariant(
    id: original?.id,
    sku: sku.text.trim(),
    label: label.text.trim(),
    priceVnd: int.parse(price.text),
    onHand: int.parse(stock.text),
    reserved: original?.reserved ?? 0,
    expectedOnHand: original?.onHand,
    active: active,
    attributes: original?.attributes ?? {},
  );
  void dispose() {
    sku.dispose();
    label.dispose();
    price.dispose();
    stock.dispose();
  }
}
