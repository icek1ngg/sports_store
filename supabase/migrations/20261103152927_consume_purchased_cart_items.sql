-- A placement is inserted once, after the order lines and reservation exist.
create function private.consume_purchased_cart_items()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  merge into public.cart_items as cart
  using (
    select variant_id, quantity from public.order_items where order_id = new.order_id
  ) as purchased
  on cart.customer_id = new.customer_id and cart.variant_id = purchased.variant_id
  when matched and cart.quantity <= purchased.quantity then delete
  when matched then update set quantity = cart.quantity - purchased.quantity;
  return new;
end;
$$;

revoke all on function private.consume_purchased_cart_items() from public, anon, authenticated;

create trigger consume_purchased_cart_items
after insert on private.checkout_placements
for each row execute function private.consume_purchased_cart_items();
