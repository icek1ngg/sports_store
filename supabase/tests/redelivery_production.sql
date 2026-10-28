-- Native isolated tests: seed business input only; every transition below
-- calls the real restricted production RPC. Fixture inspection proofs are
-- deliberately ignored by production, which must create its own proof chain.
create function pg_temp.claim(a uuid) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
end; $$;
create function pg_temp.check_ok(ok boolean) returns void language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'P083 assertion failed'; end if;
end; $$;
create function pg_temp.reject_redelivery_outcome() returns trigger language plpgsql as $$ begin
 if current_setting('sports_store.p083_fault',true)='on' then
   raise exception 'late transaction fault' using errcode='P9999';
 end if; return new;
end; $$;
create trigger p083_late_fault before insert on private.redelivery_outcomes
for each row execute function pg_temp.reject_redelivery_outcome();
do $$ declare name text; begin
 foreach name in array array['approve_return_pickup_plan(uuid,uuid,jsonb)',
  'receive_customer_return(uuid,uuid,jsonb)','reject_return_after_inspection(uuid,uuid,text)',
  'assign_redelivery_task(uuid,uuid,uuid)','accept_redelivery_task(uuid,uuid,jsonb)',
  'start_redelivery_task(uuid,uuid)','complete_redelivery(uuid,uuid,boolean)',
  'fail_redelivery_task(uuid,uuid,text,text)'] loop
  perform pg_temp.check_ok(has_function_privilege('authenticated','public.'||name,'execute'));
  perform pg_temp.check_ok(not has_function_privilege('anon','public.'||name,'execute'));
 end loop;
 perform pg_temp.check_ok(not has_table_privilege('authenticated','private.redelivery_custody','select'));
 perform pg_temp.check_ok(not has_table_privilege('authenticated','private.redelivery_release_plan_items','insert'));
end; $$;
set local role authenticated;
do $$ begin
 begin perform 1 from private.redelivery_custody;
  raise exception 'private custody exposed'; exception when insufficient_privilege then null; end;
end; $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.complete_redelivery(gen_random_uuid(),gen_random_uuid(),true);
  raise exception 'anonymous execution exposed'; exception when insufficient_privilege then null; end;
end; $$;
reset role;
do $$ declare
 x jsonb; plan jsonb; ack jsonb; receipt jsonb; task uuid; pickup uuid;
 rid uuid; oid uuid; mgr uuid; ship uuid; other_ship uuid; key uuid;
 before_cod jsonb; before_inventory jsonb; mode text;
begin
 foreach mode in array array['success','failure'] loop
  x:=p083_fixture.seed_redelivery_case_fixture('prod_'||mode,'complete');
  rid:=(x->>'return_request_id')::uuid; oid:=(x->>'order_id')::uuid;
  mgr:=(x->>'manager_id')::uuid; ship:=(x->>'shipper_id')::uuid;
  other_ship:=(x->>'alternate_shipper_id')::uuid;
  update public.return_requests set status='pending_review',decision_at=null,decided_by=null,
    inspection_started_at=null,inspected_at=null,inspected_by=null where id=rid;
  update public.return_items set quantity_collected=0 where return_request_id=rid;
  select jsonb_agg(jsonb_build_object('return_item_id',id,'quantity',quantity_to_collect) order by id)
    into plan from public.return_items where return_request_id=rid;
  select to_jsonb(c) into before_cod from public.cod_collections c where order_id=oid;
  select jsonb_agg(to_jsonb(v) order by v.id) into before_inventory from public.product_variants v;
  perform pg_temp.claim(ship);
  begin perform public.approve_return_pickup_plan(rid,gen_random_uuid(),plan);
    raise exception 'shipper approval allowed'; exception when insufficient_privilege then null; end;
  perform pg_temp.claim(mgr);
  begin perform public.assign_redelivery_task(rid,ship,gen_random_uuid());
    raise exception 'assignment without inspection proof allowed'; exception when sqlstate 'PT409' then null; end;
  begin perform public.reject_return_after_inspection(rid,gen_random_uuid(),'No receipt exists');
    raise exception 'inspection without receipt allowed'; exception when sqlstate 'PT409' then null; end;
  perform public.approve_return_pickup_plan(rid,gen_random_uuid(),plan);
  ack:=public.assign_return_pickup_task(rid,ship,gen_random_uuid()); pickup:=(ack->>'task_id')::uuid;
  begin perform public.receive_customer_return(pickup,gen_random_uuid(),plan);
    raise exception 'premature receipt allowed'; exception when sqlstate 'PT409' then null; end;
  perform pg_temp.claim(ship);
  perform public.collect_return_items(pickup,gen_random_uuid(),plan);
  perform public.report_return_pickup_handover(pickup,gen_random_uuid(),plan);
  perform pg_temp.claim(mgr);
  begin perform public.receive_customer_return(pickup,gen_random_uuid(),'[]'::jsonb);
    raise exception 'partial store receipt allowed'; exception when invalid_parameter_value then null; end;
  key:=gen_random_uuid(); ack:=public.receive_customer_return(pickup,key,plan);
  perform pg_temp.check_ok(ack=public.receive_customer_return(pickup,key,plan));
  perform public.reject_return_after_inspection(rid,gen_random_uuid(),'Inspection rejected: full actual goods released');
  ack:=public.assign_redelivery_task(rid,ship,gen_random_uuid()); task:=(ack->>'task_id')::uuid;
  perform pg_temp.check_ok((select amount_to_collect_vnd=0 and attempt_number=1 from public.delivery_tasks where id=task));
  perform pg_temp.claim(other_ship);
  begin perform public.accept_redelivery_task(task,gen_random_uuid(),plan);
    raise exception 'other shipper accepted'; exception when insufficient_privilege then null; end;
  perform pg_temp.claim(ship);
  begin perform public.start_redelivery_task(task,gen_random_uuid());
    raise exception 'start without custody'; exception when sqlstate 'PT409' then null; end;
  perform pg_temp.check_ok((select count(*)=2 from public.read_my_delivery_task_items(task)));
  perform pg_temp.check_ok((public.get_my_delivery_task(task)->'task'->>'item_source')='return_plan');
  key:=gen_random_uuid(); ack:=public.accept_redelivery_task(task,key,plan);
  perform pg_temp.check_ok(ack=public.accept_redelivery_task(task,key,plan));
  perform public.start_redelivery_task(task,gen_random_uuid());
  key:=gen_random_uuid();
  perform set_config('sports_store.p083_fault','on',true);
  begin perform public.complete_redelivery(task,key,true);
    raise exception 'late fault did not fire'; exception when sqlstate 'P9999' then null; end;
  perform set_config('sports_store.p083_fault','off',true);
  perform pg_temp.check_ok((select status='in_transit' and completed_at is null from public.delivery_tasks where id=task));
  perform pg_temp.check_ok(not exists(select 1 from private.redelivery_requests where actor_id=ship and request_id=key));
  if mode='success' then
    begin perform public.complete_redelivery(task,key,false);
      raise exception 'partial completion'; exception when invalid_parameter_value then null; end;
    ack:=public.complete_redelivery(task,key,true);
    perform pg_temp.check_ok(ack=public.complete_redelivery(task,key,true));
    perform pg_temp.check_ok((select status='rejected_after_inspection' and closed_at is not null from public.return_requests where id=rid));
    begin perform public.fail_redelivery_task(task,gen_random_uuid(),'unreachable',null);
      raise exception 'opposite outcome allowed'; exception when sqlstate 'PT409' then null; end;
  else
    begin perform public.fail_redelivery_task(task,key,'other',null);
      raise exception 'missing reason'; exception when invalid_parameter_value then null; end;
    ack:=public.fail_redelivery_task(task,key,'other','Customer unavailable');
    perform pg_temp.check_ok(ack=public.fail_redelivery_task(task,key,'other','Customer unavailable'));
    begin perform public.fail_redelivery_task(task,key,'other','Different description');
      raise exception 'payload mismatch allowed'; exception when sqlstate 'PT409' then null; end;
    perform pg_temp.check_ok((select status='manager_action_required' and closed_at is null from public.return_requests where id=rid));
    perform pg_temp.check_ok((select status='manager_action_required' and completed_at is null from public.delivery_tasks where id=task));
    begin perform public.complete_redelivery(task,gen_random_uuid(),true);
      raise exception 'opposite outcome allowed'; exception when sqlstate 'PT409' then null; end;
  end if;
  perform pg_temp.check_ok(before_cod=(select to_jsonb(c) from public.cod_collections c where order_id=oid));
  perform pg_temp.check_ok(before_inventory=(select jsonb_agg(to_jsonb(v) order by v.id) from public.product_variants v));
  perform pg_temp.check_ok(not exists(select 1 from public.delivery_attempts where order_id=oid));
  perform pg_temp.check_ok((select count(*)=1 from private.redelivery_outcomes where task_id=task));
 end loop;
end; $$;
select 'redelivery_production.sql: PASS' as result;
rollback;
