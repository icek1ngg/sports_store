-- SOURCE ONLY. Additional review/authorization required beyond the two B2
-- hashes. Reuse the team's canonical identity-only bridge; never grant custom
-- roles access to hosted Auth tables/schema or change the Auth feature.
begin;
do $$ begin
 if not exists(select 1 from pg_proc p where p.oid=to_regprocedure('private.delivery_request_user_id()')
   and p.prosecdef and p.provolatile='s' and p.prorettype='uuid'::regtype
   and pg_get_userbyid(p.proowner)='postgres'
   and btrim(replace(p.prosrc,E'\r\n',E'\n'))='select auth.uid()') then
  raise exception 'Canonical internal identity bridge missing or changed';
 end if;
 if not exists(select 1 from pg_roles where rolname='sports_store_orders_writer'
   and not rolcanlogin and not rolinherit and not rolsuper and not rolbypassrls) then
  raise exception 'Unsafe/missing Orders writer role';
 end if;
 if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where p.proowner='sports_store_orders_writer'::regrole and position('auth.uid()' in p.prosrc)>0
     and n.nspname||'.'||p.proname in ('private.orders_execute_command','public.get_order_operation_result','private.orders_write_capabilities'))<>3 then
  raise exception 'Unexpected Orders identity function drift';
 end if;
end $$;
grant execute on function private.delivery_request_user_id() to sports_store_orders_writer;
-- Preserve signatures, ACLs, owners, volatility and definer/invoker flags.
do $$ declare f record; definition text; begin
 for f in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.proowner='sports_store_orders_writer'::regrole
   and n.nspname||'.'||p.proname in ('private.orders_execute_command','public.get_order_operation_result','private.orders_write_capabilities') loop
  definition:=pg_get_functiondef(f.oid);
  execute replace(definition,'auth.uid()','private.delivery_request_user_id()');
 end loop;
end $$;
-- Policies execute under the dedicated role too. Change only B2 writer's
-- policies; all client/other-module policies and role lists remain intact.
do $$ declare p record; statement text; begin
 for p in select n.nspname,c.relname,x.polname,
   pg_get_expr(x.polqual,x.polrelid) as qual,
   pg_get_expr(x.polwithcheck,x.polrelid) as check_expr
  from pg_policy x join pg_class c on c.oid=x.polrelid join pg_namespace n on n.oid=c.relnamespace
  where x.polroles=array['sports_store_orders_writer'::regrole::oid]
   and x.polname in ('orders_writer_orders_read','orders_writer_orders_update','orders_writer_events_insert') loop
  statement:=format('alter policy %I on %I.%I',p.polname,p.nspname,p.relname);
  if p.qual is not null then statement:=statement||' using ('||replace(p.qual,'auth.uid()','private.delivery_request_user_id()')||')'; end if;
  if p.check_expr is not null then statement:=statement||' with check ('||replace(p.check_expr,'auth.uid()','private.delivery_request_user_id()')||')'; end if;
  execute statement;
 end loop;
 if exists(select 1 from pg_proc where proowner='sports_store_orders_writer'::regrole
   and position('auth.uid()' in prosrc)>0) then raise exception 'Unbridged Orders identity reference'; end if;
 if exists(select 1 from pg_policy x where x.polroles=array['sports_store_orders_writer'::regrole::oid]
   and (position('auth.uid()' in coalesce(pg_get_expr(x.polqual,x.polrelid),''))>0
     or position('auth.uid()' in coalesce(pg_get_expr(x.polwithcheck,x.polrelid),''))>0)) then
  raise exception 'Unbridged Orders policy identity reference';
 end if;
end $$;
notify pgrst,'reload schema';
commit;
