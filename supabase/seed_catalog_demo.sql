-- OPTIONAL DEMO DATA for MH04/MH05. Run manually in Supabase SQL Editor.
-- Not a migration. Adds only the fixed [DEMO] catalog records below.
-- Re-running never resets existing prices, stock, reservations or images.
begin;

do $$
begin
  if (select count(*) from public.categories
      where code in ('shoes', 'apparel', 'equipment') and is_active) <> 3 then
    raise exception 'Missing active baseline categories: shoes/apparel/equipment';
  end if;
  if exists (
    select 1 from public.products
    where id in ('40000000-0000-4000-8000-000000000001',
                 '40000000-0000-4000-8000-000000000002',
                 '40000000-0000-4000-8000-000000000003')
      and (name, category_id) is distinct from (
        case id
          when '40000000-0000-4000-8000-000000000001' then '[DEMO] Giày chạy bộ Daily Run'
          when '40000000-0000-4000-8000-000000000002' then '[DEMO] Áo tập Training Tee'
          else '[DEMO] Bóng rổ Practice' end,
        (select c.id from public.categories c where c.code = case products.id
          when '40000000-0000-4000-8000-000000000001' then 'shoes'
          when '40000000-0000-4000-8000-000000000002' then 'apparel'
          else 'equipment' end))
  ) then
    raise exception 'Demo product ID collision; no data changed';
  end if;
  if exists (
    select 1 from public.product_variants
    where id in ('50000000-0000-4000-8000-000000000001',
                 '50000000-0000-4000-8000-000000000002',
                 '50000000-0000-4000-8000-000000000003',
                 '50000000-0000-4000-8000-000000000004',
                 '50000000-0000-4000-8000-000000000005')
      and (sku, product_id) is distinct from (
        case id
          when '50000000-0000-4000-8000-000000000001' then 'DEMO-CATALOG-RUN-40'
          when '50000000-0000-4000-8000-000000000002' then 'DEMO-CATALOG-RUN-41'
          when '50000000-0000-4000-8000-000000000003' then 'DEMO-CATALOG-TEE-M'
          when '50000000-0000-4000-8000-000000000004' then 'DEMO-CATALOG-TEE-L'
          else 'DEMO-CATALOG-BALL-7' end,
        (case
          when id in ('50000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000002') then '40000000-0000-4000-8000-000000000001'
          when id in ('50000000-0000-4000-8000-000000000003', '50000000-0000-4000-8000-000000000004') then '40000000-0000-4000-8000-000000000002'
          else '40000000-0000-4000-8000-000000000003' end)::uuid)
  ) then
    raise exception 'Demo variant ID collision; no data changed';
  end if;
end;
$$;

insert into public.products (id, category_id, name, description)
select v.id::uuid, c.id, v.name, v.description
from (values
  ('40000000-0000-4000-8000-000000000001', 'shoes',
   '[DEMO] Giày chạy bộ Daily Run',
   'Dữ liệu thử MH04/MH05. Chọn cỡ để xem giá và tồn theo biến thể.'),
  ('40000000-0000-4000-8000-000000000002', 'apparel',
   '[DEMO] Áo tập Training Tee',
   'Dữ liệu thử MH04/MH05. Cỡ M còn hàng, cỡ L hết hàng để thử giao diện.'),
  ('40000000-0000-4000-8000-000000000003', 'equipment',
   '[DEMO] Bóng rổ Practice',
   'Dữ liệu thử MH04/MH05. Sản phẩm dụng cụ có một biến thể size 7.')
) as v(id, category_code, name, description)
join public.categories c on c.code = v.category_code
on conflict (id) do nothing;

with inserted as (
  insert into public.product_variants
    (id, product_id, sku, label, attributes, price_vnd, on_hand)
  values
    ('50000000-0000-4000-8000-000000000001',
     '40000000-0000-4000-8000-000000000001',
     'DEMO-CATALOG-RUN-40', 'Đen / 40', '{"color":"Đen","size":"40"}', 690000, 8),
    ('50000000-0000-4000-8000-000000000002',
     '40000000-0000-4000-8000-000000000001',
     'DEMO-CATALOG-RUN-41', 'Đen / 41', '{"color":"Đen","size":"41"}', 720000, 3),
    ('50000000-0000-4000-8000-000000000003',
     '40000000-0000-4000-8000-000000000002',
     'DEMO-CATALOG-TEE-M', 'Trắng / M', '{"color":"Trắng","size":"M"}', 250000, 12),
    ('50000000-0000-4000-8000-000000000004',
     '40000000-0000-4000-8000-000000000002',
     'DEMO-CATALOG-TEE-L', 'Trắng / L', '{"color":"Trắng","size":"L"}', 250000, 0),
    ('50000000-0000-4000-8000-000000000005',
     '40000000-0000-4000-8000-000000000003',
     'DEMO-CATALOG-BALL-7', 'Size 7', '{"size":"7"}', 320000, 5)
  on conflict (id) do nothing
  returning id, on_hand
)
insert into public.inventory_movements
  (variant_id, event_id, kind, on_hand_delta, reason)
select id, '60000000-0000-4000-8000-000000000001',
       'adjustment', on_hand, '[DEMO] Khởi tạo tồn catalog để thử MH04/MH05'
from inserted where on_hand > 0;

commit;

select p.name, v.sku, v.label, v.price_vnd,
       v.on_hand, v.reserved, v.available_quantity
from public.products p
join public.product_variants v on v.product_id = p.id
where p.id in ('40000000-0000-4000-8000-000000000001',
               '40000000-0000-4000-8000-000000000002',
               '40000000-0000-4000-8000-000000000003')
order by p.name, v.sku;
