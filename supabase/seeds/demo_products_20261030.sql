-- Dữ liệu mẫu: 10 sản phẩm, mỗi sản phẩm 1 biến thể, giá VND minh họa.
-- Ảnh minh họa từ DummyJSON; SKU cố định giúp chạy lại không tạo bản sao.
-- Không ghi đè sản phẩm/biến thể đã tồn tại.
begin;
select pg_advisory_xact_lock(hashtext('demo-products-20261030'));
do $seed$
declare
  item jsonb;
  category uuid;
  product uuid;
  variant uuid;
begin
  select id into strict category from public.categories where name = 'Dụng cụ';
  for item in select value from jsonb_array_elements($data$[{"name":"Bóng đá tập luyện","slug":"football","price":250000,"sku":"DEMO-20261030-01","image":"https://cdn.dummyjson.com/product-images/sports-accessories/football/thumbnail.webp"},{"name":"Bóng rổ tập luyện","slug":"basketball","price":320000,"sku":"DEMO-20261030-02","image":"https://cdn.dummyjson.com/product-images/sports-accessories/basketball/thumbnail.webp"},{"name":"Bóng chuyền tập luyện","slug":"volleyball","price":280000,"sku":"DEMO-20261030-03","image":"https://cdn.dummyjson.com/product-images/sports-accessories/volleyball/thumbnail.webp"},{"name":"Vợt tennis cơ bản","slug":"tennis-racket","price":850000,"sku":"DEMO-20261030-04","image":"https://cdn.dummyjson.com/product-images/sports-accessories/tennis-racket/thumbnail.webp"},{"name":"Bóng tennis","slug":"tennis-ball","price":65000,"sku":"DEMO-20261030-05","image":"https://cdn.dummyjson.com/product-images/sports-accessories/tennis-ball/thumbnail.webp"},{"name":"Quả cầu lông","slug":"feather-shuttlecock","price":30000,"sku":"DEMO-20261030-06","image":"https://cdn.dummyjson.com/product-images/sports-accessories/feather-shuttlecock/thumbnail.webp"},{"name":"Bóng golf","slug":"golf-ball","price":55000,"sku":"DEMO-20261030-07","image":"https://cdn.dummyjson.com/product-images/sports-accessories/golf-ball/thumbnail.webp"},{"name":"Gậy golf sắt","slug":"iron-golf","price":1200000,"sku":"DEMO-20261030-08","image":"https://cdn.dummyjson.com/product-images/sports-accessories/iron-golf/thumbnail.webp"},{"name":"Găng tay bóng chày","slug":"baseball-glove","price":450000,"sku":"DEMO-20261030-09","image":"https://cdn.dummyjson.com/product-images/sports-accessories/baseball-glove/thumbnail.webp"},{"name":"Gậy bóng chày kim loại","slug":"metal-baseball-bat","price":650000,"sku":"DEMO-20261030-10","image":"https://cdn.dummyjson.com/product-images/sports-accessories/metal-baseball-bat/thumbnail.webp"}]$data$::jsonb)
  loop
    if exists (select 1 from public.product_variants where sku = item->>'sku') then
      continue;
    end if;
    insert into public.products(category_id, name, description, image_path, is_active)
    values(category, item->>'name',
      'Dữ liệu mẫu phục vụ demo Sports Store. Giá và tồn kho minh họa; ảnh từ DummyJSON.',
      item->>'image', true)
    returning id into product;
    insert into public.product_variants(product_id, sku, label, attributes, price_vnd, on_hand, reserved, damaged, is_active)
    values(product, item->>'sku', 'Tiêu chuẩn', '{"version":"standard"}'::jsonb,
      (item->>'price')::bigint, 20, 0, 0, true)
    returning id into variant;
    insert into public.inventory_movements(variant_id, event_id, kind, on_hand_delta, reason)
    values(variant, gen_random_uuid(), 'adjustment', 20, 'Nhập tồn ban đầu dữ liệu mẫu demo-products-20261030');
  end loop;
end;
$seed$;
commit;
