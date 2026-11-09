-- Expose the image already snapshotted on each order item. Do not rejoin the
-- live catalog: a catalog edit must never rewrite an existing order's image.
-- CREATE OR REPLACE retains the existing helper owner and execution ACL.
create or replace function private.orders_read_items(p_order_id uuid) returns jsonb
language sql stable security invoker set search_path = '' set timezone = 'UTC'
as $$ select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
 'id',i.id,'order_id',i.order_id,'product_id',i.product_id,'variant_id',i.variant_id,
 'product_name',i.product_name,'product_image_url',i.product_image_url,
 'variant_label',i.variant_label,'attributes',i.attributes,
 'unit_price_vnd',i.unit_price_vnd,'quantity',i.quantity,'line_total_vnd',i.line_total_vnd,
 'created_at',i.created_at) order by i.created_at,i.id),'[]'::jsonb)
 from public.order_items i where i.order_id=p_order_id $$;

-- Checkout placement, lookup and replay use a separate helper with a different
-- ordering/configuration and a postgres-only ACL. Preserve that contract too.
create or replace function private.checkout_items_json(p_order_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', i.id,
        'order_id', i.order_id,
        'product_id', i.product_id,
        'variant_id', i.variant_id,
        'product_name', i.product_name,
        'product_image_url', i.product_image_url,
        'variant_label', i.variant_label,
        'attributes', i.attributes,
        'unit_price_vnd', i.unit_price_vnd,
        'quantity', i.quantity,
        'line_total_vnd', i.line_total_vnd,
        'created_at', i.created_at
      ) order by i.variant_id
    ),
    '[]'::jsonb
  )
  from public.order_items as i
  where i.order_id = p_order_id
$$;
