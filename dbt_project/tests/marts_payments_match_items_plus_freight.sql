{{ config(severity='warn') }}

{#
  Production check: what customers paid for an order should sit close to what the items and freight add up to.
  Compares payment_total with gmv (item price plus freight) for every order that has at least one item and one payment.

  It does NOT demand an exact match, because they legitimately differ: instalment plans add interest, and vouchers and
  split payments move amounts around (D16: 232 orders were paid more than the items and freight by over 1.00, 17 less).
  Today 249 of 98,665 orders (0.25%) differ by more than 1.00. The test warns when more than 1% do, which would mean
  items or payments were loaded wrongly, a join started repeating rows, or the source changed how it records payments.
  Returns one row when that happens; passes when empty. Severity is warn, so it is visible without stopping a build.

  Debugging a failure: compare outside_pct with 0.25%. Then query fct_orders for the orders where
  abs(payment_total - gmv) > 1 and look at their payment_count and primary_payment_type, then at the same
  order in stg_olist__order_payments and stg_olist__order_items.
#}
with compared as (

    select
        count(*)                                              as orders_compared,
        count_if(abs(payment_total - gmv) > 1.00)             as orders_outside_tolerance
    from {{ ref('fct_orders') }}
    where item_count > 0
      and payment_count > 0

)

select
    orders_compared,
    orders_outside_tolerance,
    round(100 * orders_outside_tolerance / orders_compared, 3) as outside_pct
from compared
where orders_outside_tolerance > 0.01 * orders_compared
