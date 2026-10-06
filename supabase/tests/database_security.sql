-- Sports Store final-schema security and invariant checks.
--
-- The fixture uses only the tables and columns from the final simplified
-- schema migration. It runs as a privileged database
-- test session, impersonates anon/authenticated users through the documented
-- request.jwt settings, prints a non-PII PASS row, and rolls everything back.

BEGIN;

SET CONSTRAINTS ALL DEFERRED;

CREATE OR REPLACE FUNCTION pg_temp.assert_rows(
  p_label text,
  p_query text,
  p_expected bigint
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  l_actual bigint;
BEGIN
  EXECUTE format('SELECT count(*) FROM (%s) AS database_test_rows', p_query)
    INTO l_actual;
  IF l_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'database test failed: % (expected %, got %)',
      p_label, p_expected, l_actual;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_exec_ok(
  p_label text,
  p_sql text
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE p_sql;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'database test failed: % (%): %',
      p_label, SQLSTATE, SQLERRM;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_raises(
  p_label text,
  p_sql text,
  p_allowed_states text[]
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  l_succeeded boolean := false;
  l_state text;
  l_message text;
BEGIN
  BEGIN
    EXECUTE p_sql;
    l_succeeded := true;
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        l_state = RETURNED_SQLSTATE,
        l_message = MESSAGE_TEXT;
  END;

  IF l_succeeded THEN
    RAISE EXCEPTION 'database test failed: % (statement unexpectedly succeeded)', p_label;
  END IF;
  IF NOT l_state = ANY (p_allowed_states) THEN
    RAISE EXCEPTION 'database test failed: % (unexpected SQLSTATE %): %',
      p_label, l_state, l_message;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_test_claims(
  p_user_id uuid,
  p_claimed_role text DEFAULT 'authenticated'
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user_id::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user_id::text,
      'role', p_claimed_role,
      'aud', p_claimed_role
    )::text,
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.clear_test_claims()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END;
$$;

-- Auth has added nullable and generated columns over time. Populate stable
-- columns and any required, default-less columns without inserting generated
-- values. The profile trigger remains part of the contract under test.
CREATE OR REPLACE FUNCTION pg_temp.create_auth_user(
  p_user_id uuid,
  p_email text,
  p_user_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  l_column text;
  l_columns text[] := ARRAY[]::text[];
  l_values text[] := ARRAY[]::text[];
  l_required text[] := ARRAY[]::text[];
  l_value text;
BEGIN
  FOR l_column IN
    SELECT c.column_name
    FROM information_schema.columns AS c
    WHERE c.table_schema = 'auth'
      AND c.table_name = 'users'
      AND c.is_generated = 'NEVER'
      AND c.is_identity = 'NO'
      AND (
        c.column_name IN (
          'id', 'instance_id', 'aud', 'role', 'email', 'encrypted_password',
          'confirmed_at', 'email_confirmed_at', 'raw_app_meta_data',
          'raw_user_meta_data', 'created_at', 'updated_at', 'is_super_admin',
          'is_sso_user', 'is_anonymous'
        )
        OR (c.is_nullable = 'NO' AND c.column_default IS NULL)
      )
    ORDER BY c.ordinal_position
  LOOP
    l_value := CASE l_column
      WHEN 'id' THEN '$1'
      WHEN 'instance_id' THEN quote_literal('00000000-0000-0000-0000-000000000000')
      WHEN 'aud' THEN quote_literal('authenticated')
      WHEN 'role' THEN quote_literal('authenticated')
      WHEN 'email' THEN '$2'
      WHEN 'encrypted_password' THEN quote_literal('')
      WHEN 'confirmed_at' THEN 'clock_timestamp()'
      WHEN 'email_confirmed_at' THEN 'clock_timestamp()'
      WHEN 'raw_app_meta_data' THEN quote_literal('{}') || '::jsonb'
      WHEN 'raw_user_meta_data' THEN '$3'
      WHEN 'created_at' THEN 'clock_timestamp()'
      WHEN 'updated_at' THEN 'clock_timestamp()'
      WHEN 'is_super_admin' THEN 'false'
      WHEN 'is_sso_user' THEN 'false'
      WHEN 'is_anonymous' THEN 'false'
      ELSE NULL
    END;

    IF l_value IS NULL THEN
      l_required := array_append(l_required, l_column);
    ELSE
      l_columns := array_append(l_columns, format('%I', l_column));
      l_values := array_append(l_values, l_value);
    END IF;
  END LOOP;

  IF coalesce(array_length(l_required, 1), 0) > 0 THEN
    RAISE EXCEPTION 'database test cannot seed auth.users; unsupported required columns: %',
      array_to_string(l_required, ', ');
  END IF;

  EXECUTE format(
    'INSERT INTO auth.users (%s) VALUES (%s)',
    array_to_string(l_columns, ', '),
    array_to_string(l_values, ', ')
  ) USING p_user_id, p_email, p_user_metadata;
END;
$$;

-- Deterministic local identities. No real account or recipient data is used.
SELECT set_config('database_test.customer_id', '10000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.other_customer_id', '10000000-0000-0000-0000-000000000002', true);
SELECT set_config('database_test.manager_id', '10000000-0000-0000-0000-000000000003', true);
SELECT set_config('database_test.shipper_id', '10000000-0000-0000-0000-000000000004', true);
SELECT set_config('database_test.other_shipper_id', '10000000-0000-0000-0000-000000000005', true);
SELECT set_config('database_test.category_id', '20000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.product_id', '30000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.variant_id', '40000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.order_id', '60000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.other_order_id', '60000000-0000-0000-0000-000000000002', true);
SELECT set_config('database_test.order_item_id', '70000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.task_id', '80000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.other_task_id', '80000000-0000-0000-0000-000000000002', true);
SELECT set_config('database_test.terminal_task_id', '80000000-0000-0000-0000-000000000003', true);
SELECT set_config('database_test.return_task_id', '80000000-0000-0000-0000-000000000004', true);
SELECT set_config('database_test.return_id', '90000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.other_return_id', '90000000-0000-0000-0000-000000000002', true);
SELECT set_config('database_test.conversation_id', 'a0000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.other_conversation_id', 'a0000000-0000-0000-0000-000000000002', true);
SELECT set_config('database_test.message_id', 'a1000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.other_message_id', 'a1000000-0000-0000-0000-000000000002', true);
SELECT set_config('database_test.event_id', 'b0000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.incident_event_id', 'b0000000-0000-0000-0000-000000000002', true);
SELECT set_config('database_test.notification_id', 'c0000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.manager_notification_id', 'c0000000-0000-0000-0000-000000000002', true);
SELECT set_config('database_test.message_client_id', 'a2000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.order_request_id', 'd0000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.return_request_id', 'd1000000-0000-0000-0000-000000000001', true);
SELECT set_config('database_test.other_return_request_id', 'd1000000-0000-0000-0000-000000000002', true);
SELECT set_config('database_test.incident_request_id', 'd2000000-0000-0000-0000-000000000001', true);

-- The customer tries to request a manager role through editable metadata. The
-- server trigger must still provision customer.
SELECT pg_temp.create_auth_user(
  current_setting('database_test.customer_id')::uuid,
  'database-test-customer@example.invalid',
  '{"role":"manager"}'::jsonb
);
SELECT pg_temp.create_auth_user(
  current_setting('database_test.other_customer_id')::uuid,
  'database-test-other@example.invalid'
);
SELECT pg_temp.create_auth_user(
  current_setting('database_test.manager_id')::uuid,
  'database-test-manager@example.invalid'
);
SELECT pg_temp.create_auth_user(
  current_setting('database_test.shipper_id')::uuid,
  'database-test-shipper@example.invalid'
);
SELECT pg_temp.create_auth_user(
  current_setting('database_test.other_shipper_id')::uuid,
  'database-test-other-shipper@example.invalid'
);

SELECT pg_temp.assert_rows(
  'new auth user is always provisioned as customer',
  format(
    'SELECT id FROM public.profiles WHERE id = %L::uuid AND role::text = %L',
    current_setting('database_test.customer_id'), 'customer'
  ),
  1
);

-- Trusted server provisioning for the non-customer fixtures.
UPDATE public.profiles SET role = 'manager'
WHERE id = current_setting('database_test.manager_id')::uuid;
UPDATE public.profiles SET role = 'shipper'
WHERE id = current_setting('database_test.shipper_id')::uuid;
UPDATE public.profiles SET role = 'shipper'
WHERE id = current_setting('database_test.other_shipper_id')::uuid;

-- Exact final-schema fixtures.
INSERT INTO public.categories (id, code, name, is_active)
VALUES (current_setting('database_test.category_id')::uuid, 'training', 'Training', true);

INSERT INTO public.products (id, category_id, name, description, is_active)
VALUES (
  current_setting('database_test.product_id')::uuid,
  current_setting('database_test.category_id')::uuid,
  'Training ball', 'Database test fixture', true
);

INSERT INTO public.product_variants
  (id, product_id, sku, label, attributes, price_vnd, is_active,
   on_hand, reserved, damaged)
VALUES (
  current_setting('database_test.variant_id')::uuid,
  current_setting('database_test.product_id')::uuid,
  'DB-TEST-001', 'Standard', '{}'::jsonb, 520000, true, 10, 2, 0
);

INSERT INTO public.cart_items (customer_id, variant_id, quantity)
VALUES (
  current_setting('database_test.customer_id')::uuid,
  current_setting('database_test.variant_id')::uuid,
  2
);

INSERT INTO public.orders
  (id, customer_id, request_id, status, recipient_name, recipient_phone,
   address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd)
VALUES (
  current_setting('database_test.order_id')::uuid,
  current_setting('database_test.customer_id')::uuid,
  current_setting('database_test.order_request_id')::uuid,
  'delivered', 'Fixture customer', '0900000001', 'Ba Dinh, Ha Noi',
  21.0333, 105.8333, 520000, 30000
);
INSERT INTO public.orders
  (id, customer_id, request_id, status, recipient_name, recipient_phone,
   address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd)
VALUES (
  current_setting('database_test.other_order_id')::uuid,
  current_setting('database_test.other_customer_id')::uuid,
  'd0000000-0000-0000-0000-000000000002'::uuid,
  'delivered', 'Fixture other', '0900000002', 'Cau Giay, Ha Noi',
  21.0340, 105.8010, 520000, 30000
);

INSERT INTO public.order_items
  (id, order_id, product_id, variant_id, product_name, variant_label,
   attributes, unit_price_vnd, quantity)
VALUES (
  current_setting('database_test.order_item_id')::uuid,
  current_setting('database_test.order_id')::uuid,
  current_setting('database_test.product_id')::uuid,
  current_setting('database_test.variant_id')::uuid,
  'Training ball', 'Standard', '{}'::jsonb, 520000, 1
);

INSERT INTO public.inventory_movements
  (variant_id, order_id, event_id, kind, reserved_delta, actor_id, reason)
VALUES (
  current_setting('database_test.variant_id')::uuid,
  current_setting('database_test.order_id')::uuid,
  'e0000000-0000-0000-0000-000000000001'::uuid,
  'reserve', 2, current_setting('database_test.manager_id')::uuid,
  'Database test fixture'
);

INSERT INTO public.return_requests
  (id, order_id, customer_id, request_id, status, reason, description,
   video_object_path, inspection_evidence_paths, additional_video_paths,
   bank_name, account_number, account_holder, refund_amount_vnd, refunded_by,
   refunded_at, transfer_evidence_path, refund_request_id)
VALUES (
  current_setting('database_test.return_id')::uuid,
  current_setting('database_test.order_id')::uuid,
  current_setting('database_test.customer_id')::uuid,
  current_setting('database_test.return_request_id')::uuid,
  'refunded', 'defective', 'Fixture defect',
  '10000000-0000-0000-0000-000000000001/90000000-0000-0000-0000-000000000001/video.mp4',
  ARRAY['90000000-0000-0000-0000-000000000001/inspection.pdf']::text[],
  ARRAY['10000000-0000-0000-0000-000000000001/90000000-0000-0000-0000-000000000001/additional.mp4']::text[],
  'Fixture Bank', '0000000001', 'Fixture Customer', 550000,
  current_setting('database_test.manager_id')::uuid, clock_timestamp(),
  '90000000-0000-0000-0000-000000000001/refund-evidence.pdf',
  'd3000000-0000-0000-0000-000000000001'::uuid
);
INSERT INTO public.return_requests
  (id, order_id, customer_id, request_id, status, reason, description,
   video_object_path, bank_name, account_number, account_holder,
   refund_amount_vnd, refunded_by, refunded_at, transfer_evidence_path,
   refund_request_id)
VALUES (
  current_setting('database_test.other_return_id')::uuid,
  current_setting('database_test.other_order_id')::uuid,
  current_setting('database_test.other_customer_id')::uuid,
  current_setting('database_test.other_return_request_id')::uuid,
  'refunded', 'wrong_item', 'Other fixture return',
  '10000000-0000-0000-0000-000000000002/90000000-0000-0000-0000-000000000002/video.mp4',
  'Other Bank', '0000000002', 'Other Customer', 550000,
  current_setting('database_test.manager_id')::uuid, clock_timestamp(),
  '90000000-0000-0000-0000-000000000002/refund-evidence.pdf',
  'd3000000-0000-0000-0000-000000000002'::uuid
);

INSERT INTO public.return_items
  (return_request_id, order_id, order_item_id, actual_item_name, variant_id,
   quantity_to_collect)
VALUES (
  current_setting('database_test.return_id')::uuid,
  current_setting('database_test.order_id')::uuid,
  current_setting('database_test.order_item_id')::uuid,
  'Training ball', current_setting('database_test.variant_id')::uuid, 1
);

INSERT INTO public.delivery_tasks
  (id, order_id, kind, assigned_shipper_id, assigned_by, status, attempt_number,
   destination_name, destination_phone, destination_address,
   destination_latitude, destination_longitude, amount_to_collect_vnd)
VALUES (
  current_setting('database_test.task_id')::uuid,
  current_setting('database_test.order_id')::uuid,
  'outbound', current_setting('database_test.shipper_id')::uuid,
  current_setting('database_test.manager_id')::uuid, 'assigned', 1,
  'Fixture customer', '0900000001', 'Ba Dinh, Ha Noi',
  21.0333, 105.8333, 550000
);
INSERT INTO public.delivery_tasks
  (id, order_id, kind, assigned_shipper_id, assigned_by, status, attempt_number,
   destination_name, destination_phone, destination_address,
   destination_latitude, destination_longitude, amount_to_collect_vnd)
VALUES (
  current_setting('database_test.other_task_id')::uuid,
  current_setting('database_test.other_order_id')::uuid,
  'outbound', current_setting('database_test.manager_id')::uuid,
  current_setting('database_test.manager_id')::uuid, 'assigned', 2,
  'Fixture other', '0900000002', 'Cau Giay, Ha Noi',
  21.0340, 105.8010, 550000
);
INSERT INTO public.delivery_tasks
  (id, order_id, kind, assigned_shipper_id, assigned_by, status, attempt_number,
   destination_name, destination_phone, destination_address,
   destination_latitude, destination_longitude, amount_to_collect_vnd)
VALUES (
  current_setting('database_test.terminal_task_id')::uuid,
  current_setting('database_test.order_id')::uuid,
  'outbound', current_setting('database_test.manager_id')::uuid,
  current_setting('database_test.manager_id')::uuid, 'failed', 2,
  'Fixture customer', '0900000001', 'Ba Dinh, Ha Noi',
  21.0333, 105.8333, 550000
);
INSERT INTO public.delivery_tasks
  (id, order_id, return_request_id, kind, assigned_shipper_id, assigned_by,
   status, attempt_number, destination_name, destination_phone,
   destination_address, destination_latitude, destination_longitude,
   amount_to_collect_vnd)
VALUES (
  current_setting('database_test.return_task_id')::uuid,
  current_setting('database_test.order_id')::uuid,
  current_setting('database_test.return_id')::uuid,
  'return_pickup', current_setting('database_test.shipper_id')::uuid,
  current_setting('database_test.manager_id')::uuid, 'assigned', 1,
  'Fixture customer', '0900000001', 'Ba Dinh, Ha Noi',
  21.0333, 105.8333, 0
);

INSERT INTO public.delivery_attempts
  (task_id, order_id, attempt_number, task_kind, result, reason, shipper_id)
VALUES (
  current_setting('database_test.task_id')::uuid,
  current_setting('database_test.order_id')::uuid, 1, 'outbound',
  'failed', 'No answer', current_setting('database_test.shipper_id')::uuid
);
INSERT INTO public.delivery_attempts
  (task_id, order_id, attempt_number, task_kind, result, reason, shipper_id)
VALUES (
  current_setting('database_test.other_task_id')::uuid,
  current_setting('database_test.other_order_id')::uuid, 2, 'outbound',
  'failed', 'Refused', current_setting('database_test.shipper_id')::uuid
);

INSERT INTO public.cod_collections
  (order_id, shipper_id, status, expected_amount_vnd,
   collected_amount_vnd, received_amount_vnd)
VALUES (
  current_setting('database_test.order_id')::uuid,
  current_setting('database_test.shipper_id')::uuid,
  'collected', 550000, 550000, 0
);

INSERT INTO public.business_events
  (id, actor_id, subject_type, subject_id, from_state, to_state, reason)
VALUES (
  current_setting('database_test.event_id')::uuid,
  current_setting('database_test.customer_id')::uuid,
  'order', current_setting('database_test.order_id')::uuid,
  'pending_confirmation', 'delivered', 'Database test fixture'
);
INSERT INTO public.business_events
  (id, actor_id, subject_type, subject_id, reason, task_id, incident_kind, request_id)
VALUES (
  current_setting('database_test.incident_event_id')::uuid,
  current_setting('database_test.shipper_id')::uuid,
  'delivery_task', current_setting('database_test.task_id')::uuid,
  'No answer', current_setting('database_test.task_id')::uuid,
  'other', current_setting('database_test.incident_request_id')::uuid
);
INSERT INTO public.business_events
  (id, actor_id, subject_type, subject_id, reason, task_id, incident_kind, request_id)
VALUES (
  'b0000000-0000-0000-0000-000000000003'::uuid,
  current_setting('database_test.other_shipper_id')::uuid,
  'delivery_task', current_setting('database_test.task_id')::uuid,
  'Other actor fixture', current_setting('database_test.task_id')::uuid,
  'other', 'd2000000-0000-0000-0000-000000000003'::uuid
);

INSERT INTO public.notifications
  (id, recipient_id, event_id, subject_type, subject_id, title, body)
VALUES (
  current_setting('database_test.notification_id')::uuid,
  current_setting('database_test.customer_id')::uuid,
  current_setting('database_test.event_id')::uuid,
  'order', current_setting('database_test.order_id')::uuid,
  'Database test', 'Fixture notification'
);
INSERT INTO public.notifications
  (id, recipient_id, event_id, subject_type, subject_id, title, body)
VALUES (
  current_setting('database_test.manager_notification_id')::uuid,
  current_setting('database_test.manager_id')::uuid,
  current_setting('database_test.incident_event_id')::uuid,
  'delivery_task', current_setting('database_test.task_id')::uuid,
  'Database test incident', 'Fixture incident'
);

INSERT INTO public.conversations (id, customer_id, read_at_by_user)
VALUES (
  current_setting('database_test.conversation_id')::uuid,
  current_setting('database_test.customer_id')::uuid,
  jsonb_build_object(current_setting('database_test.manager_id'), 'manager-original')
);
INSERT INTO public.conversations (id, customer_id)
VALUES (
  current_setting('database_test.other_conversation_id')::uuid,
  current_setting('database_test.other_customer_id')::uuid
);
INSERT INTO public.messages
  (id, conversation_id, sender_id, body, client_message_id)
VALUES (
  current_setting('database_test.message_id')::uuid,
  current_setting('database_test.conversation_id')::uuid,
  current_setting('database_test.manager_id')::uuid,
  'Fixture response', current_setting('database_test.message_client_id')::uuid
);
INSERT INTO public.messages
  (id, conversation_id, sender_id, body, client_message_id)
VALUES (
  current_setting('database_test.other_message_id')::uuid,
  current_setting('database_test.other_conversation_id')::uuid,
  current_setting('database_test.manager_id')::uuid,
  'Other fixture response', 'a2000000-0000-0000-0000-000000000002'::uuid
);

INSERT INTO public.store_settings (id, name, address, latitude, longitude)
VALUES (true, 'Sports Store', 'Ba Dinh, Ha Noi', 21.0333, 105.8333);

-- Storage metadata rows exercise object policies without writing blob bytes.
INSERT INTO storage.objects (bucket_id, name)
VALUES
  ('return-videos', '10000000-0000-0000-0000-000000000001/90000000-0000-0000-0000-000000000001/video.mp4'),
  ('return-videos', '10000000-0000-0000-0000-000000000001/90000000-0000-0000-0000-000000000001/additional.mp4'),
  ('return-videos', '10000000-0000-0000-0000-000000000001/unlinked.mp4'),
  ('return-videos', '10000000-0000-0000-0000-000000000002/other-customer.mp4'),
  ('inspection-evidence', '90000000-0000-0000-0000-000000000001/inspection.pdf'),
  ('inspection-evidence', '90000000-0000-0000-0000-000000000001/unlinked.pdf'),
  ('refund-evidence', '90000000-0000-0000-0000-000000000001/refund-evidence.pdf'),
  ('refund-evidence', '90000000-0000-0000-0000-000000000001/unlinked.pdf');

-- Anonymous has no public table rows or private Storage objects.
SET LOCAL ROLE anon;
SELECT pg_temp.clear_test_claims();
SELECT pg_temp.assert_raises('anon cannot read products', 'SELECT 1 FROM public.products', ARRAY['42501']);
SELECT pg_temp.assert_rows('anon sees no storage objects', 'SELECT 1 FROM storage.objects', 0);

-- Customer isolation, cart/notification/chat writes, and server-only domains.
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_test_claims(current_setting('database_test.customer_id')::uuid);
SELECT pg_temp.assert_rows('customer sees active product', 'SELECT id FROM public.products', 1);
SELECT pg_temp.assert_rows('customer sees active variant', 'SELECT id FROM public.product_variants', 1);
SELECT pg_temp.assert_rows('customer sees own cart item', 'SELECT variant_id FROM public.cart_items', 1);
SELECT pg_temp.assert_rows('customer sees own order only', 'SELECT id FROM public.orders', 1);
SELECT pg_temp.assert_rows('customer cannot see other order', format(
  'SELECT id FROM public.orders WHERE id = %L::uuid', current_setting('database_test.other_order_id')), 0);
SELECT pg_temp.assert_rows('customer sees own order item only', 'SELECT id FROM public.order_items', 1);
SELECT pg_temp.assert_rows('customer sees own return only', 'SELECT id FROM public.return_requests', 1);
SELECT pg_temp.assert_rows('customer cannot see other bank data',
  $$SELECT id FROM public.return_requests WHERE account_number = '0000000002'$$, 0);
SELECT pg_temp.assert_rows('customer sees own notification only', 'SELECT id FROM public.notifications', 1);
SELECT pg_temp.assert_rows('customer sees own conversation only', 'SELECT id FROM public.conversations', 1);
SELECT pg_temp.assert_rows('customer sees own messages only', 'SELECT id FROM public.messages', 1);
SELECT pg_temp.assert_exec_ok('customer may delete own cart item', format(
  'DELETE FROM public.cart_items WHERE customer_id = %L::uuid AND variant_id = %L::uuid',
  current_setting('database_test.customer_id'), current_setting('database_test.variant_id')));
SELECT pg_temp.assert_rows('customer cart is empty after own delete',
  'SELECT variant_id FROM public.cart_items', 0);
SELECT pg_temp.assert_exec_ok('customer may insert own cart item', format(
  'INSERT INTO public.cart_items (customer_id, variant_id, quantity) VALUES (%L::uuid, %L::uuid, 2)',
  current_setting('database_test.customer_id'), current_setting('database_test.variant_id')));
SELECT pg_temp.assert_exec_ok('customer may update own cart quantity', format(
  'UPDATE public.cart_items SET quantity = quantity WHERE customer_id = %L::uuid AND variant_id = %L::uuid',
  current_setting('database_test.customer_id'), current_setting('database_test.variant_id')));
SELECT pg_temp.assert_raises('customer cannot insert another customer cart item', format(
  'INSERT INTO public.cart_items (customer_id, variant_id, quantity) VALUES (%L::uuid, %L::uuid, 1)',
  current_setting('database_test.other_customer_id'), current_setting('database_test.variant_id')),
  ARRAY['42501']);
SELECT pg_temp.assert_exec_ok('customer may mark own notification read', format(
  'UPDATE public.notifications SET read_at = clock_timestamp() WHERE id = %L::uuid',
  current_setting('database_test.notification_id')));
SELECT pg_temp.assert_exec_ok('customer may send own chat message', format($sql$
  INSERT INTO public.messages (conversation_id, sender_id, body, client_message_id)
  VALUES (%L::uuid, %L::uuid, 'Fixture customer message', 'a2000000-0000-0000-0000-000000000003'::uuid)
  $sql$,
  current_setting('database_test.conversation_id'), current_setting('database_test.customer_id')));
SELECT pg_temp.assert_raises('duplicate message client key is rejected', format($sql$
  INSERT INTO public.messages (conversation_id, sender_id, body, client_message_id)
  VALUES (%L::uuid, %L::uuid, 'Duplicate', 'a2000000-0000-0000-0000-000000000003'::uuid)
  $sql$,
  current_setting('database_test.conversation_id'), current_setting('database_test.customer_id')),
  ARRAY['23505']);
SELECT pg_temp.assert_raises('customer cannot send to another conversation', format($sql$
  INSERT INTO public.messages (conversation_id, sender_id, body, client_message_id)
  VALUES (%L::uuid, %L::uuid, 'Forbidden', 'a2000000-0000-0000-0000-000000000004'::uuid)
  $sql$,
  current_setting('database_test.other_conversation_id'), current_setting('database_test.customer_id')),
  ARRAY['42501']);
SELECT set_config(
  'database_test.conversation_updated_at',
  (SELECT updated_at::text
   FROM public.conversations
   WHERE id = current_setting('database_test.conversation_id')::uuid),
  true
);
SELECT pg_temp.assert_exec_ok('customer read marker cannot forge manager marker', format($sql$
  UPDATE public.conversations
  SET read_at_by_user = jsonb_build_object(%L, 'forged')
  WHERE id = %L::uuid
  $sql$,
  current_setting('database_test.manager_id'), current_setting('database_test.conversation_id')));
SELECT pg_temp.assert_raises('customer cannot escalate profile role', format(
  'UPDATE public.profiles SET role = %L WHERE id = %L::uuid',
  'manager', current_setting('database_test.customer_id')), ARRAY['42501']);
SELECT pg_temp.assert_raises('customer cannot update order directly', format(
  'UPDATE public.orders SET status = status WHERE id = %L::uuid',
  current_setting('database_test.order_id')), ARRAY['42501']);
SELECT pg_temp.assert_raises('customer cannot update inventory directly', format(
  'UPDATE public.product_variants SET reserved = reserved WHERE id = %L::uuid',
  current_setting('database_test.variant_id')), ARRAY['42501']);
SELECT pg_temp.assert_raises('customer cannot update refund fields directly', format(
  'UPDATE public.return_requests SET refund_amount_vnd = refund_amount_vnd WHERE id = %L::uuid',
  current_setting('database_test.return_id')), ARRAY['42501']);
SELECT pg_temp.assert_raises('customer cannot upload product image',
  $$INSERT INTO storage.objects (bucket_id, name)
    VALUES ('product-images', 'customer/product.png')$$, ARRAY['42501']);

-- Customer Storage is scoped to the own return-video folder and linked own
-- inspection/refund paths. Unlinked and cross-customer objects stay hidden.
SELECT pg_temp.assert_exec_ok('customer may upload own return video', format($sql$
  INSERT INTO storage.objects (bucket_id, name)
  VALUES ('return-videos', %L)
  $sql$,
  current_setting('database_test.customer_id') || '/90000000-0000-0000-0000-000000000001/uploaded.mp4'));
SELECT pg_temp.assert_rows('customer reads own return videos', format($sql$
  SELECT name FROM storage.objects
  WHERE bucket_id = 'return-videos' AND name LIKE %L
  $sql$, current_setting('database_test.customer_id') || '/%'), 4);
SELECT pg_temp.assert_rows('customer cannot read cross-customer return videos', format($sql$
  SELECT name FROM storage.objects
  WHERE bucket_id = 'return-videos' AND name LIKE %L
  $sql$, current_setting('database_test.other_customer_id') || '/%'), 0);
SELECT pg_temp.assert_rows('customer reads linked inspection evidence', $sql$
  SELECT name FROM storage.objects
  WHERE bucket_id = 'inspection-evidence'
    AND name = '90000000-0000-0000-0000-000000000001/inspection.pdf'
  $sql$, 1);
SELECT pg_temp.assert_rows('customer cannot read unlinked inspection evidence', $sql$
  SELECT name FROM storage.objects
  WHERE bucket_id = 'inspection-evidence'
    AND name = '90000000-0000-0000-0000-000000000001/unlinked.pdf'
  $sql$, 0);
SELECT pg_temp.assert_rows('customer reads linked refund evidence', $sql$
  SELECT name FROM storage.objects
  WHERE bucket_id = 'refund-evidence'
    AND name = '90000000-0000-0000-0000-000000000001/refund-evidence.pdf'
  $sql$, 1);
SELECT pg_temp.assert_rows('customer cannot read unlinked refund evidence', $sql$
  SELECT name FROM storage.objects
  WHERE bucket_id = 'refund-evidence'
    AND name = '90000000-0000-0000-0000-000000000001/unlinked.pdf'
  $sql$, 0);

-- Server-side check of the read marker: the customer's update may add its own
-- timestamp but must preserve the manager marker that was already present.
RESET ROLE;
SELECT pg_temp.assert_rows('conversation read marker keeps manager and stamps customer', format($sql$
  SELECT id FROM public.conversations
  WHERE id = %L::uuid
    AND read_at_by_user ->> %L = 'manager-original'
    AND read_at_by_user ? %L
    AND read_at_by_user ->> %L <> 'forged'
    AND updated_at = current_setting('database_test.conversation_updated_at')::timestamptz
  $sql$,
  current_setting('database_test.conversation_id'),
  current_setting('database_test.manager_id'),
  current_setting('database_test.customer_id'),
  current_setting('database_test.customer_id')), 1);

-- Shippers see only their assigned delivery/return work, related order items,
-- COD and incident events; they cannot access chat, customer orders, or refund
-- and evidence fields.
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_test_claims(current_setting('database_test.shipper_id')::uuid);
SELECT pg_temp.assert_rows('shipper sees assigned tasks only',
  format('SELECT id FROM public.delivery_tasks WHERE assigned_shipper_id = %L::uuid',
    current_setting('database_test.shipper_id')), 2);
SELECT pg_temp.assert_rows('shipper cannot read orders', 'SELECT id FROM public.orders', 0);
SELECT pg_temp.assert_rows('shipper sees assigned order item', 'SELECT id FROM public.order_items', 1);
SELECT pg_temp.assert_rows('shipper sees assigned attempt', 'SELECT task_id FROM public.delivery_attempts', 1);
SELECT pg_temp.assert_rows('shipper sees own COD', 'SELECT order_id FROM public.cod_collections', 1);
SELECT pg_temp.assert_rows('shipper sees assigned return item', 'SELECT id FROM public.return_items', 1);
SELECT pg_temp.assert_rows('shipper sees assigned incident event',
  format($sql$
    SELECT id FROM public.business_events
    WHERE incident_kind IS NOT NULL
      AND actor_id = %L::uuid
  $sql$, current_setting('database_test.shipper_id')), 1);
SELECT pg_temp.assert_rows('assigned shipper sees the assigned task incident set',
  $$SELECT id FROM public.business_events WHERE incident_kind IS NOT NULL$$, 1);
SELECT pg_temp.assert_rows('shipper cannot read return request bank data',
  'SELECT id FROM public.return_requests', 0);
SELECT pg_temp.assert_rows('shipper cannot read conversations',
  'SELECT id FROM public.conversations', 0);
SELECT pg_temp.assert_rows('shipper cannot read messages',
  'SELECT id FROM public.messages', 0);
SELECT pg_temp.assert_rows('shipper cannot read return videos',
  $$SELECT name FROM storage.objects WHERE bucket_id = 'return-videos'$$, 0);
SELECT pg_temp.assert_rows('shipper cannot read inspection evidence',
  $$SELECT name FROM storage.objects WHERE bucket_id = 'inspection-evidence'$$, 0);
SELECT pg_temp.assert_rows('shipper cannot read refund evidence',
  $$SELECT name FROM storage.objects WHERE bucket_id = 'refund-evidence'$$, 0);
SELECT pg_temp.assert_rows('shipper may read store setting',
  'SELECT id FROM public.store_settings', 1);
SELECT pg_temp.assert_raises('shipper cannot update delivery task', format(
  'UPDATE public.delivery_tasks SET status = status WHERE id = %L::uuid',
  current_setting('database_test.task_id')), ARRAY['42501']);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_test_claims(current_setting('database_test.other_shipper_id')::uuid);
SELECT pg_temp.assert_rows('other shipper sees no unowned incident event',
  'SELECT id FROM public.business_events WHERE incident_kind IS NOT NULL', 0);
SELECT pg_temp.assert_rows('other shipper sees no assigned task',
  'SELECT id FROM public.delivery_tasks', 0);

-- Managers can review all rows and maintain catalog records. Order, stock,
-- delivery, COD, returns, event and notification state remains server-owned.
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_test_claims(current_setting('database_test.manager_id')::uuid);
SELECT pg_temp.assert_rows('manager sees all orders', 'SELECT id FROM public.orders', 2);
SELECT pg_temp.assert_rows('manager sees all tasks', 'SELECT id FROM public.delivery_tasks', 4);
SELECT pg_temp.assert_rows('manager sees all return requests', 'SELECT id FROM public.return_requests', 2);
SELECT pg_temp.assert_rows('manager sees COD', 'SELECT order_id FROM public.cod_collections', 1);
SELECT pg_temp.assert_rows('manager sees all business events', 'SELECT id FROM public.business_events', 3);
SELECT pg_temp.assert_rows('manager sees own notification', 'SELECT id FROM public.notifications', 1);
SELECT pg_temp.assert_rows('manager sees all conversations', 'SELECT id FROM public.conversations', 2);
SELECT pg_temp.assert_rows('manager sees all messages', 'SELECT id FROM public.messages', 3);
SELECT pg_temp.assert_exec_ok('manager may update product catalog', format(
  'UPDATE public.products SET name = name WHERE id = %L::uuid',
  current_setting('database_test.product_id')));
SELECT pg_temp.assert_exec_ok('manager may update variant catalog price', format(
  'UPDATE public.product_variants SET price_vnd = price_vnd WHERE id = %L::uuid',
  current_setting('database_test.variant_id')));
SELECT pg_temp.assert_raises('manager cannot mutate stock ledger directly',
  'INSERT INTO public.inventory_movements DEFAULT VALUES', ARRAY['42501']);
SELECT pg_temp.assert_raises('manager cannot update order directly', format(
  'UPDATE public.orders SET status = status WHERE id = %L::uuid',
  current_setting('database_test.order_id')), ARRAY['42501']);
SELECT pg_temp.assert_exec_ok('manager may upload product image',
  $$INSERT INTO storage.objects (bucket_id, name)
    VALUES ('product-images', 'manager/product.png')$$);
SELECT pg_temp.assert_rows('manager reads linked and unlinked inspection objects',
  $$SELECT name FROM storage.objects WHERE bucket_id = 'inspection-evidence'$$, 2);
SELECT pg_temp.assert_rows('manager reads linked and unlinked refund objects',
  $$SELECT name FROM storage.objects WHERE bucket_id = 'refund-evidence'$$, 2);
SELECT pg_temp.assert_rows('manager reads linked return videos only',
  $$SELECT name FROM storage.objects WHERE bucket_id = 'return-videos'$$, 2);

-- Final schema invariants and duplicate/idempotency keys are tested as the
-- server role so they are independent of client write grants.
RESET ROLE;
SELECT pg_temp.assert_rows('stock remains nonnegative and reserved <= on hand',
  'SELECT id FROM public.product_variants WHERE on_hand >= 0 AND reserved >= 0 AND reserved <= on_hand', 1);
SELECT pg_temp.assert_rows('delivery fee remains fixed at 30000 VND',
  'SELECT id FROM public.orders WHERE delivery_fee_vnd = 30000', 2);
SELECT pg_temp.assert_rows('COD expected and collected amounts are complete', format($sql$
  SELECT c.order_id
  FROM public.cod_collections c
  JOIN public.orders o ON o.id = c.order_id
  WHERE c.expected_amount_vnd = o.total_cod_vnd
    AND c.status = 'collected'
    AND c.collected_amount_vnd = c.expected_amount_vnd
    AND c.received_amount_vnd = 0
    AND c.order_id = %L::uuid
  $sql$, current_setting('database_test.order_id')), 1);
SELECT pg_temp.assert_rows('non-outbound task collects no COD',
  format('SELECT id FROM public.delivery_tasks WHERE kind <> %L AND amount_to_collect_vnd = 0', 'outbound'), 1);
SELECT pg_temp.assert_raises('duplicate order request key is rejected', format($sql$
  INSERT INTO public.orders
    (customer_id, request_id, status, recipient_name, recipient_phone,
     address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd)
  VALUES (%L::uuid, %L::uuid, 'pending_confirmation', 'Duplicate',
    '0900000099', 'Ba Dinh, Ha Noi', 21.0333, 105.8333, 520000, 30000)
  $sql$,
  current_setting('database_test.customer_id'), current_setting('database_test.order_request_id')),
  ARRAY['23505']);
SELECT pg_temp.assert_raises('third outbound attempt number is rejected', $sql$
  INSERT INTO public.delivery_tasks
    (id, order_id, kind, status, attempt_number, destination_name,
     destination_phone, destination_address, destination_latitude,
     destination_longitude, amount_to_collect_vnd)
  VALUES ('82000000-0000-0000-0000-000000000005'::uuid,
    '60000000-0000-0000-0000-000000000001'::uuid, 'outbound', 'failed', 3,
    'Fixture customer', '0900000001', 'Ba Dinh, Ha Noi', 21.0333, 105.8333, 550000)
  $sql$, ARRAY['23514']);
SELECT pg_temp.assert_raises('mismatched task and order attempt is rejected', format($sql$
  INSERT INTO public.delivery_attempts
    (task_id, order_id, attempt_number, task_kind, result, reason, shipper_id)
  VALUES (%L::uuid, %L::uuid, 1, 'outbound', 'failed', 'Mismatched order', %L::uuid)
  $sql$,
  current_setting('database_test.terminal_task_id'), current_setting('database_test.other_order_id'),
  current_setting('database_test.shipper_id')), ARRAY['23503']);
SELECT pg_temp.assert_exec_ok('seed first active return for uniqueness check', format($sql$
  INSERT INTO public.return_requests
    (id, order_id, customer_id, request_id, status, reason, description, video_object_path)
  VALUES ('90000000-0000-0000-0000-000000000003'::uuid, %L::uuid, %L::uuid,
    'd1000000-0000-0000-0000-000000000003'::uuid,
    'pending_review', 'defective', 'First active return',
    '10000000-0000-0000-0000-000000000001/first-active.mp4')
  $sql$,
  current_setting('database_test.order_id'), current_setting('database_test.customer_id')));
SELECT pg_temp.assert_raises('second active return is rejected', format($sql$
  INSERT INTO public.return_requests
    (order_id, customer_id, request_id, status, reason, description, video_object_path)
  VALUES (%L::uuid, %L::uuid, 'd1000000-0000-0000-0000-000000000004'::uuid,
    'pending_review', 'defective', 'Duplicate active return',
    '10000000-0000-0000-0000-000000000001/duplicate.mp4')
  $sql$,
  current_setting('database_test.order_id'), current_setting('database_test.customer_id')),
  ARRAY['23505']);
SELECT pg_temp.assert_raises('partial COD collection is rejected', format($sql$
  INSERT INTO public.cod_collections
    (order_id, status, expected_amount_vnd, collected_amount_vnd, received_amount_vnd)
  VALUES (%L::uuid, 'collected', 550000, 1, 0)
  $sql$, current_setting('database_test.other_order_id')), ARRAY['23514']);
SELECT pg_temp.assert_raises('non-outbound task with COD is rejected', format($sql$
  INSERT INTO public.delivery_tasks
    (id, order_id, return_request_id, kind, status, attempt_number,
     destination_name, destination_phone, destination_address,
     destination_latitude, destination_longitude, amount_to_collect_vnd)
  VALUES ('82000000-0000-0000-0000-000000000006'::uuid, %L::uuid, %L::uuid,
    'return_pickup', 'failed', 1, 'Fixture customer', '0900000001',
    'Ba Dinh, Ha Noi', 21.0333, 105.8333, 1)
  $sql$,
  current_setting('database_test.order_id'), current_setting('database_test.return_id')),
  ARRAY['23514']);
SELECT pg_temp.assert_raises('duplicate business request event is rejected', format($sql$
  INSERT INTO public.business_events
    (actor_id, subject_type, subject_id, reason, incident_kind, task_id, request_id)
  VALUES (%L::uuid, 'delivery_task', %L::uuid, 'Duplicate', 'other', %L::uuid, %L::uuid)
  $sql$,
  current_setting('database_test.shipper_id'), current_setting('database_test.task_id'),
  current_setting('database_test.task_id'), current_setting('database_test.incident_request_id')),
  ARRAY['23505']);

RESET ROLE;
SELECT 'database_security.sql: PASS' AS result,
       'fixtures rolled back by final statement' AS fixture_scope;

ROLLBACK;
