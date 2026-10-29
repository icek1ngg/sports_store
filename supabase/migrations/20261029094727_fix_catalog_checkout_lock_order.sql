-- Preserve the existing RPC contract and grants; align lock order with checkout.
create or replace function private.save_managed_product(
  p_request_id uuid, p_product_id uuid, p_expected_updated_at timestamptz,
  p_name text, p_category_id uuid, p_description text, p_image_path text,
  p_is_active boolean, p_variants jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  command jsonb := jsonb_build_object('product_id',p_product_id,'expected_updated_at',p_expected_updated_at,
    'name',p_name,'category_id',p_category_id,'description',p_description,
    'image_path',p_image_path,'is_active',p_is_active,'variants',p_variants);
  receipt private.catalog_command_receipts%rowtype;
  product public.products%rowtype;
  variant public.product_variants%rowtype;
  item jsonb;
  product_key uuid := p_product_id;
  variant_key uuid;
  delta bigint;
  stock bigint;
  seen uuid[] := '{}'::uuid[];
  locked_variants uuid[];
begin
  if actor is null or not exists(select 1 from public.profiles where id=actor and role='manager') then
    raise exception 'manager_required' using errcode='42501';
  end if;
  if p_request_id is null then raise exception 'request_id_required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('catalog:'||actor::text||':'||p_request_id::text,0));
  select * into receipt from private.catalog_command_receipts where actor_id=actor and request_id=p_request_id;
  if found then
    if receipt.command <> command then raise exception 'idempotency_conflict' using errcode='22023'; end if;
    return receipt.product_id;
  end if;
  if btrim(coalesce(p_name,''))='' or p_is_active is null
    or jsonb_typeof(p_variants) is distinct from 'array'
    or jsonb_array_length(p_variants)=0 then
    raise exception 'invalid_product' using errcode='22023';
  end if;
  if not exists(select 1 from public.categories where id=p_category_id) then
    raise exception 'category_required' using errcode='22023';
  end if;
  if p_image_path is not null and (btrim(p_image_path)='' or p_image_path like 'http://%') then
    raise exception 'invalid_image_path' using errcode='22023';
  end if;
  if product_key is null then
    insert into public.products(category_id,name,description,image_path,is_active)
      values(p_category_id,btrim(p_name),p_description,p_image_path,p_is_active)
      returning * into product;
    product_key := product.id;
  else
    -- Checkout and delivery lock variants in UUID order. Take these locks
    -- before the product row to avoid a product/variant lock inversion.
    select coalesce(array_agg(id order by id), '{}'::uuid[]) into locked_variants
      from public.product_variants where product_id=product_key;
    perform id from public.product_variants where id=any(locked_variants) order by id for update;
    select * into product from public.products where id=product_key for update;
    if not found then raise exception 'product_unavailable' using errcode='42501'; end if;
    if locked_variants is distinct from (
      select coalesce(array_agg(id order by id), '{}'::uuid[])
      from public.product_variants where product_id=product_key
    ) then raise exception 'product_changed' using errcode='40001'; end if;
    if p_expected_updated_at is null or product.updated_at <> p_expected_updated_at then
      raise exception 'product_changed' using errcode='40001';
    end if;
    update public.products set category_id=p_category_id,name=btrim(p_name),description=p_description,
      image_path=p_image_path,is_active=p_is_active where id=product_key;
  end if;
  for item in select value from jsonb_array_elements(p_variants) loop
    if jsonb_typeof(item) is distinct from 'object'
      or btrim(coalesce(item->>'sku',''))='' or btrim(coalesce(item->>'label',''))=''
      or coalesce(item->>'price_vnd','') !~ '^[0-9]+$'
      or coalesce(item->>'on_hand','') !~ '^[0-9]+$'
      or jsonb_typeof(item->'is_active') is distinct from 'boolean'
      or jsonb_typeof(item->'attributes') is distinct from 'object' then
      raise exception 'invalid_variant' using errcode='22023';
    end if;
    variant_key := nullif(item->>'id','')::uuid;
    stock := (item->>'on_hand')::bigint;
    if variant_key is null then
      insert into public.product_variants(product_id,sku,label,price_vnd,on_hand,is_active,attributes)
      values(product_key,btrim(item->>'sku'),btrim(item->>'label'),(item->>'price_vnd')::bigint,
        stock,(item->>'is_active')::boolean,item->'attributes') returning * into variant;
      variant_key := variant.id;
      delta := stock;
    else
      if variant_key=any(seen) then raise exception 'duplicate_variant' using errcode='22023'; end if;
      select * into variant from public.product_variants where id=variant_key and product_id=product_key for update;
      if not found then raise exception 'variant_unavailable' using errcode='42501'; end if;
      if coalesce(item->>'expected_on_hand','') !~ '^[0-9]+$'
        or variant.on_hand <> (item->>'expected_on_hand')::bigint then
        raise exception 'stock_changed' using errcode='40001';
      end if;
      if stock < variant.reserved then raise exception 'stock_below_reserved' using errcode='23514'; end if;
      delta := stock-variant.on_hand;
      update public.product_variants set sku=btrim(item->>'sku'),label=btrim(item->>'label'),
        price_vnd=(item->>'price_vnd')::bigint,on_hand=stock,
        is_active=(item->>'is_active')::boolean,attributes=item->'attributes' where id=variant_key;
    end if;
    seen := array_append(seen,variant_key);
    if delta<>0 then
      insert into public.inventory_movements(variant_id,event_id,kind,on_hand_delta,actor_id,reason)
        values(variant_key,p_request_id,'adjustment',delta,actor,'Điều chỉnh tồn kho trong quản lý sản phẩm');
    end if;
  end loop;
  if exists(select 1 from public.product_variants where product_id=product_key and not(id=any(seen))) then
    raise exception 'existing_variants_must_be_preserved' using errcode='22023';
  end if;
  insert into private.catalog_command_receipts(actor_id,request_id,command,product_id)
    values(actor,p_request_id,command,product_key);
  return product_key;
end;
$$;
