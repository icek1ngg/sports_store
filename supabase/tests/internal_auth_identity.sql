-- Regression for managed Supabase auth-schema ACLs; never reads Auth tables.
begin;
select set_config('request.jwt.claim.sub','',true), set_config('request.jwt.claims','{}',true);
do $$
declare l_role text;
begin
  -- Native fixture grants are reversible; hosted roles already lack access,
  -- so avoid attempting unsupported grants/revokes on managed auth schema.
  foreach l_role in array array['sports_store_delivery_reader','sports_store_delivery_writer',
    'sports_store_cod_receipt_writer','sports_store_outbound_writer',
    'sports_store_outbound_completion_writer'] loop
    if has_schema_privilege(l_role,'auth','USAGE') then
      execute format('revoke usage on schema auth from %I',l_role);
    end if;
    if has_schema_privilege(l_role,'auth','USAGE') then
      raise exception 'Internal role unexpectedly retains auth schema access';
    end if;
  end loop;
  if not exists(select 1 from pg_proc p where p.oid='private.delivery_request_user_id()'::regprocedure
    and p.prosecdef and p.provolatile='s' and pg_get_userbyid(p.proowner)='postgres'
    and p.proconfig @> array['search_path=""']) then
    raise exception 'Identity bridge owner/configuration is unsafe';
  end if;
  if has_function_privilege('authenticated','private.delivery_request_user_id()','EXECUTE')
    or has_function_privilege('anon','private.delivery_request_user_id()','EXECUTE')
    or has_function_privilege('service_role','private.delivery_request_user_id()','EXECUTE') then
    raise exception 'Identity bridge must not be callable by client roles';
  end if;
end;
$$;
set local role sports_store_delivery_reader;
do $$ begin
  if private.delivery_request_user_id() is not null then raise exception 'Missing request must return NULL'; end if;
end $$;
reset role;
set local role sports_store_outbound_writer;
do $$ begin
  if private.delivery_request_user_id() is not null then raise exception 'Missing request must return NULL'; end if;
end $$;
reset role;
set local role sports_store_outbound_completion_writer;
do $$ begin
  if private.delivery_request_user_id() is not null then raise exception 'Missing request must return NULL'; end if;
end $$;
reset role;
set local role authenticated;
do $$
declare l_code text;
begin
  begin perform private.delivery_request_user_id();
  exception when others then l_code:=sqlstate;
  end;
  if l_code is distinct from '42501' then raise exception 'Client called internal identity bridge'; end if;
  l_code:=null;
  begin perform public.accept_delivery_task('04150000-0000-0000-0000-000000000001'::uuid,
    '04150000-0000-0000-0000-000000000002'::uuid);
  exception when others then
    l_code:=sqlstate;
    if sqlerrm <> 'AUTH_REQUIRED' then raise exception 'Wrong missing-session rejection: %',sqlerrm; end if;
  end;
  if l_code is distinct from '42501' then raise exception 'Missing session was not denied'; end if;
end;
$$;
reset role;
select 'internal_auth_identity.sql: PASS' as result;
rollback;
