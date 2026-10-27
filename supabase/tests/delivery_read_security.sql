-- Delivery read projections must be the only shipper read path for delivery
-- work.  This fixture is deliberately independent from database_security.sql:
-- it exercises every projection scope and keeps all changes inside a rolled
-- back transaction.

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
  EXECUTE format('SELECT count(*) FROM (%s) AS delivery_security_rows', p_query)
    INTO l_actual;
  IF l_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'delivery read security test failed: % (expected %, got %)',
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
    RAISE EXCEPTION 'delivery read security test failed: % (%): %',
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
    RAISE EXCEPTION
      'delivery read security test failed: % (statement unexpectedly succeeded)',
      p_label;
  END IF;
  IF NOT l_state = ANY (p_allowed_states) THEN
    RAISE EXCEPTION
      'delivery read security test failed: % (unexpected SQLSTATE %): %',
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

-- Auth has gained nullable/defaulted columns over time.  Seed only the stable
-- columns and any required, default-less column, as the baseline security test
-- does, so this test remains usable across local Supabase Auth versions.
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
    RAISE EXCEPTION
      'delivery read security test cannot seed auth.users; unsupported required columns: %',
      array_to_string(l_required, ', ');
  END IF;

  EXECUTE format(
    'INSERT INTO auth.users (%s) VALUES (%s)',
    array_to_string(l_columns, ', '),
    array_to_string(l_values, ', ')
  ) USING p_user_id, p_email, p_user_metadata;
END;
$$;

-- Fixture identities and rows.  Customer A owns orders 1..13; customer B owns
-- order 14.  The old/new return-pickup pair (tasks 12/13) shares both order and
-- request to prove that a new assignment does not backfill old shipper access.
SELECT set_config('delivery_test.customer_a', '11000000-0000-0000-0000-000000000001', true);
SELECT set_config('delivery_test.customer_b', '11000000-0000-0000-0000-000000000002', true);
SELECT set_config('delivery_test.manager', '11000000-0000-0000-0000-000000000003', true);
SELECT set_config('delivery_test.shipper_a', '11000000-0000-0000-0000-000000000004', true);
SELECT set_config('delivery_test.shipper_b', '11000000-0000-0000-0000-000000000005', true);
SELECT set_config('delivery_test.category', '21000000-0000-0000-0000-000000000001', true);
SELECT set_config('delivery_test.product', '31000000-0000-0000-0000-000000000001', true);
SELECT set_config('delivery_test.variant', '41000000-0000-0000-0000-000000000001', true);

SELECT set_config('delivery_test.order_01', '61000000-0000-0000-0000-000000000001', true);
SELECT set_config('delivery_test.order_02', '61000000-0000-0000-0000-000000000002', true);
SELECT set_config('delivery_test.order_03', '61000000-0000-0000-0000-000000000003', true);
SELECT set_config('delivery_test.order_04', '61000000-0000-0000-0000-000000000004', true);
SELECT set_config('delivery_test.order_05', '61000000-0000-0000-0000-000000000005', true);
SELECT set_config('delivery_test.order_06', '61000000-0000-0000-0000-000000000006', true);
SELECT set_config('delivery_test.order_07', '61000000-0000-0000-0000-000000000007', true);
SELECT set_config('delivery_test.order_08', '61000000-0000-0000-0000-000000000008', true);
SELECT set_config('delivery_test.order_09', '61000000-0000-0000-0000-000000000009', true);
SELECT set_config('delivery_test.order_10', '61000000-0000-0000-0000-000000000010', true);
SELECT set_config('delivery_test.order_11', '61000000-0000-0000-0000-000000000011', true);
SELECT set_config('delivery_test.order_12', '61000000-0000-0000-0000-000000000012', true);
SELECT set_config('delivery_test.order_13', '61000000-0000-0000-0000-000000000013', true);
SELECT set_config('delivery_test.order_14', '61000000-0000-0000-0000-000000000014', true);

SELECT set_config('delivery_test.return_04', '91000000-0000-0000-0000-000000000004', true);
SELECT set_config('delivery_test.return_05', '91000000-0000-0000-0000-000000000005', true);
SELECT set_config('delivery_test.return_12', '91000000-0000-0000-0000-000000000012', true);

SELECT set_config('delivery_test.task_01', '81000000-0000-0000-0000-000000000001', true);
SELECT set_config('delivery_test.task_02', '81000000-0000-0000-0000-000000000002', true);
SELECT set_config('delivery_test.task_03', '81000000-0000-0000-0000-000000000003', true);
SELECT set_config('delivery_test.task_04', '81000000-0000-0000-0000-000000000004', true);
SELECT set_config('delivery_test.task_05', '81000000-0000-0000-0000-000000000005', true);
SELECT set_config('delivery_test.task_06', '81000000-0000-0000-0000-000000000006', true);
SELECT set_config('delivery_test.task_07', '81000000-0000-0000-0000-000000000007', true);
SELECT set_config('delivery_test.task_08', '81000000-0000-0000-0000-000000000008', true);
SELECT set_config('delivery_test.task_09', '81000000-0000-0000-0000-000000000009', true);
SELECT set_config('delivery_test.task_10', '81000000-0000-0000-0000-000000000010', true);
SELECT set_config('delivery_test.task_11', '81000000-0000-0000-0000-000000000011', true);
SELECT set_config('delivery_test.task_12', '81000000-0000-0000-0000-000000000012', true);
SELECT set_config('delivery_test.task_13', '81000000-0000-0000-0000-000000000013', true);
SELECT set_config('delivery_test.task_14', '81000000-0000-0000-0000-000000000014', true);
SELECT set_config('delivery_test.task_15', '81000000-0000-0000-0000-000000000015', true);

SELECT set_config('delivery_test.item_01', '71000000-0000-0000-0000-000000000001', true);
SELECT set_config('delivery_test.item_02', '71000000-0000-0000-0000-000000000002', true);
SELECT set_config('delivery_test.item_03', '71000000-0000-0000-0000-000000000003', true);
SELECT set_config('delivery_test.item_04', '71000000-0000-0000-0000-000000000004', true);
SELECT set_config('delivery_test.item_05', '71000000-0000-0000-0000-000000000005', true);
SELECT set_config('delivery_test.item_06', '71000000-0000-0000-0000-000000000006', true);
SELECT set_config('delivery_test.item_07', '71000000-0000-0000-0000-000000000007', true);
SELECT set_config('delivery_test.item_08', '71000000-0000-0000-0000-000000000008', true);
SELECT set_config('delivery_test.item_09', '71000000-0000-0000-0000-000000000009', true);
SELECT set_config('delivery_test.item_10', '71000000-0000-0000-0000-000000000010', true);
SELECT set_config('delivery_test.item_11', '71000000-0000-0000-0000-000000000011', true);
SELECT set_config('delivery_test.item_12', '71000000-0000-0000-0000-000000000012', true);
SELECT set_config('delivery_test.item_13', '71000000-0000-0000-0000-000000000013', true);
SELECT set_config('delivery_test.item_14', '71000000-0000-0000-0000-000000000014', true);

SELECT set_config('delivery_test.return_item_04', '92000000-0000-0000-0000-000000000004', true);
SELECT set_config('delivery_test.return_item_05', '92000000-0000-0000-0000-000000000005', true);
SELECT set_config('delivery_test.return_item_12', '92000000-0000-0000-0000-000000000012', true);

SELECT pg_temp.create_auth_user(
  current_setting('delivery_test.customer_a')::uuid,
  'delivery-security-customer-a@example.invalid',
  '{"role":"manager"}'::jsonb
);
SELECT pg_temp.create_auth_user(
  current_setting('delivery_test.customer_b')::uuid,
  'delivery-security-customer-b@example.invalid'
);
SELECT pg_temp.create_auth_user(
  current_setting('delivery_test.manager')::uuid,
  'delivery-security-manager@example.invalid'
);
SELECT pg_temp.create_auth_user(
  current_setting('delivery_test.shipper_a')::uuid,
  'delivery-security-shipper-a@example.invalid'
);
SELECT pg_temp.create_auth_user(
  current_setting('delivery_test.shipper_b')::uuid,
  'delivery-security-shipper-b@example.invalid'
);

UPDATE public.profiles
SET role = 'manager'
WHERE id = current_setting('delivery_test.manager')::uuid;
UPDATE public.profiles
SET role = 'shipper'
WHERE id IN (
  current_setting('delivery_test.shipper_a')::uuid,
  current_setting('delivery_test.shipper_b')::uuid
);

SELECT pg_temp.assert_rows(
  'editable metadata cannot provision manager role',
  format($sql$
    SELECT id FROM public.profiles
    WHERE id = %L::uuid AND role::text = 'customer'
  $sql$, current_setting('delivery_test.customer_a')),
  1
);

INSERT INTO public.categories (id, code, name, is_active)
VALUES (
  current_setting('delivery_test.category')::uuid,
  'delivery-security',
  'Delivery security fixtures',
  true
);

INSERT INTO public.products (id, category_id, name, description, is_active)
VALUES (
  current_setting('delivery_test.product')::uuid,
  current_setting('delivery_test.category')::uuid,
  'Delivery security ball',
  'Projection fixture',
  true
);

INSERT INTO public.product_variants
  (id, product_id, sku, label, attributes, price_vnd, is_active,
   on_hand, reserved, damaged)
VALUES (
  current_setting('delivery_test.variant')::uuid,
  current_setting('delivery_test.product')::uuid,
  'DELIVERY-SECURITY-001',
  'Fixture size',
  '{"size":"M","color":"blue"}'::jsonb,
  520000,
  true,
  100,
  0,
  0
);

-- All customer-A orders use the same product variant.  Keeping one snapshot
-- item per order makes accidental cross-order joins observable in the item
-- projection while preserving the schema's order/variant uniqueness constraint.
INSERT INTO public.orders
  (id, customer_id, request_id, status, recipient_name, recipient_phone,
   address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd)
SELECT
  ('61000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  current_setting('delivery_test.customer_a')::uuid,
  ('a3000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'delivered',
  format('Customer A %s', n),
  format('09000000%02s', n),
  format('Fixture address %s, Ha Noi', n),
  21.030000 + n / 100000.0,
  105.800000 + n / 100000.0,
  520000,
  30000
FROM generate_series(1, 13) AS numbers(n);

INSERT INTO public.orders
  (id, customer_id, request_id, status, recipient_name, recipient_phone,
   address_detail, latitude, longitude, subtotal_vnd, delivery_fee_vnd)
VALUES (
  current_setting('delivery_test.order_14')::uuid,
  current_setting('delivery_test.customer_b')::uuid,
  'a3000000-0000-0000-0000-000000000014'::uuid,
  'delivered',
  'Customer B 14',
  '0900000014',
  'Fixture address 14, Ha Noi',
  21.044000,
  105.814000,
  520000,
  30000
);

INSERT INTO public.order_items
  (id, order_id, product_id, variant_id, product_name, variant_label,
   attributes, unit_price_vnd, quantity)
SELECT
  ('71000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('61000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  current_setting('delivery_test.product')::uuid,
  current_setting('delivery_test.variant')::uuid,
  format('Ball snapshot %s', n),
  format('Fixture variant %s', n),
  jsonb_build_object('order_number', n, 'fixture', true),
  520000,
  1
FROM generate_series(1, 13) AS numbers(n);

INSERT INTO public.order_items
  (id, order_id, product_id, variant_id, product_name, variant_label,
   attributes, unit_price_vnd, quantity)
VALUES (
  current_setting('delivery_test.item_14')::uuid,
  current_setting('delivery_test.order_14')::uuid,
  current_setting('delivery_test.product')::uuid,
  current_setting('delivery_test.variant')::uuid,
  'Ball snapshot 14',
  'Fixture variant 14',
  '{"order_number":14,"fixture":true}'::jsonb,
  520000,
  1
);

INSERT INTO public.return_requests
  (id, order_id, customer_id, request_id, status, reason, description,
   video_object_path)
VALUES
  (
    current_setting('delivery_test.return_04')::uuid,
    current_setting('delivery_test.order_04')::uuid,
    current_setting('delivery_test.customer_a')::uuid,
    'a4000000-0000-0000-0000-000000000004'::uuid,
    'awaiting_return_pickup',
    'defective',
    'Pickup projection fixture',
    'delivery-security/return-04/video.mp4'
  ),
  (
    current_setting('delivery_test.return_05')::uuid,
    current_setting('delivery_test.order_05')::uuid,
    current_setting('delivery_test.customer_a')::uuid,
    'a4000000-0000-0000-0000-000000000005'::uuid,
    'awaiting_redelivery',
    'wrong_item',
    'Redelivery projection fixture',
    'delivery-security/return-05/video.mp4'
  ),
  (
    current_setting('delivery_test.return_12')::uuid,
    current_setting('delivery_test.order_12')::uuid,
    current_setting('delivery_test.customer_a')::uuid,
    'a4000000-0000-0000-0000-000000000012'::uuid,
    'awaiting_return_pickup',
    'missing_items',
    'Assignment history fixture',
    'delivery-security/return-12/video.mp4'
  );

INSERT INTO public.return_items
  (id, return_request_id, order_id, order_item_id, actual_item_name,
   variant_id, quantity_to_collect, quantity_collected)
VALUES
  (
    current_setting('delivery_test.return_item_04')::uuid,
    current_setting('delivery_test.return_04')::uuid,
    current_setting('delivery_test.order_04')::uuid,
    current_setting('delivery_test.item_04')::uuid,
    'Ball to collect 04',
    current_setting('delivery_test.variant')::uuid,
    1,
    1
  ),
  (
    current_setting('delivery_test.return_item_05')::uuid,
    current_setting('delivery_test.return_05')::uuid,
    current_setting('delivery_test.order_05')::uuid,
    current_setting('delivery_test.item_05')::uuid,
    'Ball to redeliver 05',
    current_setting('delivery_test.variant')::uuid,
    1,
    0
  ),
  (
    current_setting('delivery_test.return_item_12')::uuid,
    current_setting('delivery_test.return_12')::uuid,
    current_setting('delivery_test.order_12')::uuid,
    current_setting('delivery_test.item_12')::uuid,
    'Ball to collect 12',
    current_setting('delivery_test.variant')::uuid,
    1,
    0
  );

-- One COD row verifies that the projection change leaves the existing COD
-- policy independent and still usable by the assigned shipper.
INSERT INTO public.cod_collections
  (order_id, shipper_id, status, expected_amount_vnd,
   collected_amount_vnd, received_amount_vnd)
VALUES (
  current_setting('delivery_test.order_01')::uuid,
  current_setting('delivery_test.shipper_a')::uuid,
  'collected',
  550000,
  550000,
  0
);

-- Tasks 1..5 are current; 6..8 are restricted; 9..12 are history.  Task 12
-- is an old task assigned to shipper A, while task 13 is a new task for the
-- same order/request assigned to shipper B. Task 14 is reassigned in-place,
-- and task 15 belongs solely to customer/shipper B.
INSERT INTO public.delivery_tasks
  (id, order_id, return_request_id, kind, assigned_shipper_id, assigned_by,
   status, attempt_number, destination_name, destination_phone,
   destination_address, destination_latitude, destination_longitude,
   amount_to_collect_vnd, assigned_at, accepted_at, started_at, completed_at)
VALUES
  (
    current_setting('delivery_test.task_01')::uuid,
    current_setting('delivery_test.order_01')::uuid,
    NULL,
    'outbound',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'assigned',
    1,
    'Current assigned 01', '0900000101', 'Address 01, Ha Noi',
    21.031000, 105.801000, 550000,
    clock_timestamp() - interval '15 minutes', NULL, NULL, NULL
  ),
  (
    current_setting('delivery_test.task_02')::uuid,
    current_setting('delivery_test.order_02')::uuid,
    NULL,
    'outbound',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'accepted',
    1,
    'Current accepted 02', '0900000102', 'Address 02, Ha Noi',
    21.032000, 105.802000, 550000,
    clock_timestamp() - interval '20 minutes',
    clock_timestamp() - interval '10 minutes', NULL, NULL
  ),
  (
    current_setting('delivery_test.task_03')::uuid,
    current_setting('delivery_test.order_03')::uuid,
    NULL,
    'outbound',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'in_transit',
    1,
    'Current transit 03', '0900000103', 'Address 03, Ha Noi',
    21.033000, 105.803000, 550000,
    clock_timestamp() - interval '30 minutes',
    clock_timestamp() - interval '25 minutes',
    clock_timestamp() - interval '5 minutes', NULL
  ),
  (
    current_setting('delivery_test.task_04')::uuid,
    current_setting('delivery_test.order_04')::uuid,
    current_setting('delivery_test.return_04')::uuid,
    'return_pickup',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'in_transit',
    1,
    'Current pickup 04', '0900000104', 'Address 04, Ha Noi',
    21.034000, 105.804000, 0,
    clock_timestamp() - interval '40 minutes',
    clock_timestamp() - interval '30 minutes',
    clock_timestamp() - interval '10 minutes', NULL
  ),
  (
    current_setting('delivery_test.task_05')::uuid,
    current_setting('delivery_test.order_05')::uuid,
    current_setting('delivery_test.return_05')::uuid,
    'redelivery',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'accepted',
    1,
    'Current redelivery 05', '0900000105', 'Address 05, Ha Noi',
    21.035000, 105.805000, 0,
    clock_timestamp() - interval '50 minutes',
    clock_timestamp() - interval '20 minutes', NULL, NULL
  ),
  (
    current_setting('delivery_test.task_06')::uuid,
    current_setting('delivery_test.order_06')::uuid,
    NULL,
    'outbound',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'pending_assignment',
    1,
    'Restricted pending 06', '0900000106', 'Address 06, Ha Noi',
    21.036000, 105.806000, 550000,
    clock_timestamp() - interval '60 minutes', NULL, NULL, NULL
  ),
  (
    current_setting('delivery_test.task_07')::uuid,
    current_setting('delivery_test.order_07')::uuid,
    NULL,
    'outbound',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'failed',
    1,
    'Restricted failed 07', '0900000107', 'Address 07, Ha Noi',
    21.037000, 105.807000, 550000,
    clock_timestamp() - interval '70 minutes', NULL, NULL,
    clock_timestamp() - interval '5 minutes'
  ),
  (
    current_setting('delivery_test.task_08')::uuid,
    current_setting('delivery_test.order_08')::uuid,
    NULL,
    'outbound',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'manager_action_required',
    2,
    'Restricted manager action 08', '0900000108', 'Address 08, Ha Noi',
    21.038000, 105.808000, 550000,
    clock_timestamp() - interval '80 minutes',
    clock_timestamp() - interval '70 minutes',
    clock_timestamp() - interval '60 minutes', NULL
  ),
  (
    current_setting('delivery_test.task_09')::uuid,
    current_setting('delivery_test.order_09')::uuid,
    NULL,
    'outbound',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'delivered',
    1,
    'History delivered 09', '0900000109', 'Address 09, Ha Noi',
    21.039000, 105.809000, 550000,
    clock_timestamp() - interval '100 minutes',
    clock_timestamp() - interval '90 minutes',
    clock_timestamp() - interval '85 minutes',
    clock_timestamp() - interval '80 minutes'
  ),
  (
    current_setting('delivery_test.task_10')::uuid,
    current_setting('delivery_test.order_10')::uuid,
    NULL,
    'outbound',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'cancelled',
    1,
    'History cancelled 10', '0900000110', 'Address 10, Ha Noi',
    21.040000, 105.810000, 550000,
    clock_timestamp() - interval '110 minutes',
    NULL, NULL,
    clock_timestamp() - interval '105 minutes'
  ),
  (
    current_setting('delivery_test.task_11')::uuid,
    current_setting('delivery_test.order_11')::uuid,
    NULL,
    'outbound',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'returned_to_store',
    2,
    'History returned 11', '0900000111', 'Address 11, Ha Noi',
    21.041000, 105.811000, 550000,
    clock_timestamp() - interval '120 minutes',
    clock_timestamp() - interval '115 minutes',
    clock_timestamp() - interval '110 minutes',
    clock_timestamp() - interval '100 minutes'
  ),
  (
    current_setting('delivery_test.task_12')::uuid,
    current_setting('delivery_test.order_12')::uuid,
    current_setting('delivery_test.return_12')::uuid,
    'return_pickup',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'delivered',
    1,
    'Old pickup history 12', '0900000112', 'Address 12, Ha Noi',
    21.042000, 105.812000, 0,
    clock_timestamp() - interval '140 minutes',
    clock_timestamp() - interval '130 minutes',
    clock_timestamp() - interval '125 minutes',
    clock_timestamp() - interval '120 minutes'
  ),
  (
    current_setting('delivery_test.task_13')::uuid,
    current_setting('delivery_test.order_12')::uuid,
    current_setting('delivery_test.return_12')::uuid,
    'return_pickup',
    current_setting('delivery_test.shipper_b')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'assigned',
    1,
    'New pickup current 12', '0900000112', 'Address 12, Ha Noi',
    21.042000, 105.812000, 0,
    clock_timestamp() - interval '15 minutes',
    NULL, NULL, NULL
  ),
  (
    current_setting('delivery_test.task_14')::uuid,
    current_setting('delivery_test.order_13')::uuid,
    NULL,
    'outbound',
    current_setting('delivery_test.shipper_a')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'assigned',
    1,
    'Reassigned same task 13', '0900000113', 'Address 13, Ha Noi',
    21.043000, 105.813000, 550000,
    clock_timestamp() - interval '10 minutes',
    NULL, NULL, NULL
  ),
  (
    current_setting('delivery_test.task_15')::uuid,
    current_setting('delivery_test.order_14')::uuid,
    NULL,
    'outbound',
    current_setting('delivery_test.shipper_b')::uuid,
    current_setting('delivery_test.manager')::uuid,
    'assigned',
    1,
    'Other customer task 14', '0900000114', 'Address 14, Ha Noi',
    21.044000, 105.814000, 550000,
    clock_timestamp() - interval '10 minutes',
    NULL, NULL, NULL
  );

INSERT INTO public.delivery_attempts
  (task_id, order_id, attempt_number, task_kind, result, reason, shipper_id)
VALUES (
  current_setting('delivery_test.task_07')::uuid,
  current_setting('delivery_test.order_07')::uuid,
  1,
  'outbound',
  'failed',
  'Fixture failed attempt',
  current_setting('delivery_test.shipper_a')::uuid
);

-- No delivery projection may use the old generic history policy to leak an
-- incident.  This row remains manager-visible only after the migration.
INSERT INTO public.business_events
  (id, actor_id, subject_type, subject_id, reason, task_id, incident_kind, request_id)
VALUES (
  'b4000000-0000-0000-0000-000000000001'::uuid,
  current_setting('delivery_test.shipper_a')::uuid,
  'delivery_task',
  current_setting('delivery_test.task_07')::uuid,
  'Fixture incident',
  current_setting('delivery_test.task_07')::uuid,
  'other',
  'b5000000-0000-0000-0000-000000000001'::uuid
);

-- Anonymous callers do not have execute on either projection.
SET LOCAL ROLE anon;
SELECT pg_temp.clear_test_claims();
SELECT pg_temp.assert_raises(
  'anonymous cannot call task projection',
  'SELECT count(*) FROM public.read_my_delivery_tasks()',
  ARRAY['42501']
);
SELECT pg_temp.assert_raises(
  'anonymous cannot call item projection',
  format(
    'SELECT count(*) FROM public.read_my_delivery_task_items(%L::uuid)',
    current_setting('delivery_test.task_01')
  ),
  ARRAY['42501']
);

SELECT pg_temp.assert_rows(
  'task function grants authenticated only',
  $$
    SELECT 1
    FROM pg_proc AS p
    WHERE p.oid = 'public.read_my_delivery_tasks(uuid)'::regprocedure
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
      AND NOT EXISTS (
        SELECT 1
        FROM aclexplode(
          coalesce(p.proacl, acldefault('f', p.proowner))
        ) AS acl
        WHERE acl.grantee = 0
          AND acl.privilege_type = 'EXECUTE'
      )
  $$,
  1
);
SELECT pg_temp.assert_rows(
  'item function grants authenticated only',
  $$
    SELECT 1
    FROM pg_proc AS p
    WHERE p.oid = 'public.read_my_delivery_task_items(uuid)'::regprocedure
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
      AND NOT EXISTS (
        SELECT 1
        FROM aclexplode(
          coalesce(p.proacl, acldefault('f', p.proowner))
        ) AS acl
        WHERE acl.grantee = 0
          AND acl.privilege_type = 'EXECUTE'
      )
  $$,
  1
);

-- Projection functions must own their access check and pin search_path.  The
-- caller must not get a definer function with an ambient path.
SELECT pg_temp.assert_rows(
  'task projection is a pinned security definer',
  $$
    SELECT 1
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.oid = 'public.read_my_delivery_tasks(uuid)'::regprocedure
      AND p.prosecdef
      AND EXISTS (
        SELECT 1
        FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) AS setting
        WHERE setting IN ('search_path=', 'search_path=""')
      )
  $$,
  1
);
SELECT pg_temp.assert_rows(
  'item projection is a pinned security definer',
  $$
    SELECT 1
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.oid = 'public.read_my_delivery_task_items(uuid)'::regprocedure
      AND p.prosecdef
      AND EXISTS (
        SELECT 1
        FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) AS setting
        WHERE setting IN ('search_path=', 'search_path=""')
      )
  $$,
  1
);

RESET ROLE;
SELECT pg_temp.assert_rows(
  'projection owner is the locked-down reader role',
  $$
    SELECT 1
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    JOIN pg_roles AS owner_role ON owner_role.oid = p.proowner
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'read_my_delivery_tasks',
        'read_my_delivery_task_items'
      )
      AND p.oid IN (
        'public.read_my_delivery_tasks(uuid)'::regprocedure,
        'public.read_my_delivery_task_items(uuid)'::regprocedure
      )
      AND owner_role.rolname = 'sports_store_delivery_reader'
      AND NOT owner_role.rolsuper
      AND NOT owner_role.rolcanlogin
      AND NOT owner_role.rolinherit
      AND NOT owner_role.rolbypassrls
      AND NOT owner_role.rolcreaterole
      AND NOT owner_role.rolcreatedb
      AND NOT owner_role.rolreplication
  $$,
  2
);
SELECT pg_temp.assert_rows(
  'API roles cannot assume projection owner',
  $$
    SELECT 1
    WHERE NOT EXISTS (
      SELECT 1
      FROM pg_auth_members AS membership
      JOIN pg_roles AS granted_role
        ON granted_role.oid = membership.roleid
      JOIN pg_roles AS member_role
        ON member_role.oid = membership.member
      WHERE granted_role.rolname = 'sports_store_delivery_reader'
        AND member_role.rolname IN ('anon', 'authenticated', 'service_role')
    )
  $$,
  1
);
SELECT pg_temp.assert_rows(
  'reader has only the projection column grants',
  $$
    SELECT 1
    WHERE (
      SELECT count(*)
      FROM information_schema.column_privileges AS grants
      WHERE grants.grantee = 'sports_store_delivery_reader'
        AND grants.table_schema = 'public'
    ) = 33
      AND NOT EXISTS (
        SELECT 1
        FROM information_schema.column_privileges AS grants
        WHERE grants.grantee = 'sports_store_delivery_reader'
          AND grants.table_schema = 'public'
          AND grants.table_name NOT IN (
            'profiles', 'delivery_tasks', 'order_items', 'return_items'
          )
      )
      AND NOT EXISTS (
        SELECT 1
        FROM information_schema.role_table_grants AS table_grants
        WHERE table_grants.grantee = 'sports_store_delivery_reader'
          AND table_grants.table_schema = 'public'
      )
  $$,
  1
);
SELECT pg_temp.assert_rows(
  'reader cannot read broad order return or COD tables',
  $$
    SELECT 1
    WHERE NOT has_table_privilege(
            'sports_store_delivery_reader', 'public.orders', 'SELECT'
          )
      AND NOT has_table_privilege(
            'sports_store_delivery_reader',
            'public.return_requests',
            'SELECT'
          )
      AND NOT has_table_privilege(
            'sports_store_delivery_reader',
            'public.cod_collections',
            'SELECT'
          )
      AND NOT has_table_privilege(
            'sports_store_delivery_reader',
            'public.delivery_tasks',
            'INSERT'
          )
      AND NOT has_table_privilege(
            'sports_store_delivery_reader',
            'public.delivery_tasks',
            'UPDATE'
          )
  $$,
  1
);
SELECT pg_temp.assert_rows(
  'reader schema grant is usage only after migration',
  $$
    SELECT 1
    WHERE has_schema_privilege(
            'sports_store_delivery_reader', 'public', 'USAGE'
          )
      AND NOT has_schema_privilege(
            'sports_store_delivery_reader', 'public', 'CREATE'
          )
  $$,
  1
);

-- A non-shipper authenticated user is authenticated but receives no delivery
-- rows.  A forged JWT role claim cannot change the server profile role.
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_test_claims(
  current_setting('delivery_test.customer_a')::uuid,
  'manager'
);
SELECT pg_temp.assert_rows(
  'customer with forged manager claim gets no task projection',
  'SELECT task_id FROM public.read_my_delivery_tasks()',
  0
);
SELECT pg_temp.assert_rows(
  'customer with forged manager claim gets no item projection',
  format(
    'SELECT item_id FROM public.read_my_delivery_task_items(%L::uuid)',
    current_setting('delivery_test.task_01')
  ),
  0
);

SELECT pg_temp.set_test_claims(current_setting('delivery_test.manager')::uuid);
SELECT pg_temp.assert_rows(
  'manager receives no shipper task projection',
  'SELECT task_id FROM public.read_my_delivery_tasks()',
  0
);

-- Shipper A receives all and only its currently assigned task rows.  The
-- projection retains the task ID and status for restricted/history rows, but
-- only current rows retain operational PII and order/request/amount fields.
SELECT pg_temp.set_test_claims(current_setting('delivery_test.shipper_a')::uuid);
SELECT pg_temp.assert_rows(
  'shipper A sees only assigned task rows',
  'SELECT task_id FROM public.read_my_delivery_tasks()',
  13
);
SELECT pg_temp.assert_rows(
  'shipper A sees all current and restricted/history statuses',
  $$
    SELECT task_id
    FROM public.read_my_delivery_tasks()
    WHERE status IN (
      'assigned', 'accepted', 'in_transit', 'pending_assignment', 'failed',
      'manager_action_required', 'delivered', 'cancelled', 'returned_to_store'
    )
  $$,
  13
);
SELECT pg_temp.assert_rows(
  'current task scopes include all operational fields',
  $$
    SELECT task_id
    FROM public.read_my_delivery_tasks()
    WHERE snapshot_scope = 'current'
      AND order_id IS NOT NULL
      AND amount_to_collect_vnd IS NOT NULL
      AND destination_name IS NOT NULL
      AND destination_phone IS NOT NULL
      AND destination_address IS NOT NULL
      AND destination_latitude IS NOT NULL
      AND destination_longitude IS NOT NULL
      AND assigned_at IS NOT NULL
      AND completed_at IS NULL
  $$,
  6
);
SELECT pg_temp.assert_rows(
  'restricted/history scopes hide operational fields',
  $$
    SELECT task_id
    FROM public.read_my_delivery_tasks()
    WHERE snapshot_scope IN ('restricted', 'history')
      AND order_id IS NULL
      AND return_request_id IS NULL
      AND amount_to_collect_vnd IS NULL
      AND destination_name IS NULL
      AND destination_phone IS NULL
      AND destination_address IS NULL
      AND destination_latitude IS NULL
      AND destination_longitude IS NULL
      AND assigned_at IS NULL
      AND accepted_at IS NULL
      AND started_at IS NULL
      AND item_source = 'unavailable'
  $$,
  7
);
SELECT pg_temp.assert_rows(
  'completed_at remains visible on terminal history rows',
  $$
    SELECT task_id
    FROM public.read_my_delivery_tasks()
    WHERE snapshot_scope = 'history'
      AND status IN ('delivered', 'cancelled', 'returned_to_store')
      AND completed_at IS NOT NULL
  $$,
  4
);
SELECT pg_temp.assert_rows(
  'active outbound uses order snapshot source',
  $$
    SELECT task_id
    FROM public.read_my_delivery_tasks()
    WHERE snapshot_scope = 'current'
      AND kind = 'outbound'
      AND item_source = 'order_snapshot'
  $$,
  4
);
SELECT pg_temp.assert_rows(
  'active pickup uses return plan source',
  $$
    SELECT task_id
    FROM public.read_my_delivery_tasks()
    WHERE task_id = current_setting('delivery_test.task_04')::uuid
      AND snapshot_scope = 'current'
      AND kind = 'return_pickup'
      AND item_source = 'return_plan'
  $$,
  1
);
SELECT pg_temp.assert_rows(
  'active redelivery has no guessed item source',
  $$
    SELECT task_id
    FROM public.read_my_delivery_tasks()
    WHERE task_id = current_setting('delivery_test.task_05')::uuid
      AND snapshot_scope = 'current'
      AND kind = 'redelivery'
      AND item_source = 'unavailable_redelivery_plan'
  $$,
  1
);

-- A deep link to a task owned by B cannot be used by A, including when the
-- caller supplies the exact UUID.  NULL and explicit task filters agree.
SELECT pg_temp.assert_rows(
  'shipper A cannot deep-link to shipper B task',
  format(
    'SELECT task_id FROM public.read_my_delivery_tasks(%L::uuid)',
    current_setting('delivery_test.task_15')
  ),
  0
);
SELECT pg_temp.assert_rows(
  'shipper A cannot deep-link to shipper B items',
  format(
    'SELECT item_id FROM public.read_my_delivery_task_items(%L::uuid)',
    current_setting('delivery_test.task_15')
  ),
  0
);

-- Items are scoped to the exact current task.  Outbound items come from the
-- task's order; pickup items come from its request; redelivery and non-current
-- rows remain empty until an approved plan exists.
SELECT pg_temp.assert_rows(
  'shipper A sees exact outbound item only',
  format(
    $sql$
      SELECT item_id
      FROM public.read_my_delivery_task_items(%L::uuid)
      WHERE item_id = %L::uuid
        AND item_source = 'order_snapshot'
        AND product_name = 'Ball snapshot 1'
        AND quantity = 1
        AND quantity_collected IS NULL
        AND unit_price_vnd = 520000
        AND line_total_vnd = 520000
    $sql$,
    current_setting('delivery_test.task_01'),
    current_setting('delivery_test.item_01')
  ),
  1
);
SELECT pg_temp.assert_rows(
  'shipper A sees exact pickup plan item only',
  format(
    $sql$
      SELECT item_id
      FROM public.read_my_delivery_task_items(%L::uuid)
      WHERE item_id = %L::uuid
        AND item_source = 'return_plan'
        AND quantity = 1
        AND quantity_collected = 1
    $sql$,
    current_setting('delivery_test.task_04'),
    current_setting('delivery_test.return_item_04')
  ),
  1
);
SELECT pg_temp.assert_rows(
  'redelivery has no guessed order or return items',
  format(
    'SELECT item_id FROM public.read_my_delivery_task_items(%L::uuid)',
    current_setting('delivery_test.task_05')
  ),
  0
);
SELECT pg_temp.assert_rows(
  'restricted task has no item projection',
  format(
    'SELECT item_id FROM public.read_my_delivery_task_items(%L::uuid)',
    current_setting('delivery_test.task_07')
  ),
  0
);
SELECT pg_temp.assert_rows(
  'terminal task has no item projection',
  format(
    'SELECT item_id FROM public.read_my_delivery_task_items(%L::uuid)',
    current_setting('delivery_test.task_09')
  ),
  0
);

-- Base table policies no longer provide delivery data to shippers.  COD is an
-- intentionally unchanged exception; its existing policy still exposes only
-- the shipper's own obligation.
SELECT pg_temp.assert_rows(
  'shipper cannot read base delivery tasks',
  'SELECT id FROM public.delivery_tasks',
  0
);
SELECT pg_temp.assert_rows(
  'shipper cannot read base orders',
  'SELECT id FROM public.orders',
  0
);
SELECT pg_temp.assert_rows(
  'shipper cannot read return request bank/quality data',
  'SELECT id FROM public.return_requests',
  0
);
SELECT pg_temp.assert_rows(
  'shipper cannot read base order items',
  'SELECT id FROM public.order_items',
  0
);
SELECT pg_temp.assert_rows(
  'shipper cannot read base return items',
  'SELECT id FROM public.return_items',
  0
);
SELECT pg_temp.assert_rows(
  'shipper cannot read base delivery attempts',
  'SELECT id FROM public.delivery_attempts',
  0
);
SELECT pg_temp.assert_rows(
  'shipper cannot read incident history',
  'SELECT id FROM public.business_events WHERE incident_kind IS NOT NULL',
  0
);
SELECT pg_temp.assert_rows(
  'COD policy remains shipper scoped',
  'SELECT order_id FROM public.cod_collections',
  1
);
SELECT pg_temp.assert_raises(
  'shipper cannot write delivery task directly',
  format(
    'UPDATE public.delivery_tasks SET status = status WHERE id = %L::uuid',
    current_setting('delivery_test.task_01')
  ),
  ARRAY['42501']
);
SELECT pg_temp.assert_raises(
  'shipper cannot write order item directly',
  format(
    'UPDATE public.order_items SET quantity = quantity WHERE id = %L::uuid',
    current_setting('delivery_test.item_01')
  ),
  ARRAY['42501']
);
SELECT pg_temp.assert_raises(
  'shipper cannot write return item directly',
  format(
    'UPDATE public.return_items SET quantity_collected = quantity_collected
     WHERE id = %L::uuid',
    current_setting('delivery_test.return_item_04')
  ),
  ARRAY['42501']
);
SELECT pg_temp.assert_raises(
  'shipper cannot write delivery attempt directly',
  format(
    'UPDATE public.delivery_attempts SET reason = reason WHERE task_id = %L::uuid',
    current_setting('delivery_test.task_07')
  ),
  ARRAY['42501']
);

-- Shipper A still sees the old historical task after B receives a new task for
-- the same order/request, but gets no PII or item history from it. B sees only
-- the new current task and its exact return plan.
SELECT pg_temp.assert_rows(
  'old shipper retains minimal historical row',
  format(
    $sql$
      SELECT task_id
      FROM public.read_my_delivery_tasks(%L::uuid)
      WHERE task_id = %L::uuid
        AND snapshot_scope = 'history'
        AND status = 'delivered'
        AND order_id IS NULL
        AND return_request_id IS NULL
        AND item_source = 'unavailable'
    $sql$,
    current_setting('delivery_test.task_12'),
    current_setting('delivery_test.task_12')
  ),
  1
);
SELECT pg_temp.assert_rows(
  'old shipper cannot backfill new task items',
  format(
    'SELECT item_id FROM public.read_my_delivery_task_items(%L::uuid)',
    current_setting('delivery_test.task_12')
  ),
  0
);

SELECT pg_temp.set_test_claims(current_setting('delivery_test.shipper_b')::uuid);
SELECT pg_temp.assert_rows(
  'new shipper sees only its assigned rows',
  'SELECT task_id FROM public.read_my_delivery_tasks()',
  2
);
SELECT pg_temp.assert_rows(
  'new shipper sees exact new return task item',
  format(
    $sql$
      SELECT item_id
      FROM public.read_my_delivery_task_items(%L::uuid)
      WHERE item_id = %L::uuid
        AND item_source = 'return_plan'
    $sql$,
    current_setting('delivery_test.task_13'),
    current_setting('delivery_test.return_item_12')
  ),
  1
);
SELECT pg_temp.assert_rows(
  'new shipper cannot read old task items',
  format(
    'SELECT item_id FROM public.read_my_delivery_task_items(%L::uuid)',
    current_setting('delivery_test.task_12')
  ),
  0
);

-- Reassigning the same task revokes the old shipper immediately. There is no
-- assignment-history table from which to backfill the old assignment.
RESET ROLE;
UPDATE public.delivery_tasks
SET assigned_shipper_id = current_setting('delivery_test.shipper_b')::uuid,
    assigned_at = clock_timestamp()
WHERE id = current_setting('delivery_test.task_14')::uuid;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_test_claims(current_setting('delivery_test.shipper_a')::uuid);
SELECT pg_temp.assert_rows(
  'reassignment revokes old shipper task row',
  format(
    'SELECT task_id FROM public.read_my_delivery_tasks(%L::uuid)',
    current_setting('delivery_test.task_14')
  ),
  0
);
SELECT pg_temp.assert_rows(
  'reassignment revokes old shipper items',
  format(
    'SELECT item_id FROM public.read_my_delivery_task_items(%L::uuid)',
    current_setting('delivery_test.task_14')
  ),
  0
);
SELECT pg_temp.set_test_claims(current_setting('delivery_test.shipper_b')::uuid);
SELECT pg_temp.assert_rows(
  'reassigned task is visible only to new shipper',
  format(
    'SELECT task_id FROM public.read_my_delivery_tasks(%L::uuid)',
    current_setting('delivery_test.task_14')
  ),
  1
);

-- Managers retain their existing full table scopes and customers retain their
-- own order/return scopes.  Neither role gets shipper projection rows.
SELECT pg_temp.set_test_claims(current_setting('delivery_test.manager')::uuid);
SELECT pg_temp.assert_rows(
  'manager sees all delivery tasks through base policy',
  'SELECT id FROM public.delivery_tasks',
  15
);
SELECT pg_temp.assert_rows(
  'manager sees all order items through base policy',
  'SELECT id FROM public.order_items',
  14
);
SELECT pg_temp.assert_rows(
  'manager sees all return items through base policy',
  'SELECT id FROM public.return_items',
  3
);
SELECT pg_temp.assert_rows(
  'manager sees incident history',
  'SELECT id FROM public.business_events WHERE incident_kind IS NOT NULL',
  1
);
SELECT pg_temp.assert_rows(
  'manager still receives no shipper projection',
  'SELECT task_id FROM public.read_my_delivery_tasks()',
  0
);

SELECT pg_temp.set_test_claims(current_setting('delivery_test.customer_a')::uuid);
SELECT pg_temp.assert_rows(
  'customer A sees own orders only',
  'SELECT id FROM public.orders',
  13
);
SELECT pg_temp.assert_rows(
  'customer A sees own order items only',
  'SELECT id FROM public.order_items',
  13
);
SELECT pg_temp.assert_rows(
  'customer A sees own return items only',
  'SELECT id FROM public.return_items',
  3
);
SELECT pg_temp.assert_rows(
  'customer A sees no shipper projection',
  'SELECT task_id FROM public.read_my_delivery_tasks()',
  0
);
SELECT pg_temp.assert_rows(
  'customer A cannot read customer B order item',
  format(
    'SELECT id FROM public.order_items WHERE order_id = %L::uuid',
    current_setting('delivery_test.order_14')
  ),
  0
);
SELECT pg_temp.assert_rows(
  'customer A cannot deep-link to customer B task items',
  format(
    'SELECT item_id FROM public.read_my_delivery_task_items(%L::uuid)',
    current_setting('delivery_test.task_15')
  ),
  0
);

-- Reset to the privileged test role before checking rollback and printing only
-- a non-PII result.  All fixture rows and temporary helpers disappear at the
-- final ROLLBACK.
RESET ROLE;
SELECT 'delivery_read_security.sql: PASS' AS result,
       'fixtures rolled back by final statement' AS fixture_scope;

ROLLBACK;
