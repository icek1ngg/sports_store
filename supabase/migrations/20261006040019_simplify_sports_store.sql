-- Simplify the foundational schema after the first two migrations.
--
-- This migration intentionally refuses to discard existing business rows.  It
-- is safe for the currently empty project only; any populated target table
-- aborts the migration before policies, keys, or tables are changed.

select pg_advisory_xact_lock(
  hashtextextended('sports_store_simplify_20261006035307', 0)
);

-- Take the locks in one stable order before checking emptiness.  The advisory
-- lock coordinates repeat runs of this migration; these table locks also
-- prevent a concurrent writer from inserting a row between the guard and the
-- destructive RESTRICT drops.
lock table
  public.business_events,
  public.cart_items,
  public.carts,
  public.cod_collections,
  public.conversation_reads,
  public.conversations,
  public.delivery_attempts,
  public.delivery_incidents,
  public.delivery_tasks,
  public.inventory_balances,
  public.inventory_movements,
  public.messages,
  public.notifications,
  public.order_items,
  public.orders,
  public.product_variants,
  public.refund_accounts,
  public.refunds,
  public.return_evidence,
  public.return_items,
  public.return_requests
in access exclusive mode;

do $$
declare
  table_name text;
  has_rows boolean;
begin
  foreach table_name in array array[
    'inventory_balances',
    'product_variants',
    'carts',
    'cart_items',
    'return_evidence',
    'refund_accounts',
    'refunds',
    'return_requests',
    'return_items',
    'delivery_incidents',
    'delivery_tasks',
    'delivery_attempts',
    'cod_collections',
    'inventory_movements',
    'business_events',
    'notifications',
    'conversations',
    'messages',
    'conversation_reads',
    'orders',
    'order_items'
  ] loop
    execute format(
      'select exists (select 1 from public.%I)',
      table_name
    )
    into has_rows;

    if has_rows then
      raise exception
        'sports_store_simplify aborted: public.% contains data',
        table_name
        using errcode = 'P0001';
    end if;
  end loop;
end;
$$;

-- Remove policies that mention tables or columns being consolidated.  DROP
-- TABLE below remains RESTRICT so an unexpected dependency still aborts.
drop policy if exists inventory_balances_read on public.inventory_balances;

drop policy if exists carts_read on public.carts;
drop policy if exists carts_insert on public.carts;
drop policy if exists carts_delete on public.carts;

drop policy if exists incidents_read on public.delivery_incidents;
drop policy if exists return_evidence_read on public.return_evidence;
drop policy if exists refund_accounts_read on public.refund_accounts;
drop policy if exists refunds_read on public.refunds;

drop policy if exists conversation_reads_read on public.conversation_reads;
drop policy if exists conversation_reads_insert on public.conversation_reads;
drop policy if exists conversation_reads_update on public.conversation_reads;

drop policy if exists business_events_read on public.business_events;

drop policy if exists cart_items_read on public.cart_items;
drop policy if exists cart_items_insert on public.cart_items;
drop policy if exists cart_items_update on public.cart_items;
drop policy if exists cart_items_delete on public.cart_items;

-- These policies reference the old evidence/refund tables and must be removed
-- before those tables can be dropped with RESTRICT.
drop policy if exists sports_store_return_videos_read on storage.objects;
drop policy if exists sports_store_inspection_evidence_read on storage.objects;
drop policy if exists sports_store_refund_evidence_read on storage.objects;

revoke insert, update, delete on public.cart_items from authenticated;

drop trigger if exists carts_set_updated_at on public.carts;
drop trigger if exists inventory_balances_set_updated_at on public.inventory_balances;
drop trigger if exists refund_accounts_set_updated_at on public.refund_accounts;
drop trigger if exists conversation_reads_stamp_read_time on public.conversation_reads;

-- A cart is represented by one customer-owned item set.  The guard above makes
-- this key replacement lossless for the empty deployment.
alter table public.cart_items
  drop constraint cart_items_cart_id_fkey,
  drop constraint cart_items_pkey;

alter table public.cart_items
  add column customer_id uuid;

alter table public.cart_items
  drop column cart_id;

alter table public.cart_items
  alter column customer_id set not null,
  add constraint cart_items_customer_id_fkey
    foreign key (customer_id) references public.profiles (id) on delete cascade,
  add primary key (customer_id, variant_id);

-- Inventory is owned by the variant row.  Client grants from the previous
-- migration do not include these new stock columns.
alter table public.product_variants
  add column on_hand bigint not null default 0;

alter table public.product_variants
  add column reserved bigint not null default 0;

alter table public.product_variants
  add column damaged bigint not null default 0;

alter table public.product_variants
  add column available_quantity bigint
    generated always as (on_hand - reserved) stored;

alter table public.product_variants
  add constraint product_variants_on_hand_nonnegative
    check (on_hand >= 0),
  add constraint product_variants_reserved_nonnegative
    check (reserved >= 0),
  add constraint product_variants_damaged_nonnegative
    check (damaged >= 0),
  add constraint product_variants_reserved_not_over_on_hand
    check (reserved <= on_hand);

-- Delivery incidents use the existing business event ledger.  Generic
-- state-change events keep these columns NULL; incident rows require the
-- assigned task, actor, idempotency request and a nonblank reason.
alter table public.business_events
  add column task_id uuid,
  add column incident_kind public.delivery_incident_kind,
  add column request_id uuid;

alter table public.business_events
  add constraint business_events_task_fkey
    foreign key (task_id) references public.delivery_tasks (id),
  add constraint business_events_request_id_unique
    unique (request_id),
  add constraint business_events_incident_fields
    check (
      incident_kind is null
      or (
        subject_type = 'delivery_task'
        and subject_id = task_id
        and task_id is not null
        and actor_id is not null
        and request_id is not null
        and reason is not null
        and btrim(reason) <> ''
      )
    );

create index business_events_task_id_idx
  on public.business_events (task_id);

-- Evidence and refund metadata live with the return request.  All merged
-- fields remain nullable until the corresponding workflow records a refund.
alter table public.return_requests
  add column inspection_evidence_paths text[] not null default '{}'::text[],
  add column additional_video_paths text[] not null default '{}'::text[],
  add column bank_name text,
  add column account_number text,
  add column account_holder text,
  add column refund_amount_vnd bigint,
  add column refunded_by uuid,
  add column refunded_at timestamptz,
  add column transfer_evidence_path text,
  add column refund_request_id uuid;

alter table public.return_requests
  add constraint return_requests_inspection_paths_valid
    check (
      array_position(inspection_evidence_paths, null) is null
      and array_position(inspection_evidence_paths, '') is null
    ),
  add constraint return_requests_additional_video_paths_valid
    check (
      array_position(additional_video_paths, null) is null
      and array_position(additional_video_paths, '') is null
    ),
  add constraint return_requests_bank_bundle_complete
    check (
      (
        bank_name is null
        and account_number is null
        and account_holder is null
      )
      or (
        btrim(coalesce(bank_name, '')) <> ''
        and btrim(coalesce(account_number, '')) <> ''
        and btrim(coalesce(account_holder, '')) <> ''
      )
    ),
  add constraint return_requests_refund_amount_positive
    check (refund_amount_vnd is null or refund_amount_vnd > 0),
  add constraint return_requests_refund_bundle_complete
    check (
      (
        refund_amount_vnd is null
        and refunded_by is null
        and refunded_at is null
        and transfer_evidence_path is null
        and refund_request_id is null
      )
      or (
        refund_amount_vnd is not null
        and refund_amount_vnd > 0
        and refunded_by is not null
        and refunded_at is not null
        and btrim(coalesce(transfer_evidence_path, '')) <> ''
        and refund_request_id is not null
      )
    ),
  add constraint return_requests_refunded_by_fkey
    foreign key (refunded_by) references public.profiles (id),
  add constraint return_requests_refund_request_id_unique
    unique (refund_request_id);

create index return_requests_refunded_by_idx
  on public.return_requests (refunded_by);

-- The read path for a conversation is a per-user JSON object.  Only the
-- authenticated participant may update the column, and the trigger ignores
-- the submitted value in favor of OLD plus server time.
alter table public.conversations
  add column read_at_by_user jsonb not null default '{}'::jsonb,
  add constraint conversations_read_at_by_user_object
    check (jsonb_typeof(read_at_by_user) = 'object');

create or replace function private.stamp_conversation_read_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  reader_key text := (select auth.uid())::text;
begin
  if reader_key is null then
    new.read_at_by_user := old.read_at_by_user;
  else
    new.read_at_by_user := jsonb_set(
      coalesce(old.read_at_by_user, '{}'::jsonb),
      array[reader_key],
      to_jsonb(clock_timestamp()),
      true
    );
  end if;

  -- The original trigger keeps updated_at current for business changes.  A
  -- read-marker-only update is activity metadata, so restore its old value
  -- after conversations_set_updated_at has run alphabetically before this
  -- trigger.  This leaves real conversation edits timestamped normally.
  if (to_jsonb(new) - 'read_at_by_user' - 'updated_at')
     = (to_jsonb(old) - 'read_at_by_user' - 'updated_at') then
    new.updated_at := old.updated_at;
  end if;

  return new;
end;
$$;

revoke all on function private.stamp_conversation_read_at()
  from public, anon, authenticated, service_role;

create trigger conversations_stamp_read_at
before update of read_at_by_user on public.conversations
for each row execute function private.stamp_conversation_read_at();

-- Recreate the cart policy with the final customer_id key and explicit column
-- grants.  There is intentionally no client write path for inventory, events,
-- delivery, COD, return decisions, or refund state.
create policy cart_items_read on public.cart_items
for select to authenticated
using (
  (select private.current_app_role()) = 'customer'
  and customer_id = (select auth.uid())
);

create policy cart_items_insert on public.cart_items
for insert to authenticated
with check (
  (select private.current_app_role()) = 'customer'
  and customer_id = (select auth.uid())
  and exists (
    select 1
    from public.product_variants v
    where v.id = variant_id and v.is_active
  )
);

create policy cart_items_update on public.cart_items
for update to authenticated
using (
  (select private.current_app_role()) = 'customer'
  and customer_id = (select auth.uid())
)
with check (
  (select private.current_app_role()) = 'customer'
  and customer_id = (select auth.uid())
);

create policy cart_items_delete on public.cart_items
for delete to authenticated
using (
  (select private.current_app_role()) = 'customer'
  and customer_id = (select auth.uid())
);

grant insert (customer_id, variant_id, quantity),
  update (quantity),
  delete on public.cart_items to authenticated;

create policy business_events_read on public.business_events
for select to authenticated
using (
  (select private.current_app_role()) = 'manager'
  or (
    (select private.current_app_role()) = 'shipper'
    and incident_kind is not null
    and actor_id = (select auth.uid())
    and exists (
      select 1
      from public.delivery_tasks t
      where t.id = task_id
        and t.assigned_shipper_id = (select auth.uid())
    )
  )
);

create policy conversations_update_read_at on public.conversations
for update to authenticated
using (
  (select private.current_app_role()) = 'manager'
  or (
    (select private.current_app_role()) = 'customer'
    and customer_id = (select auth.uid())
  )
)
with check (
  (select private.current_app_role()) = 'manager'
  or (
    (select private.current_app_role()) = 'customer'
    and customer_id = (select auth.uid())
  )
);

grant update (read_at_by_user) on public.conversations to authenticated;

-- Drop only after policies, triggers, and cart foreign keys have been handled.
drop table public.inventory_balances restrict;
drop table public.carts restrict;
drop table public.delivery_incidents restrict;
drop table public.return_evidence restrict;
drop table public.refund_accounts restrict;
drop table public.refunds restrict;
drop table public.conversation_reads restrict;

-- The old storage policies referenced the removed evidence/refund tables.
-- Customer access remains scoped to the user's own return-video folder;
-- manager access is limited to paths recorded on return_requests.
create policy sports_store_return_videos_read on storage.objects
for select to authenticated
using (
  bucket_id = 'return-videos'
  and (
    (
      (select private.current_app_role()) = 'customer'
      and (storage.foldername(name))[1] = (select auth.uid())::text
    )
    or (
      (select private.current_app_role()) = 'manager'
      and exists (
        select 1
        from public.return_requests r
        where r.video_object_path = name
           or name = any(r.additional_video_paths)
      )
    )
  )
);

create policy sports_store_inspection_evidence_read on storage.objects
for select to authenticated
using (
  bucket_id = 'inspection-evidence'
  and (
    (select private.current_app_role()) = 'manager'
    or (
      (select private.current_app_role()) = 'customer'
      and exists (
        select 1
        from public.return_requests r
        where r.customer_id = (select auth.uid())
          and name = any(r.inspection_evidence_paths)
      )
    )
  )
);

create policy sports_store_refund_evidence_read on storage.objects
for select to authenticated
using (
  bucket_id = 'refund-evidence'
  and (
    (select private.current_app_role()) = 'manager'
    or (
      (select private.current_app_role()) = 'customer'
      and exists (
        select 1
        from public.return_requests r
        where r.customer_id = (select auth.uid())
          and r.transfer_evidence_path = name
      )
    )
  )
);

notify pgrst, 'reload schema';
