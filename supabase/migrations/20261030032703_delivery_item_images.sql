-- Snapshot public HTTPS product images at order creation.
-- Private Storage object paths are intentionally not exposed as public URLs.
alter table public.order_items add column product_image_url text;
create function private.snapshot_order_item_image()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  select case when p.image_path ~ '^https://[^/[:space:]]+/' then p.image_path else null end
  into new.product_image_url from public.products p where p.id=new.product_id;
  return new;
end;
$$;
revoke all on function private.snapshot_order_item_image() from public,anon,authenticated,service_role;
create trigger order_items_snapshot_image before insert on public.order_items
for each row execute function private.snapshot_order_item_image();
-- Existing orders had no image snapshot. Bootstrap once from current catalog.
update public.order_items oi set product_image_url=p.image_path
from public.products p where p.id=oi.product_id and p.image_path ~ '^https://[^/[:space:]]+/';
grant select(product_image_url) on public.order_items to sports_store_delivery_reader;
-- Keep the existing authorized projection and extend only its outbound items.
do $migration$
declare definition text;
begin
  definition := pg_get_functiondef('public.get_my_delivery_task(uuid)'::regprocedure);
  if position('select to_jsonb(i) as item_json' in definition)=0 then
    raise exception 'Unexpected get_my_delivery_task definition';
  end if;
  definition := replace(definition,
    'select to_jsonb(i) as item_json',
    'select to_jsonb(i) || jsonb_build_object(''image_url'', (
      select oi.product_image_url from public.order_items oi
      where oi.id=i.item_id and i.item_source=''order_snapshot''
    )) as item_json');
  execute definition;
end;
$migration$;
notify pgrst,'reload schema';
