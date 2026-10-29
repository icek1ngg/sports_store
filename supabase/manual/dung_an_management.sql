-- CHAY TOAN BO FILE trong SQL Editor cua project bqoyfytmrtvjwrpshuhh.
-- Run once as the project administrator. This script does not reset data.
-- Generated from migration 20261029041230; edit the source, then regenerate.
-- An error rolls back this entire script; do not run only a selected section.
begin;

do $prerequisites$
begin
  if to_regclass('public.profiles') is null
     or to_regclass('public.products') is null
     or to_regclass('public.product_variants') is null
     or to_regclass('public.inventory_movements') is null
     or to_regclass('public.conversations') is null
     or to_regclass('public.messages') is null
     or to_regprocedure('private.current_app_role()') is null
     or not exists (select 1 from information_schema.columns
       where table_schema='public' and table_name='product_variants' and column_name='on_hand')
     or not exists (select 1 from information_schema.columns
       where table_schema='public' and table_name='conversations' and column_name='read_at_by_user') then
    raise exception 'Required Sports Store baseline schema is missing. Stop and inspect the existing schema; do not reset or replay old migrations.';
  end if;
end;
$prerequisites$;

-- MH01/MH02: customer profiles are provisioned by the trusted Auth trigger.
-- User metadata supplies contact information only, never an application role.
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (new.id, nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'phone'), ''), new.phone),
    'customer'::public.user_role)
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function private.handle_new_user() from public, anon, authenticated, service_role;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    grant execute on function private.handle_new_user() to supabase_auth_admin;
  end if;
end; $$;
-- Inventory has no direct client write grant. This private, restricted function
-- is the trusted transactional boundary for manager catalog + stock changes.
create table if not exists private.catalog_command_receipts (
  actor_id uuid not null references public.profiles(id),
  request_id uuid not null,
  command jsonb not null,
  product_id uuid not null references public.products(id),
  created_at timestamptz not null default now(),
  primary key(actor_id, request_id)
);
alter table private.catalog_command_receipts enable row level security;
create index catalog_command_receipts_product_id_idx on private.catalog_command_receipts(product_id);
revoke all on private.catalog_command_receipts from public, anon, authenticated;

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
    select * into product from public.products where id=product_key for update;
    if not found then raise exception 'product_unavailable' using errcode='42501'; end if;
    if p_expected_updated_at is null or product.updated_at <> p_expected_updated_at then
      raise exception 'product_changed' using errcode='40001';
    end if;
    -- Lock existing variants in deterministic order before validating stock.
    perform id from public.product_variants where product_id=product_key order by id for update;
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
revoke all on function private.save_managed_product(uuid,uuid,timestamptz,text,uuid,text,text,boolean,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.save_managed_product(uuid,uuid,timestamptz,text,uuid,text,text,boolean,jsonb) to authenticated;

create or replace function public.save_managed_product(
  p_request_id uuid, p_product_id uuid, p_expected_updated_at timestamptz,
  p_name text, p_category_id uuid, p_description text, p_image_path text,
  p_is_active boolean, p_variants jsonb
) returns uuid language sql security invoker set search_path = ''
as $$ select private.save_managed_product(p_request_id,p_product_id,p_expected_updated_at,p_name,
  p_category_id,p_description,p_image_path,p_is_active,p_variants); $$;
revoke all on function public.save_managed_product(uuid,uuid,timestamptz,text,uuid,text,text,boolean,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.save_managed_product(uuid,uuid,timestamptz,text,uuid,text,text,boolean,jsonb) to authenticated;
notify pgrst, 'reload schema';
-- MH19/MH20: all RPCs execute with the caller's existing RLS and grants.
-- Serialize ALL message inserts (including permitted direct INSERTs) and reads
-- by conversation. Stamp time after locking so a transaction started earlier
-- cannot commit an unseen message behind an already advanced read watermark.
create or replace function private.stamp_chat_message()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare previous_at timestamptz;
begin
  perform c.id from public.conversations c where c.id=new.conversation_id for update;
  if not found then raise exception 'chat access denied' using errcode='42501'; end if;
  select m.created_at into previous_at from public.messages m
    where m.conversation_id=new.conversation_id order by m.created_at desc,m.id desc limit 1;
  new.created_at := greatest(clock_timestamp(),previous_at + interval '1 microsecond');
  return new;
end; $$;
revoke all on function private.stamp_chat_message() from public,anon,authenticated,service_role;
create trigger messages_stamp_server_time before insert on public.messages
for each row execute function private.stamp_chat_message();

-- Read markers cannot rewrite another user's marker or mark a newer message
-- merely because it arrived between the message SELECT and marker UPDATE.
create or replace function private.stamp_conversation_read_at()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  reader_key text := (select auth.uid())::text;
  requested_at timestamptz;
  previous_at timestamptz;
begin
  if reader_key is null then
    new.read_at_by_user := old.read_at_by_user;
  else
    requested_at := coalesce((new.read_at_by_user ->> reader_key)::timestamptz, clock_timestamp());
    previous_at := (old.read_at_by_user ->> reader_key)::timestamptz;
    new.read_at_by_user := jsonb_set(coalesce(old.read_at_by_user, '{}'::jsonb),
      array[reader_key], to_jsonb(greatest(previous_at, least(requested_at, clock_timestamp()))), true);
  end if;
  if (to_jsonb(new) - 'read_at_by_user' - 'updated_at') =
     (to_jsonb(old) - 'read_at_by_user' - 'updated_at') then
    new.updated_at := old.updated_at;
  end if;
  return new;
end;
$$;
revoke all on function private.stamp_conversation_read_at() from public, anon, authenticated, service_role;

create or replace function public.list_chat_conversations()
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare result jsonb;
begin
  if (select auth.uid()) is null or coalesce(private.current_app_role(), '') not in ('customer','manager') then
    raise exception 'chat access denied' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(x.row order by x.activity_at desc, x.id), '[]'::jsonb) into result
  from (
    select c.id, coalesce(last_message.created_at,c.created_at) as activity_at,
      jsonb_build_object('id',c.id,'customer_id',c.customer_id,
        'customer_name',coalesce(nullif(btrim(p.full_name),''),'Khách hàng'),'last_message',last_message.body,
        'last_message_at',last_message.created_at,'last_sender_id',last_message.sender_id,
        'unread_count',(select count(*) from public.messages m
          where m.conversation_id=c.id and m.sender_id <> (select auth.uid())
            and m.created_at > coalesce((c.read_at_by_user ->> (select auth.uid())::text)::timestamptz,'-infinity'::timestamptz))) as row
    from public.conversations c join public.profiles p on p.id=c.customer_id
    left join lateral (select m.body,m.created_at,m.sender_id from public.messages m
      where m.conversation_id=c.id order by m.created_at desc,m.id desc limit 1) last_message on true
  ) x;
  return result;
end;
$$;

create or replace function public.ensure_customer_conversation()
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare conversation_id uuid;
begin
  if (select auth.uid()) is null or coalesce(private.current_app_role(),'') <> 'customer' then
    raise exception 'customer chat access denied' using errcode = '42501';
  end if;
  insert into public.conversations(customer_id) values ((select auth.uid()))
    on conflict(customer_id) do nothing returning id into conversation_id;
  if conversation_id is null then
    select c.id into conversation_id from public.conversations c where c.customer_id=(select auth.uid());
  end if;
  return jsonb_build_object('id',conversation_id);
end;
$$;

create or replace function public.get_chat_messages(p_conversation_id uuid, p_before_message_id uuid default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  result jsonb;
  cursor_time timestamptz;
  cursor_id uuid;
  watermark timestamptz;
begin
  if (select auth.uid()) is null or coalesce(private.current_app_role(),'') not in ('customer','manager') or
    not exists(select 1 from public.conversations c where c.id=p_conversation_id) then
    raise exception 'chat access denied' using errcode='42501';
  end if;
  if p_before_message_id is not null then
    select m.created_at,m.id into cursor_time,cursor_id from public.messages m
      where m.id=p_before_message_id and m.conversation_id=p_conversation_id;
    if cursor_id is null then raise exception 'invalid chat cursor' using errcode='22023'; end if;
  end if;
  perform c.id from public.conversations c where c.id=p_conversation_id for update;
  if not found then raise exception 'chat access denied' using errcode='42501'; end if;
  with page as materialized (
    select m.* from public.messages m where m.conversation_id=p_conversation_id
      and (cursor_id is null or (m.created_at,m.id)<(cursor_time,cursor_id))
    order by m.created_at desc,m.id desc limit 101
  ), visible as (select * from page order by created_at desc,id desc limit 100)
  select jsonb_build_object('conversation_id',p_conversation_id,
    'messages',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at,v.id) from visible v),'[]'::jsonb),
    'has_more',(select count(*)>100 from page)),
    (select max(v.created_at) from visible v) into result,watermark;
  if p_before_message_id is null and watermark is not null then
    update public.conversations set read_at_by_user=jsonb_build_object((select auth.uid())::text,watermark)
      where id=p_conversation_id;
  end if;
  return result;
end;
$$;

create or replace function public.send_chat_message(p_conversation_id uuid,p_client_message_id uuid,p_body text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare canonical public.messages;
begin
  if (select auth.uid()) is null or coalesce(private.current_app_role(),'') not in ('customer','manager') or
    not exists(select 1 from public.conversations c where c.id=p_conversation_id) then
    raise exception 'chat access denied' using errcode='42501';
  end if;
  if p_client_message_id is null or p_body is null or btrim(p_body)='' or char_length(p_body)>4000 then
    raise exception 'invalid chat message' using errcode='22023';
  end if;
  insert into public.messages(conversation_id,sender_id,body,client_message_id)
    values(p_conversation_id,(select auth.uid()),btrim(p_body),p_client_message_id)
    on conflict(sender_id,client_message_id) do nothing returning * into canonical;
  if canonical.id is null then
    select m.* into canonical from public.messages m
      where m.sender_id=(select auth.uid()) and m.client_message_id=p_client_message_id;
  end if;
  if canonical.conversation_id is distinct from p_conversation_id or canonical.body is distinct from btrim(p_body) then
    raise exception 'chat idempotency conflict' using errcode='23505';
  end if;
  return to_jsonb(canonical);
end;
$$;

revoke all on function public.list_chat_conversations() from public,anon;
revoke all on function public.ensure_customer_conversation() from public,anon;
revoke all on function public.get_chat_messages(uuid,uuid) from public,anon;
revoke all on function public.send_chat_message(uuid,uuid,text) from public,anon;
grant execute on function public.list_chat_conversations() to authenticated;
grant execute on function public.ensure_customer_conversation() to authenticated;
grant execute on function public.get_chat_messages(uuid,uuid) to authenticated;
grant execute on function public.send_chat_message(uuid,uuid,text) to authenticated;


notify pgrst, 'reload schema';
commit;

select 'Dung An migration committed. Run verify_dung_an_management.sql next.' as result;