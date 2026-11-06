-- Hosted Supabase does not allow postgres to grant custom roles USAGE on the
-- managed auth schema. Keep auth.uid canonical; expose only its UUID result to
-- the dedicated internal function owners, never Auth tables or client roles.
create function private.delivery_request_user_id()
returns uuid
language sql stable security definer
set search_path = ''
as $$ select auth.uid() $$;
alter function private.delivery_request_user_id() owner to postgres;
revoke all on function private.delivery_request_user_id()
  from public, anon, authenticated, service_role;
grant usage on schema private
  to sports_store_delivery_reader, sports_store_delivery_writer,
     sports_store_cod_receipt_writer, sports_store_outbound_writer;
grant execute on function private.delivery_request_user_id()
  to sports_store_delivery_reader, sports_store_delivery_writer,
     sports_store_cod_receipt_writer, sports_store_outbound_writer;

-- Restrict replacements to functions owned by this repository's four internal
-- roles in the two application schemas. Preserve signatures, bodies, owner,
-- volatility/search_path and existing EXECUTE ACLs with CREATE OR REPLACE.
do $$
declare
  l_function record;
  l_definition text;
  l_roles oid[] := array[
    'sports_store_delivery_reader'::regrole::oid,
    'sports_store_delivery_writer'::regrole::oid,
    'sports_store_cod_receipt_writer'::regrole::oid,
    'sports_store_outbound_writer'::regrole::oid
  ];
begin
  for l_function in
    select p.oid
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where p.proowner=any(l_roles) and n.nspname in ('public','private')
      and p.prokind='f'
    order by p.oid
  loop
    l_definition := pg_get_functiondef(l_function.oid);
    if position('auth.uid()' in l_definition) > 0 then
      execute replace(l_definition, 'auth.uid()', 'private.delivery_request_user_id()');
    end if;
  end loop;
end;
$$;

-- Only internal-role policies change. Client/Storage policies and all table
-- privileges/role memberships remain exactly as before this migration.
do $$
declare
  l_policy record;
  l_using text;
  l_check text;
  l_sql text;
  l_roles oid[] := array[
    'sports_store_delivery_reader'::regrole::oid,
    'sports_store_delivery_writer'::regrole::oid,
    'sports_store_cod_receipt_writer'::regrole::oid,
    'sports_store_outbound_writer'::regrole::oid
  ];
begin
  for l_policy in
    select p.polname, n.nspname, c.relname,
      pg_get_expr(p.polqual,p.polrelid) as using_expression,
      pg_get_expr(p.polwithcheck,p.polrelid) as check_expression
    from pg_policy p join pg_class c on c.oid=p.polrelid
      join pg_namespace n on n.oid=c.relnamespace
    where p.polroles <@ l_roles and cardinality(p.polroles)>0
      and n.nspname in ('public','private')
    order by n.nspname,c.relname,p.polname
  loop
    l_using := l_policy.using_expression;
    l_check := l_policy.check_expression;
    if position('auth.uid()' in coalesce(l_using,''))=0
       and position('auth.uid()' in coalesce(l_check,''))=0 then
      continue;
    end if;
    l_sql := format('alter policy %I on %I.%I', l_policy.polname,
      l_policy.nspname,l_policy.relname);
    if l_using is not null then
      l_sql := l_sql || ' using (' || replace(l_using,'auth.uid()',
        'private.delivery_request_user_id()') || ')';
    end if;
    if l_check is not null then
      l_sql := l_sql || ' with check (' || replace(l_check,'auth.uid()',
        'private.delivery_request_user_id()') || ')';
    end if;
    execute l_sql;
  end loop;
end;
$$;

comment on function private.delivery_request_user_id() is
  'Internal canonical request UUID only; no Auth table access; hosted auth-schema ACL bridge.';
notify pgrst, 'reload schema';
