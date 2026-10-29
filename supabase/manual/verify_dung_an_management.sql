-- READ-ONLY verification. Run after dung_an_management.sql in the same project.
-- Every RPC: installed=true, authenticated_can_execute=true, anon_can_execute=false.
with expected(signature) as (values
  ('public.save_managed_product(uuid,uuid,timestamp with time zone,text,uuid,text,text,boolean,jsonb)'),
  ('public.list_chat_conversations()'),
  ('public.ensure_customer_conversation()'),
  ('public.get_chat_messages(uuid,uuid)'),
  ('public.send_chat_message(uuid,uuid,text)')
), resolved as (
  select signature, to_regprocedure(signature) as function_id from expected
)
select signature, function_id is not null as installed,
  coalesce(has_function_privilege('authenticated', function_id, 'execute'), false) as authenticated_can_execute,
  coalesce(has_function_privilege('anon', function_id, 'execute'), false) as anon_can_execute
from resolved order by signature;

-- Every expected table should exist and have RLS enabled.
with expected(schema_name, table_name) as (values
  ('public','profiles'), ('public','categories'), ('public','products'),
  ('public','product_variants'), ('public','inventory_movements'),
  ('public','conversations'), ('public','messages'),
  ('private','catalog_command_receipts')
)
select e.schema_name, e.table_name, c.oid is not null as installed,
  coalesce(c.relrowsecurity, false) as rls_enabled
from expected e
left join pg_namespace n on n.nspname=e.schema_name
left join pg_class c on c.relnamespace=n.oid and c.relname=e.table_name
order by e.schema_name,e.table_name;

-- Both trigger rows should have installed=true and enabled=true.
with expected(table_name, trigger_name) as (values
  ('messages','messages_stamp_server_time'),
  ('conversations','conversations_stamp_read_at')
)
select e.table_name,e.trigger_name,t.oid is not null as installed,
  coalesce(t.tgenabled <> 'D',false) as enabled
from expected e
left join pg_trigger t on t.tgrelid=to_regclass('public.'||e.table_name)
  and t.tgname=e.trigger_name and not t.tgisinternal
order by e.table_name;
