-- Online Sports Store foundational schema.
--
-- This migration creates the shared data contract for MH01-MH20.  It deliberately
-- does not expose a client write path: the follow-up access migration grants only
-- the reads and policies that are safe for each role, while transactional business
-- operations will be implemented as server-side RPCs.

create schema if not exists private;

-- Keep the helper schema out of the Data API and out of client reach.
revoke all on schema private from public, anon, authenticated, service_role;

create type public.user_role as enum (
  'customer',
  'manager',
  'shipper'
);

create type public.order_status as enum (
  'pending_confirmation',
  'preparing',
  'awaiting_pickup',
  'delivering',
  'awaiting_redelivery',
  'awaiting_store_return',
  'delivered',
  'cancelled',
  'rejected',
  'undeliverable_returned'
);

create type public.order_confirmation_source as enum (
  'manager',
  'automatic'
);

create type public.inventory_movement_kind as enum (
  'reserve',
  'release',
  'dispatch',
  'restock',
  'damage',
  'loss',
  'adjustment',
  'return_received'
);

create type public.delivery_task_kind as enum (
  'outbound',
  'return_pickup',
  'redelivery'
);

create type public.delivery_task_status as enum (
  'pending_assignment',
  'assigned',
  'accepted',
  'in_transit',
  'delivered',
  'failed',
  'returned_to_store',
  'cancelled',
  'manager_action_required'
);

create type public.delivery_attempt_result as enum (
  'success',
  'failed'
);

create type public.delivery_incident_kind as enum (
  'damaged',
  'lost',
  'other'
);

create type public.cod_status as enum (
  'uncollected',
  'collected',
  'received'
);

create type public.return_request_status as enum (
  'pending_review',
  'initially_rejected',
  'awaiting_return_pickup',
  'returning_to_store',
  'under_inspection',
  'awaiting_refund',
  'refunded',
  'rejected_after_inspection',
  'awaiting_redelivery',
  'redelivery_failed',
  'manager_action_required'
);

create type public.return_reason as enum (
  'wrong_item',
  'missing_items',
  'defective'
);

create type public.return_evidence_kind as enum (
  'customer_video',
  'inspection'
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role public.user_role not null default 'customer',
  full_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint categories_code_nonblank check (btrim(code) <> ''),
  constraint categories_name_nonblank check (btrim(name) <> '')
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories (id),
  name text not null,
  description text,
  image_path text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_name_nonblank check (btrim(name) <> '')
);

create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id),
  sku text not null unique,
  label text not null,
  attributes jsonb not null default '{}'::jsonb,
  price_vnd bigint not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_variants_sku_nonblank check (btrim(sku) <> ''),
  constraint product_variants_label_nonblank check (btrim(label) <> ''),
  constraint product_variants_attributes_object
    check (jsonb_typeof(attributes) = 'object'),
  constraint product_variants_price_nonnegative check (price_vnd >= 0)
);

create table public.inventory_balances (
  variant_id uuid primary key references public.product_variants (id),
  on_hand bigint not null default 0,
  reserved bigint not null default 0,
  damaged bigint not null default 0,
  available_quantity bigint generated always as (on_hand - reserved) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint inventory_balances_on_hand_nonnegative check (on_hand >= 0),
  constraint inventory_balances_reserved_nonnegative check (reserved >= 0),
  constraint inventory_balances_damaged_nonnegative check (damaged >= 0),
  constraint inventory_balances_reserved_not_over_on_hand
    check (reserved <= on_hand)
);

create table public.carts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null unique references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.cart_items (
  cart_id uuid not null references public.carts (id) on delete cascade,
  variant_id uuid not null references public.product_variants (id),
  quantity bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (cart_id, variant_id),
  constraint cart_items_quantity_positive check (quantity > 0)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id),
  request_id uuid not null,
  status public.order_status not null default 'pending_confirmation',
  recipient_name text not null,
  recipient_phone text not null,
  address_detail text not null,
  latitude numeric(9, 6) not null,
  longitude numeric(9, 6) not null,
  subtotal_vnd bigint not null,
  delivery_fee_vnd bigint not null default 30000,
  total_cod_vnd bigint generated always as (subtotal_vnd + delivery_fee_vnd) stored,
  delivery_attempt_count smallint not null default 0,
  placed_at timestamptz not null default now(),
  confirmed_at timestamptz,
  source public.order_confirmation_source,
  confirmed_by uuid references public.profiles (id) on delete set null,
  delivered_at timestamptz,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orders_customer_request_unique unique (customer_id, request_id),
  constraint orders_id_customer_unique unique (id, customer_id),
  constraint orders_recipient_name_nonblank check (btrim(recipient_name) <> ''),
  constraint orders_recipient_phone_nonblank check (btrim(recipient_phone) <> ''),
  constraint orders_address_nonblank check (btrim(address_detail) <> ''),
  constraint orders_latitude_valid check (latitude between -90 and 90),
  constraint orders_longitude_valid check (longitude between -180 and 180),
  constraint orders_subtotal_nonnegative check (subtotal_vnd >= 0),
  constraint orders_delivery_fee_fixed check (delivery_fee_vnd = 30000),
  constraint orders_delivery_attempt_count_valid
    check (delivery_attempt_count between 0 and 2)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id),
  product_id uuid not null references public.products (id),
  variant_id uuid not null references public.product_variants (id),
  product_name text not null,
  variant_label text not null,
  attributes jsonb not null default '{}'::jsonb,
  unit_price_vnd bigint not null,
  quantity bigint not null,
  line_total_vnd bigint generated always as (unit_price_vnd * quantity) stored,
  created_at timestamptz not null default now(),
  constraint order_items_product_name_nonblank check (btrim(product_name) <> ''),
  constraint order_items_variant_label_nonblank check (btrim(variant_label) <> ''),
  constraint order_items_attributes_object
    check (jsonb_typeof(attributes) = 'object'),
  constraint order_items_unit_price_nonnegative check (unit_price_vnd >= 0),
  constraint order_items_quantity_positive check (quantity > 0),
  constraint order_items_order_variant_unique unique (order_id, variant_id),
  constraint order_items_id_order_unique unique (id, order_id)
);

create table public.return_requests (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null,
  customer_id uuid not null references public.profiles (id),
  request_id uuid not null,
  status public.return_request_status not null default 'pending_review',
  reason public.return_reason not null,
  description text not null,
  video_object_path text not null,
  submitted_at timestamptz not null default now(),
  decision_reason text,
  decision_at timestamptz,
  decided_by uuid references public.profiles (id) on delete set null,
  inspection_started_at timestamptz,
  inspected_at timestamptz,
  inspected_by uuid references public.profiles (id) on delete set null,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint return_requests_customer_request_unique
    unique (customer_id, request_id),
  constraint return_requests_id_order_unique
    unique (id, order_id),
  constraint return_requests_order_customer_fkey
    foreign key (order_id, customer_id)
    references public.orders (id, customer_id),
  constraint return_requests_description_nonblank
    check (btrim(description) <> ''),
  constraint return_requests_video_path_nonblank
    check (btrim(video_object_path) <> '')
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants (id),
  order_id uuid references public.orders (id),
  return_request_id uuid references public.return_requests (id),
  event_id uuid not null,
  kind public.inventory_movement_kind not null,
  on_hand_delta bigint not null default 0,
  reserved_delta bigint not null default 0,
  damaged_delta bigint not null default 0,
  actor_id uuid references public.profiles (id) on delete set null,
  reason text,
  created_at timestamptz not null default now(),
  constraint inventory_movements_nonzero_delta
    check (on_hand_delta <> 0 or reserved_delta <> 0 or damaged_delta <> 0),
  constraint inventory_movements_event_variant_unique
    unique (event_id, variant_id)
);

create table public.delivery_tasks (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null,
  return_request_id uuid,
  kind public.delivery_task_kind not null default 'outbound',
  assigned_shipper_id uuid references public.profiles (id) on delete set null,
  assigned_by uuid references public.profiles (id) on delete set null,
  status public.delivery_task_status not null default 'pending_assignment',
  attempt_number smallint not null default 1,
  destination_name text not null,
  destination_phone text not null,
  destination_address text not null,
  destination_latitude numeric(9, 6) not null,
  destination_longitude numeric(9, 6) not null,
  amount_to_collect_vnd bigint not null default 0,
  assigned_at timestamptz,
  accepted_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  failure_reason text,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint delivery_tasks_destination_name_nonblank
    check (btrim(destination_name) <> ''),
  constraint delivery_tasks_destination_phone_nonblank
    check (btrim(destination_phone) <> ''),
  constraint delivery_tasks_destination_address_nonblank
    check (btrim(destination_address) <> ''),
  constraint delivery_tasks_latitude_valid
    check (destination_latitude between -90 and 90),
  constraint delivery_tasks_longitude_valid
    check (destination_longitude between -180 and 180),
  constraint delivery_tasks_attempt_valid check (
    (kind = 'outbound' and attempt_number between 1 and 2)
    or (kind <> 'outbound' and attempt_number = 1)
  ),
  constraint delivery_tasks_amount_nonnegative check (amount_to_collect_vnd >= 0),
  constraint delivery_tasks_non_outbound_free check (
    kind = 'outbound' or amount_to_collect_vnd = 0
  ),
  constraint delivery_tasks_order_fkey
    foreign key (order_id) references public.orders (id),
  constraint delivery_tasks_return_order_fkey
    foreign key (return_request_id, order_id)
    references public.return_requests (id, order_id),
  constraint delivery_tasks_return_reference_by_kind check (
    (kind = 'outbound' and return_request_id is null)
    or (kind <> 'outbound' and return_request_id is not null)
  ),
  constraint delivery_tasks_id_order_attempt_kind_unique
    unique (id, order_id, attempt_number, kind)
);

create table public.delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null unique references public.delivery_tasks (id),
  order_id uuid not null,
  attempt_number smallint not null,
  task_kind public.delivery_task_kind not null default 'outbound',
  result public.delivery_attempt_result not null,
  reason text,
  occurred_at timestamptz not null default now(),
  shipper_id uuid not null references public.profiles (id),
  constraint delivery_attempts_number_valid check (attempt_number between 1 and 2),
  constraint delivery_attempts_task_kind_outbound
    check (task_kind = 'outbound'),
  constraint delivery_attempts_task_contract_fkey
    foreign key (task_id, order_id, attempt_number, task_kind)
    references public.delivery_tasks (id, order_id, attempt_number, kind),
  constraint delivery_attempts_order_fkey
    foreign key (order_id) references public.orders (id),
  constraint delivery_attempts_order_number_unique unique (order_id, attempt_number),
  constraint delivery_attempts_failed_reason check (
    result = 'success'
    or nullif(btrim(coalesce(reason, '')), '') is not null
  )
);

create table public.delivery_incidents (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.delivery_tasks (id),
  shipper_id uuid not null references public.profiles (id),
  kind public.delivery_incident_kind not null,
  description text not null,
  event_id uuid not null unique,
  created_at timestamptz not null default now(),
  constraint delivery_incidents_description_nonblank
    check (btrim(description) <> '')
);

create table public.cod_collections (
  order_id uuid primary key references public.orders (id),
  shipper_id uuid references public.profiles (id) on delete set null,
  status public.cod_status not null default 'uncollected',
  expected_amount_vnd bigint not null,
  collected_amount_vnd bigint not null default 0,
  received_amount_vnd bigint not null default 0,
  collected_at timestamptz,
  collected_by uuid references public.profiles (id) on delete set null,
  handed_over_at timestamptz,
  received_at timestamptz,
  received_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cod_expected_positive check (expected_amount_vnd > 0),
  constraint cod_collected_nonnegative check (collected_amount_vnd >= 0),
  constraint cod_received_nonnegative check (received_amount_vnd >= 0),
  constraint cod_collected_not_over_expected
    check (collected_amount_vnd <= expected_amount_vnd),
  constraint cod_received_not_over_collected
    check (received_amount_vnd <= collected_amount_vnd),
  constraint cod_collected_amount_matches_status check (
    (status = 'uncollected' and collected_amount_vnd = 0)
    or (status in ('collected', 'received')
      and collected_amount_vnd = expected_amount_vnd)
  ),
  constraint cod_received_amount_matches_status check (
    (status in ('uncollected', 'collected') and received_amount_vnd = 0)
    or (status = 'received' and received_amount_vnd = expected_amount_vnd)
  )
);

create table public.return_items (
  id uuid primary key default gen_random_uuid(),
  return_request_id uuid not null,
  order_id uuid not null,
  order_item_id uuid,
  actual_item_name text not null,
  variant_id uuid references public.product_variants (id),
  quantity_to_collect bigint not null,
  quantity_collected bigint not null default 0,
  sellable_quantity bigint not null default 0,
  damaged_quantity bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint return_items_actual_name_nonblank
    check (btrim(actual_item_name) <> ''),
  constraint return_items_return_order_fkey
    foreign key (return_request_id, order_id)
    references public.return_requests (id, order_id),
  constraint return_items_order_item_fkey
    foreign key (order_item_id, order_id)
    references public.order_items (id, order_id),
  constraint return_items_quantity_to_collect_positive
    check (quantity_to_collect > 0),
  constraint return_items_quantity_collected_valid
    check (quantity_collected between 0 and quantity_to_collect),
  constraint return_items_sellable_nonnegative
    check (sellable_quantity >= 0),
  constraint return_items_damaged_nonnegative
    check (damaged_quantity >= 0),
  constraint return_items_inspection_totals_valid
    check (sellable_quantity + damaged_quantity <= quantity_collected)
);

create table public.return_evidence (
  id uuid primary key default gen_random_uuid(),
  return_request_id uuid not null references public.return_requests (id),
  uploader_id uuid not null references public.profiles (id),
  kind public.return_evidence_kind not null,
  object_path text not null,
  created_at timestamptz not null default now(),
  constraint return_evidence_object_path_nonblank
    check (btrim(object_path) <> '')
);

create table public.refund_accounts (
  return_request_id uuid primary key references public.return_requests (id),
  bank_name text not null,
  account_number text not null,
  account_holder text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint refund_accounts_bank_name_nonblank
    check (btrim(bank_name) <> ''),
  constraint refund_accounts_account_number_nonblank
    check (btrim(account_number) <> ''),
  constraint refund_accounts_account_holder_nonblank
    check (btrim(account_holder) <> '')
);

create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  return_request_id uuid not null unique references public.return_requests (id),
  amount_vnd bigint not null,
  refunded_by uuid not null references public.profiles (id),
  refunded_at timestamptz not null default now(),
  transfer_evidence_path text not null,
  request_id uuid not null unique,
  created_at timestamptz not null default now(),
  constraint refunds_amount_positive check (amount_vnd > 0),
  constraint refunds_evidence_path_nonblank
    check (btrim(transfer_evidence_path) <> '')
);

create table public.business_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles (id) on delete set null,
  subject_type text not null,
  subject_id uuid not null,
  from_state text,
  to_state text,
  reason text,
  created_at timestamptz not null default now(),
  constraint business_events_subject_type_nonblank
    check (btrim(subject_type) <> ''),
  constraint business_events_from_state_nonblank
    check (from_state is null or btrim(from_state) <> ''),
  constraint business_events_to_state_nonblank
    check (to_state is null or btrim(to_state) <> '')
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  event_id uuid not null references public.business_events (id),
  subject_type text not null,
  subject_id uuid not null,
  title text not null,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint notifications_recipient_event_unique
    unique (recipient_id, event_id),
  constraint notifications_subject_type_nonblank
    check (btrim(subject_type) <> ''),
  constraint notifications_title_nonblank check (btrim(title) <> ''),
  constraint notifications_body_nonblank check (btrim(body) <> '')
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null unique references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id),
  body text not null,
  client_message_id uuid not null,
  created_at timestamptz not null default now(),
  constraint messages_sender_client_id_unique
    unique (sender_id, client_message_id),
  constraint messages_body_nonblank check (btrim(body) <> '')
);

create table public.conversation_reads (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table public.store_settings (
  id boolean primary key default true,
  name text not null,
  address text,
  latitude numeric(9, 6),
  longitude numeric(9, 6),
  approved_service_area_geojson jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint store_settings_singleton check (id),
  constraint store_settings_name_nonblank check (btrim(name) <> ''),
  constraint store_settings_coordinates_paired
    check ((latitude is null) = (longitude is null)),
  constraint store_settings_latitude_valid
    check (latitude is null or latitude between -90 and 90),
  constraint store_settings_longitude_valid
    check (longitude is null or longitude between -180 and 180),
  constraint store_settings_geojson_object
    check (
      approved_service_area_geojson is null
      or jsonb_typeof(approved_service_area_geojson) = 'object'
    )
);

-- Index every foreign-key column that is not already covered by a primary or
-- unique index.  These also support the future RLS ownership predicates.
create index products_category_id_idx on public.products (category_id);
create index product_variants_product_id_idx on public.product_variants (product_id);

create index inventory_movements_variant_id_idx
  on public.inventory_movements (variant_id);
create index inventory_movements_order_id_idx
  on public.inventory_movements (order_id);
create index inventory_movements_return_request_id_idx
  on public.inventory_movements (return_request_id);
create index inventory_movements_actor_id_idx
  on public.inventory_movements (actor_id);

create index cart_items_variant_id_idx on public.cart_items (variant_id);
create index orders_customer_id_idx on public.orders (customer_id);
create index orders_confirmed_by_idx on public.orders (confirmed_by);
create index order_items_order_id_idx on public.order_items (order_id);
create index order_items_product_id_idx on public.order_items (product_id);
create index order_items_variant_id_idx on public.order_items (variant_id);

create index return_requests_order_id_idx
  on public.return_requests (order_id);
create index return_requests_order_customer_idx
  on public.return_requests (order_id, customer_id);
create index return_requests_customer_id_idx
  on public.return_requests (customer_id);
create index return_requests_decided_by_idx
  on public.return_requests (decided_by);
create index return_requests_inspected_by_idx
  on public.return_requests (inspected_by);

create index delivery_tasks_order_id_idx on public.delivery_tasks (order_id);
create index delivery_tasks_return_request_id_idx
  on public.delivery_tasks (return_request_id);
create index delivery_tasks_return_order_idx
  on public.delivery_tasks (return_request_id, order_id);
create index delivery_tasks_assigned_shipper_id_idx
  on public.delivery_tasks (assigned_shipper_id);
create index delivery_tasks_assigned_by_idx
  on public.delivery_tasks (assigned_by);

create index delivery_attempts_order_id_idx
  on public.delivery_attempts (order_id);
create index delivery_attempts_task_contract_idx
  on public.delivery_attempts (task_id, order_id, attempt_number, task_kind);
create index delivery_attempts_shipper_id_idx
  on public.delivery_attempts (shipper_id);
create index delivery_incidents_task_id_idx
  on public.delivery_incidents (task_id);
create index delivery_incidents_shipper_id_idx
  on public.delivery_incidents (shipper_id);

create index cod_collections_shipper_id_idx
  on public.cod_collections (shipper_id);
create index cod_collections_collected_by_idx
  on public.cod_collections (collected_by);
create index cod_collections_received_by_idx
  on public.cod_collections (received_by);

create index return_items_return_request_id_idx
  on public.return_items (return_request_id);
create index return_items_return_order_idx
  on public.return_items (return_request_id, order_id);
create index return_items_order_item_id_idx
  on public.return_items (order_item_id);
create index return_items_order_item_order_idx
  on public.return_items (order_item_id, order_id);
create index return_items_variant_id_idx
  on public.return_items (variant_id);
create index return_evidence_return_request_id_idx
  on public.return_evidence (return_request_id);
create index return_evidence_uploader_id_idx
  on public.return_evidence (uploader_id);
create index refunds_refunded_by_idx on public.refunds (refunded_by);

create index business_events_actor_id_idx on public.business_events (actor_id);
create index business_events_subject_idx
  on public.business_events (subject_type, subject_id, created_at desc);

create index notifications_recipient_created_idx
  on public.notifications (recipient_id, created_at desc);
create index notifications_event_id_idx on public.notifications (event_id);
create index notifications_subject_idx
  on public.notifications (subject_type, subject_id);

create index messages_conversation_created_idx
  on public.messages (conversation_id, created_at, id);
create index messages_sender_id_idx on public.messages (sender_id);
create index conversation_reads_user_id_idx on public.conversation_reads (user_id);

-- There may be several terminal tasks for an order over time, but only one
-- active outbound task and one active return/redelivery task at a time.
create unique index delivery_tasks_one_active_outbound_idx
  on public.delivery_tasks (order_id)
  where kind = 'outbound'
    and status in ('pending_assignment', 'assigned', 'accepted', 'in_transit');

create unique index delivery_tasks_one_active_return_idx
  on public.delivery_tasks (return_request_id)
  where return_request_id is not null
    and kind in ('return_pickup', 'redelivery')
    and status in (
      'pending_assignment',
      'assigned',
      'accepted',
      'in_transit',
      'manager_action_required'
    );

create unique index return_requests_one_active_per_order_idx
  on public.return_requests (order_id)
  where status in (
    'pending_review',
    'awaiting_return_pickup',
    'returning_to_store',
    'under_inspection',
    'awaiting_refund',
    'awaiting_redelivery',
    'redelivery_failed',
    'manager_action_required'
  );

-- The three categories are part of the report's fixed catalogue.  No products,
-- accounts, or store coordinates are seeded here.
insert into public.categories (code, name)
values
  ('apparel', 'Quần áo'),
  ('shoes', 'Giày'),
  ('equipment', 'Dụng cụ')
on conflict (code) do nothing;

-- Private trigger helpers.  The user-created profile trigger is the only
-- SECURITY DEFINER function in this migration and it ignores any requested
-- role, always provisioning a customer.  User metadata is used only for the
-- optional display name.
create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    new.phone,
    'customer'::public.user_role
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- The definer function is never a client-callable RPC.  The trigger owner can
-- still invoke it when Supabase Auth creates a user.
revoke all on function private.handle_new_user() from public, anon, authenticated, service_role;
revoke all on function private.set_updated_at() from public, anon, authenticated, service_role;

-- Supabase Auth invokes the trigger as its own role.  Keep the function
-- unreachable to API clients while permitting that internal trigger call on
-- hosted/local Supabase installations.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    execute 'grant execute on function private.handle_new_user() to supabase_auth_admin';
  end if;
  if exists (select 1 from pg_roles where rolname = 'postgres') then
    execute 'grant execute on function private.set_updated_at() to postgres';
  end if;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger categories_set_updated_at
before update on public.categories
for each row execute function private.set_updated_at();

create trigger products_set_updated_at
before update on public.products
for each row execute function private.set_updated_at();

create trigger product_variants_set_updated_at
before update on public.product_variants
for each row execute function private.set_updated_at();

create trigger inventory_balances_set_updated_at
before update on public.inventory_balances
for each row execute function private.set_updated_at();

create trigger carts_set_updated_at
before update on public.carts
for each row execute function private.set_updated_at();

create trigger cart_items_set_updated_at
before update on public.cart_items
for each row execute function private.set_updated_at();

create trigger orders_set_updated_at
before update on public.orders
for each row execute function private.set_updated_at();

create trigger return_requests_set_updated_at
before update on public.return_requests
for each row execute function private.set_updated_at();

create trigger delivery_tasks_set_updated_at
before update on public.delivery_tasks
for each row execute function private.set_updated_at();

create trigger cod_collections_set_updated_at
before update on public.cod_collections
for each row execute function private.set_updated_at();

create trigger return_items_set_updated_at
before update on public.return_items
for each row execute function private.set_updated_at();

create trigger refund_accounts_set_updated_at
before update on public.refund_accounts
for each row execute function private.set_updated_at();

create trigger conversations_set_updated_at
before update on public.conversations
for each row execute function private.set_updated_at();

create trigger store_settings_set_updated_at
before update on public.store_settings
for each row execute function private.set_updated_at();

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

-- Ensure accounts that existed before this migration have a profile.  The
-- conflict clause deliberately preserves an administrator-provisioned role.
insert into public.profiles (id, full_name, phone, role)
select
  u.id,
  nullif(u.raw_user_meta_data ->> 'full_name', ''),
  u.phone,
  'customer'::public.user_role
from auth.users as u
on conflict (id) do nothing;

-- RLS is enabled before this migration completes.  The follow-up access
-- migration grants role-specific privileges and policies in a separate change.
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.inventory_balances enable row level security;
alter table public.carts enable row level security;
alter table public.cart_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.return_requests enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.delivery_tasks enable row level security;
alter table public.delivery_attempts enable row level security;
alter table public.delivery_incidents enable row level security;
alter table public.cod_collections enable row level security;
alter table public.return_items enable row level security;
alter table public.return_evidence enable row level security;
alter table public.refund_accounts enable row level security;
alter table public.refunds enable row level security;
alter table public.business_events enable row level security;
alter table public.notifications enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.conversation_reads enable row level security;
alter table public.store_settings enable row level security;

-- Prevent the default Data API grants from exposing a table between migrations.
revoke all on all tables in schema public from PUBLIC, anon, authenticated;
revoke all on all sequences in schema public from PUBLIC, anon, authenticated;
revoke all on all functions in schema public from PUBLIC, anon, authenticated;
