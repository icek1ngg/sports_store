-- DỮ LIỆU MẪU STRIDE: 5 giày + 8 quần áo, 125 biến thể.
-- Giá/tồn minh họa; ảnh HTTPS bên thứ ba, không cam kết thông số thương mại.
-- Chạy lại giữ nguyên giá/tồn/reservation/ảnh đã sửa, không nhân đôi ledger.
-- Không sửa schema, quyền, đơn hàng hoặc 10 sản phẩm dụng cụ hiện có.
begin;
select pg_advisory_xact_lock(hashtextextended('stride-apparel-shoes-20261108',0));
do $seed$
declare
  item jsonb;
  category uuid;
  product uuid;
  variant uuid;
  size_label text;
  color_label text;
  size_index int;
  color_index int;
  stock bigint;
  variant_sku text;
  seed_event uuid;
begin
  if (select count(*) from public.categories where code in ('shoes','apparel') and is_active) <> 2 then
    raise exception 'Missing active shoes/apparel categories';
  end if;
  for item in select value from jsonb_array_elements($dataset$[{"key":"S01","category":"shoes","name":"Giày Nike Air Jordan 1 Đỏ Đen","price_vnd":1890000,"image":"https://cdn.dummyjson.com/product-images/mens-shoes/nike-air-jordan-1-red-and-black/thumbnail.webp","sizes":["36","37","38","39","40","41","42","43","44"],"colors":["Đỏ đen"],"material":"Vải và vật liệu tổng hợp","description":"Giày thể thao dành cho bộ sưu tập minh họa; lựa chọn cỡ từ 36 đến 44."},{"key":"S02","category":"shoes","name":"Giày Nike Baseball Cleats","price_vnd":1590000,"image":"https://cdn.dummyjson.com/product-images/mens-shoes/nike-baseball-cleats/thumbnail.webp","sizes":["36","37","38","39","40","41","42","43","44"],"colors":["Đen trắng"],"material":"Vải và vật liệu tổng hợp","description":"Giày thể thao dành cho bộ sưu tập minh họa; lựa chọn cỡ từ 36 đến 44."},{"key":"S03","category":"shoes","name":"Giày Puma Future Rider","price_vnd":1490000,"image":"https://cdn.dummyjson.com/product-images/mens-shoes/puma-future-rider-trainers/thumbnail.webp","sizes":["36","37","38","39","40","41","42","43","44"],"colors":["Nhiều màu"],"material":"Vải và vật liệu tổng hợp","description":"Giày thể thao dành cho bộ sưu tập minh họa; lựa chọn cỡ từ 36 đến 44."},{"key":"S04","category":"shoes","name":"Giày Sports Sneakers Off White & Red","price_vnd":1190000,"image":"https://cdn.dummyjson.com/product-images/mens-shoes/sports-sneakers-off-white-&-red/thumbnail.webp","sizes":["36","37","38","39","40","41","42","43","44"],"colors":["Trắng đỏ"],"material":"Vải và vật liệu tổng hợp","description":"Giày thể thao dành cho bộ sưu tập minh họa; lựa chọn cỡ từ 36 đến 44."},{"key":"S05","category":"shoes","name":"Giày Sports Sneakers Off White Red","price_vnd":1290000,"image":"https://cdn.dummyjson.com/product-images/mens-shoes/sports-sneakers-off-white-red/thumbnail.webp","sizes":["36","37","38","39","40","41","42","43","44"],"colors":["Trắng đỏ"],"material":"Vải và vật liệu tổng hợp","description":"Giày thể thao dành cho bộ sưu tập minh họa; lựa chọn cỡ từ 36 đến 44."},{"key":"A01","category":"apparel","name":"Áo chạy bộ Kalenji Xanh","price_vnd":350000,"image":"https://contents.mediadecathlon.com/p2506817/k$6bb995e8d179b5827ab1f530b137c8ca/picture.jpg","sizes":["S","M","L","XL","XXL"],"colors":["Xanh dương","Xanh navy"],"material":"Polyester","description":"Quần áo thể thao minh họa cho tập luyện và vận động hằng ngày."},{"key":"A02","category":"apparel","name":"Áo tập Nike Miler Cam","price_vnd":490000,"image":"https://strtsply.com/cdn/shop/files/NIKEDRIFIT1.0MILERTSHIRTBURNTORANGESTRTSPLY.jpg?v=1740091172&width=600","sizes":["S","M","L","XL","XXL"],"colors":["Cam","Đen"],"material":"Polyester","description":"Quần áo thể thao minh họa cho tập luyện và vận động hằng ngày."},{"key":"A03","category":"apparel","name":"Áo thể thao Carrollton Trắng","price_vnd":390000,"image":"https://www.tascperformance.com/cdn/shop/files/TM110-100CarrolltonFitnessT_White_1200x1600_b693f427-e466-4c86-b8fc-0288966be2cd.jpg?v=1767110501&width=600","sizes":["S","M","L","XL","XXL"],"colors":["Trắng","Xám"],"material":"Vải pha co giãn","description":"Quần áo thể thao minh họa cho tập luyện và vận động hằng ngày."},{"key":"A04","category":"apparel","name":"Áo tập Performance Xám","price_vnd":290000,"image":"https://contents.mediadecathlon.com/p3154123/k$bb23ec633d82f9914c4005f23a1349e0/picture.jpg?f=600x600","sizes":["S","M","L","XL","XXL"],"colors":["Xám","Đen"],"material":"Polyester","description":"Quần áo thể thao minh họa cho tập luyện và vận động hằng ngày."},{"key":"A05","category":"apparel","name":"Quần short tập luyện Essential","price_vnd":250000,"image":"https://contents.mediadecathlon.com/p2789798/k$55d674c813deb11fa069180916a1a9e3/picture.jpg?f=600x600","sizes":["S","M","L","XL","XXL"],"colors":["Đen","Xanh navy"],"material":"Polyester","description":"Quần áo thể thao minh họa cho tập luyện và vận động hằng ngày."},{"key":"A06","category":"apparel","name":"Quần short chạy bộ nữ Kiprun","price_vnd":280000,"image":"https://contents.mediadecathlon.com/p2765177/k$13438722e78a8584797fae1cfbb6091b/picture.jpg?f=600x600","sizes":["S","M","L","XL","XXL"],"colors":["Đen","Trắng"],"material":"Polyester","description":"Quần áo thể thao minh họa cho tập luyện và vận động hằng ngày."},{"key":"A07","category":"apparel","name":"Áo khoác chạy bộ Kiprun","price_vnd":790000,"image":"https://contents.mediadecathlon.com/p2906668/k$09e4d07281641cc1bc555a48f51006d5/men-s-running-jacket-kiprun-run-100-warm-black.jpg","sizes":["S","M","L","XL","XXL"],"colors":["Đen","Xanh navy"],"material":"Vải tổng hợp","description":"Quần áo thể thao minh họa cho tập luyện và vận động hằng ngày."},{"key":"A08","category":"apparel","name":"Áo khoác chạy bộ nữ","price_vnd":690000,"image":"https://contents.mediadecathlon.com/s1210002/k$252cb943d97c12ca08d4d124d5132fd2/6e9b540a-dcce-48d9-ac2b-705e974edfcc.jpg","sizes":["S","M","L","XL","XXL"],"colors":["Đen","Xám"],"material":"Vải tổng hợp","description":"Quần áo thể thao minh họa cho tập luyện và vận động hằng ngày."}]$dataset$::jsonb)
  loop
    select id into strict category from public.categories where code = item->>'category' and is_active;
    product := null;
    select v.product_id into product from public.product_variants v
      where v.sku like 'DEMO-STRIDE-20261108-' || (item->>'key') || '-%'
      order by v.sku limit 1;
    if product is not null and not exists (
      select 1 from public.products p where p.id=product and p.category_id=category
      and p.description like '[DEMO STRIDE 20261108]%'
    ) then
      raise exception 'Seed SKU collision for %', item->>'key';
    end if;
    if product is null then
      insert into public.products(category_id,name,description,image_path,is_active)
      values(category,item->>'name',
        '[DEMO STRIDE 20261108] ' || (item->>'description') ||
        ' Giá, chất liệu và tồn dùng để demo. Ảnh minh họa; ảnh có thể không thể hiện tất cả màu của biến thể.',
        item->>'image',true) returning id into product;
    end if;
    for color_label, color_index in
      select value, ordinality::int from jsonb_array_elements_text(item->'colors') with ordinality
    loop
      for size_label, size_index in
        select value, ordinality::int from jsonb_array_elements_text(item->'sizes') with ordinality
      loop
        variant_sku := 'DEMO-STRIDE-20261108-' || (item->>'key') || '-C' || color_index || '-' || size_label;
        if exists(select 1 from public.product_variants where sku=variant_sku and product_id<>product) then
          raise exception 'Seed variant collision for %',variant_sku;
        end if;
        stock := case when size_index=jsonb_array_length(item->'sizes') and color_index=1 then 0 else 8 + (size_index * 3 + color_index) % 15 end;
        variant := null;
        insert into public.product_variants(product_id,sku,label,attributes,price_vnd,on_hand,reserved,damaged,is_active)
        values(product,variant_sku,color_label || ' / ' || size_label,
          jsonb_build_object('color',color_label,'size',size_label,'material',item->>'material','demo',true),
          (item->>'price_vnd')::bigint,stock,0,0,true)
        on conflict(sku) do nothing returning id into variant;
        if variant is not null and stock>0 then
          seed_event := gen_random_uuid();
          insert into public.inventory_movements(variant_id,event_id,kind,on_hand_delta,reason)
          values(variant,seed_event,'adjustment',stock,'[DEMO STRIDE 20261108] Khởi tạo tồn quần áo/giày');
        end if;
      end loop;
    end loop;
  end loop;
end;
$seed$;
commit;
