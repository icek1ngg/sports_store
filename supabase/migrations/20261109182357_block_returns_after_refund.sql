-- Block repeat returns and duplicate refunds for an already refunded order.
-- Keep existing RPC signatures, privileges, RLS and idempotency handling.
begin;

do $migration$
declare
  target regprocedure;
  definition text;
  patched text;
begin
  foreach target in array array[
    'private.orders_return_creation_open(uuid)'::regprocedure,
    'public.get_return_request_context(uuid)'::regprocedure,
    'public.submit_return_request(uuid,uuid,text,text,text,text,text,text)'::regprocedure
  ] loop
    definition := pg_catalog.pg_get_functiondef(target);
    patched := replace(definition,
      '''redelivery_failed'', ''manager_action_required''',
      '''redelivery_failed'', ''manager_action_required'', ''refunded''');
    if patched = definition then
      raise exception 'Refund eligibility predicate not found in %', target;
    end if;
    execute patched;
  end loop;
end;
$migration$;

-- Serialize by order, including requests created before this fix. A second
-- request must never progress to a second refund even if it already exists.
create function private.block_repeated_order_refund()
returns trigger
language plpgsql security invoker set search_path = ''
as $$
begin
  if TG_OP = 'UPDATE' then
    if new.status <> 'refunded' or old.status = 'refunded' then
      return new;
    end if;
  end if;
  perform 1 from public.orders o where o.id = new.order_id for update;
  if exists (
    select 1 from public.return_requests r
    where r.order_id = new.order_id and r.id <> new.id
      and r.status = 'refunded'
  ) then
    if TG_OP = 'INSERT' then
      raise exception using errcode = 'PT409', message = 'ACTIVE_RETURN_EXISTS';
    end if;
    raise exception using errcode = 'PT409', message = 'STATE_CONFLICT';
  end if;
  return new;
end;
$$;
revoke all on function private.block_repeated_order_refund() from public, anon, authenticated;
create trigger block_repeated_order_refund
before insert or update of status on public.return_requests
for each row execute function private.block_repeated_order_refund();

notify pgrst, 'reload schema';
commit;
