-- Client privileges and RLS for the schema foundation.
-- Orders, inventory ledger, delivery, COD and returns are deliberately read-only
-- to clients. Transactional business RPCs will be implemented with their features.

create or replace function private.current_app_role()
returns text language sql stable security definer set search_path = ''
as $$
  select p.role::text from public.profiles p
  where p.id = (select auth.uid()) and (select auth.uid()) is not null;
$$;
revoke all on function private.current_app_role() from public, anon, authenticated, service_role;
grant usage on schema private to authenticated;
grant execute on function private.current_app_role() to authenticated;

-- Explicitly grant Data API access; RLS constrains rows for each app role.
grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;

create policy profiles_read on public.profiles for select to authenticated
using (id = (select auth.uid()) or (select private.current_app_role()) = 'manager');

create policy categories_read on public.categories for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or ((select private.current_app_role()) = 'customer' and is_active));

create policy products_read on public.products for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or ((select private.current_app_role()) = 'customer' and is_active));
create policy products_insert on public.products for insert to authenticated
with check ((select private.current_app_role()) = 'manager');
create policy products_update on public.products for update to authenticated
using ((select private.current_app_role()) = 'manager')
with check ((select private.current_app_role()) = 'manager');
grant insert (category_id, name, description, image_path, is_active)
  on public.products to authenticated;
grant update (category_id, name, description, image_path, is_active)
  on public.products to authenticated;

create policy variants_read on public.product_variants for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or ((select private.current_app_role()) = 'customer' and is_active and exists
    (select 1 from public.products p where p.id = product_id and p.is_active)));
create policy variants_insert on public.product_variants for insert to authenticated
with check ((select private.current_app_role()) = 'manager');
create policy variants_update on public.product_variants for update to authenticated
using ((select private.current_app_role()) = 'manager')
with check ((select private.current_app_role()) = 'manager');
grant insert (product_id, sku, label, attributes, price_vnd, is_active)
  on public.product_variants to authenticated;
grant update (sku, label, attributes, price_vnd, is_active)
  on public.product_variants to authenticated;

create policy inventory_balances_read on public.inventory_balances for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or ((select private.current_app_role()) = 'customer' and exists
    (select 1 from public.product_variants v where v.id = variant_id and v.is_active)));
create policy inventory_movements_read on public.inventory_movements for select to authenticated
using ((select private.current_app_role()) = 'manager');

create policy carts_read on public.carts for select to authenticated
using (customer_id = (select auth.uid()) and (select private.current_app_role()) = 'customer');
create policy carts_insert on public.carts for insert to authenticated
with check (customer_id = (select auth.uid()) and (select private.current_app_role()) = 'customer');
create policy carts_delete on public.carts for delete to authenticated
using (customer_id = (select auth.uid()) and (select private.current_app_role()) = 'customer');
grant insert (customer_id), delete on public.carts to authenticated;

create policy cart_items_read on public.cart_items for select to authenticated
using ((select private.current_app_role()) = 'customer' and exists
  (select 1 from public.carts c where c.id = cart_id and c.customer_id = (select auth.uid())));
create policy cart_items_insert on public.cart_items for insert to authenticated
with check ((select private.current_app_role()) = 'customer' and exists
  (select 1 from public.carts c where c.id = cart_id and c.customer_id = (select auth.uid()))
  and exists (select 1 from public.product_variants v where v.id = variant_id and v.is_active));
create policy cart_items_update on public.cart_items for update to authenticated
using ((select private.current_app_role()) = 'customer' and exists
  (select 1 from public.carts c where c.id = cart_id and c.customer_id = (select auth.uid())))
with check ((select private.current_app_role()) = 'customer' and exists
  (select 1 from public.carts c where c.id = cart_id and c.customer_id = (select auth.uid())));
create policy cart_items_delete on public.cart_items for delete to authenticated
using ((select private.current_app_role()) = 'customer' and exists
  (select 1 from public.carts c where c.id = cart_id and c.customer_id = (select auth.uid())));
grant insert (cart_id, variant_id, quantity), update (quantity), delete
  on public.cart_items to authenticated;

create policy orders_read on public.orders for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or ((select private.current_app_role()) = 'customer' and customer_id = (select auth.uid())));
create policy tasks_read on public.delivery_tasks for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or ((select private.current_app_role()) = 'shipper' and assigned_shipper_id = (select auth.uid())));
create policy order_items_read on public.order_items for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or exists (select 1 from public.orders o where o.id = order_id and o.customer_id = (select auth.uid()))
  or ((select private.current_app_role()) = 'shipper' and exists
    (select 1 from public.delivery_tasks t where t.order_id = order_items.order_id
      and t.assigned_shipper_id = (select auth.uid()))));
create policy attempts_read on public.delivery_attempts for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or exists (select 1 from public.orders o where o.id = order_id and o.customer_id = (select auth.uid()))
  or ((select private.current_app_role()) = 'shipper' and exists
    (select 1 from public.delivery_tasks t where t.id = task_id
      and t.assigned_shipper_id = (select auth.uid()))));
create policy incidents_read on public.delivery_incidents for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or ((select private.current_app_role()) = 'shipper' and exists
    (select 1 from public.delivery_tasks t where t.id = task_id
      and t.assigned_shipper_id = (select auth.uid()))));
create policy cod_read on public.cod_collections for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or ((select private.current_app_role()) = 'shipper' and shipper_id = (select auth.uid()))
  or exists (select 1 from public.orders o where o.id = order_id and o.customer_id = (select auth.uid())));

create policy returns_read on public.return_requests for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or ((select private.current_app_role()) = 'customer' and customer_id = (select auth.uid())));
create policy return_items_read on public.return_items for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or exists (select 1 from public.return_requests r where r.id = return_request_id
    and r.customer_id = (select auth.uid()))
  or ((select private.current_app_role()) = 'shipper' and exists
    (select 1 from public.delivery_tasks t where t.return_request_id = return_items.return_request_id
      and t.assigned_shipper_id = (select auth.uid()))));
create policy return_evidence_read on public.return_evidence for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or exists (select 1 from public.return_requests r where r.id = return_request_id
    and r.customer_id = (select auth.uid())));
create policy refund_accounts_read on public.refund_accounts for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or exists (select 1 from public.return_requests r where r.id = return_request_id
    and r.customer_id = (select auth.uid())));
create policy refunds_read on public.refunds for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or exists (select 1 from public.return_requests r where r.id = return_request_id
    and r.customer_id = (select auth.uid())));
create policy business_events_read on public.business_events for select to authenticated
using ((select private.current_app_role()) = 'manager');

create policy notifications_read on public.notifications for select to authenticated
using (recipient_id = (select auth.uid()));
create policy notifications_update on public.notifications for update to authenticated
using (recipient_id = (select auth.uid())) with check (recipient_id = (select auth.uid()));
grant update (read_at) on public.notifications to authenticated;

create policy conversations_read on public.conversations for select to authenticated
using ((select private.current_app_role()) = 'manager'
  or ((select private.current_app_role()) = 'customer' and customer_id = (select auth.uid())));
create policy conversations_insert on public.conversations for insert to authenticated
with check ((select private.current_app_role()) = 'customer' and customer_id = (select auth.uid()));
grant insert (customer_id) on public.conversations to authenticated;
create policy messages_read on public.messages for select to authenticated
using ((select private.current_app_role()) in ('customer', 'manager') and exists
  (select 1 from public.conversations c where c.id = conversation_id));
create policy messages_insert on public.messages for insert to authenticated
with check (sender_id = (select auth.uid())
  and (select private.current_app_role()) in ('customer', 'manager')
  and exists (select 1 from public.conversations c where c.id = conversation_id));
grant insert (conversation_id, sender_id, body, client_message_id) on public.messages to authenticated;
create policy conversation_reads_read on public.conversation_reads for select to authenticated
using ((select private.current_app_role()) in ('customer', 'manager') and exists
  (select 1 from public.conversations c where c.id = conversation_id));
create policy conversation_reads_insert on public.conversation_reads for insert to authenticated
with check (user_id = (select auth.uid())
  and (select private.current_app_role()) in ('customer', 'manager')
  and exists (select 1 from public.conversations c where c.id = conversation_id));
create policy conversation_reads_update on public.conversation_reads for update to authenticated
using (user_id = (select auth.uid())
  and (select private.current_app_role()) in ('customer', 'manager')
  and exists (select 1 from public.conversations c where c.id = conversation_id))
with check (user_id = (select auth.uid())
  and (select private.current_app_role()) in ('customer', 'manager')
  and exists (select 1 from public.conversations c where c.id = conversation_id));
grant insert (conversation_id, user_id, last_read_at), update (last_read_at)
  on public.conversation_reads to authenticated;
create policy store_settings_read on public.store_settings for select to authenticated
using ((select private.current_app_role()) in ('manager', 'shipper'));

create or replace function private.stamp_read_time()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if tg_table_name = 'notifications' then
    if new.read_at is not null then
      new.read_at := coalesce(old.read_at, clock_timestamp());
    elsif old.read_at is not null then
      new.read_at := old.read_at;
    end if;
  else
    new.last_read_at := clock_timestamp();
  end if;
  return new;
end;
$$;
revoke all on function private.stamp_read_time() from public, anon, authenticated, service_role;
create trigger notifications_stamp_read_time before update of read_at on public.notifications
for each row execute function private.stamp_read_time();
create trigger conversation_reads_stamp_read_time before insert or update of last_read_at on public.conversation_reads
for each row execute function private.stamp_read_time();

-- All evidence buckets are private. No technical file-size or MIME limits are
-- invented here; the report delegates these to a later technical specification.
insert into storage.buckets (id, name, public) values
  ('product-images', 'product-images', false),
  ('return-videos', 'return-videos', false),
  ('inspection-evidence', 'inspection-evidence', false),
  ('refund-evidence', 'refund-evidence', false);

create policy sports_store_product_images_read on storage.objects for select to authenticated
using (bucket_id = 'product-images' and (select private.current_app_role()) in ('customer', 'manager'));
create policy sports_store_product_images_insert on storage.objects for insert to authenticated
with check (bucket_id = 'product-images' and (select private.current_app_role()) = 'manager');
create policy sports_store_product_images_update on storage.objects for update to authenticated
using (bucket_id = 'product-images' and (select private.current_app_role()) = 'manager')
with check (bucket_id = 'product-images' and (select private.current_app_role()) = 'manager');
create policy sports_store_product_images_delete on storage.objects for delete to authenticated
using (bucket_id = 'product-images' and (select private.current_app_role()) = 'manager');

-- Return videos: <customer UUID>/<return UUID>/<file>. Customer can upload
-- before the transactional return submission API has registered the evidence.
create policy sports_store_return_videos_insert on storage.objects for insert to authenticated
with check (bucket_id = 'return-videos' and (select private.current_app_role()) = 'customer'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and cardinality(storage.foldername(name)) >= 2);
create policy sports_store_return_videos_read on storage.objects for select to authenticated
using (bucket_id = 'return-videos' and
  (((select private.current_app_role()) = 'customer'
      and (storage.foldername(name))[1] = (select auth.uid())::text)
    or ((select private.current_app_role()) = 'manager' and
      (exists (select 1 from public.return_requests r where r.video_object_path = name)
       or exists (select 1 from public.return_evidence e where e.object_path = name and e.kind::text = 'customer_video')))));

-- Manager evidence: <return UUID>/<file>. Shippers get no access to evidence.
create policy sports_store_inspection_evidence_insert on storage.objects for insert to authenticated
with check (bucket_id = 'inspection-evidence' and (select private.current_app_role()) = 'manager'
  and exists (select 1 from public.return_requests r where r.id::text = (storage.foldername(name))[1]));
create policy sports_store_inspection_evidence_read on storage.objects for select to authenticated
using (bucket_id = 'inspection-evidence' and
  ((select private.current_app_role()) = 'manager'
   or ((select private.current_app_role()) = 'customer' and exists
      (select 1 from public.return_evidence e join public.return_requests r on r.id = e.return_request_id
       where e.object_path = name and e.kind::text = 'inspection' and r.customer_id = (select auth.uid())))));
create policy sports_store_refund_evidence_insert on storage.objects for insert to authenticated
with check (bucket_id = 'refund-evidence' and (select private.current_app_role()) = 'manager'
  and exists (select 1 from public.return_requests r where r.id::text = (storage.foldername(name))[1]));
create policy sports_store_refund_evidence_read on storage.objects for select to authenticated
using (bucket_id = 'refund-evidence' and
  ((select private.current_app_role()) = 'manager'
   or ((select private.current_app_role()) = 'customer' and exists
      (select 1 from public.refunds f join public.return_requests r on r.id = f.return_request_id
       where f.transfer_evidence_path = name and r.customer_id = (select auth.uid())))));

notify pgrst, 'reload schema';
