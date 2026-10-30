-- Đơn DEMO test shipper; địa điểm công cộng, tọa độ minh họa, không giao thật.
begin;
select pg_advisory_xact_lock(hashtext('shipper-demo-20261030'));
do $seed$
declare
 c uuid; m uuid; s uuid; o uuid; req uuid; items jsonb; result jsonb;
 row jsonb; i integer := 0;
begin
 select p.id into strict c from public.profiles p join auth.users u on u.id=p.id where u.email='customer@gmail.com' and p.role='customer';
 select p.id into strict m from public.profiles p join auth.users u on u.id=p.id where u.email='manager@gmail.com' and p.role='manager';
 select p.id into strict s from public.profiles p join auth.users u on u.id=p.id where u.email='shipper@gmail.com' and p.role='shipper';
 for row in select value from jsonb_array_elements($data$[["Cổng Bưu điện Hà Nội, 75 Đinh Tiên Hoàng, Hoàn Kiếm, Hà Nội",21.026,105.8523],["Cổng Nhà hát Lớn Hà Nội, 1 Tràng Tiền, Hoàn Kiếm, Hà Nội",21.0242,105.8576],["Cổng Văn Miếu, 58 Quốc Tử Giám, Đống Đa, Hà Nội",21.0272,105.8355],["Cổng Công viên Thống Nhất, đường Trần Nhân Tông, Hai Bà Trưng, Hà Nội",21.017,105.843],["Cổng Bảo tàng Dân tộc học, Nguyễn Văn Huyên, Cầu Giấy, Hà Nội",21.0404,105.7981]]$data$::jsonb)
 loop
 i := i+1;
 req := ('a1030030-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid;
 if exists(select 1 from public.orders where customer_id=c and request_id=req) then continue; end if;
 select jsonb_agg(jsonb_build_object('variant_id',id,'quantity',1) order by sku) into items
 from public.product_variants where sku in ('DEMO-20261030-'||lpad((i*2-1)::text,2,'0'),'DEMO-20261030-'||lpad((i*2)::text,2,'0'));
 if jsonb_array_length(items) is distinct from 2 then raise exception 'Missing demo variants'; end if;
 perform set_config('request.jwt.claim.sub',c::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated')::text,true);
 result := public.place_order(req,items,'DEMO giao hàng '||i,'0000000000',row->>0,(row->>1)::numeric,(row->>2)::numeric);
 select id into strict o from public.orders where customer_id=c and request_id=req;
 -- Trusted admin seed: confirmation RPC is not available in this database.
 update public.orders set status='preparing',confirmed_at=now(),source='manager',confirmed_by=m where id=o and status='pending_confirmation';
 insert into public.business_events(actor_id,subject_type,subject_id,from_state,to_state,reason,request_id)
 values(m,'order',o,'pending_confirmation','preparing','demo_seed_manager_confirmation',gen_random_uuid());
 perform set_config('request.jwt.claim.sub',m::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
 perform public.assign_delivery_task(o,s,('a1030030-0000-4000-9000-'||lpad(i::text,12,'0'))::uuid);
 end loop;
end;
$seed$;
commit;
