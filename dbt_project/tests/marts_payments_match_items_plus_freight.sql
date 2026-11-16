{{ config(severity='warn') }}

{#
  Production check: what customers paid for an order should sit close to what the items and freight add up to.
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
