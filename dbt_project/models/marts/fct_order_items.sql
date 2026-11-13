{#
  One row per UNIT on an order (there is no quantity column: three of a product is three rows). The order-level facts an
  item needs, its purchase date, whether it counts as revenue and whether its order was late, are read from fct_orders so
  each is defined once (D48). fct_orders has exactly one row per order, so this join cannot repeat an item row
  (reconciliation tests prove it).

  Product and seller keys are computed from the natural keys with the same macro the dimensions use (D41).

  revenue is price where the order counts as revenue and 0 where it does not (D47), so a plain SUM(revenue) is already
  the right revenue. SUM(price) is the unfiltered total, which includes canceled and unavailable orders.
#}
with items as (

    select * from {{ ref('stg_olist__order_items') }}

),

orders as (

    select
        order_id,
        purchase_date,
        is_revenue_order,
        is_late
    from {{ ref('fct_orders') }}

)

select
    cast({{ generate_surrogate_key(['items.order_id', 'items.order_item_id']) }} as varchar(32))   as order_item_key,
    cast(items.order_id as varchar(32))                                                             as order_id,
    cast(items.order_item_id as number(10,0))                                                       as order_item_id,
    cast({{ generate_surrogate_key(['items.product_id']) }} as varchar(32))                         as product_sk,
    cast({{ generate_surrogate_key(['items.seller_id']) }} as varchar(32))                          as seller_sk,
    cast(orders.purchase_date as date)                                                              as purchase_date,
    cast(orders.is_revenue_order as boolean)                                                        as is_revenue_order,
    cast(orders.is_late as boolean)                                                                 as is_late,
    cast(items.price as number(12,2))                                                               as price,
    cast(iff(orders.is_revenue_order, items.price, 0) as number(12,2))                              as revenue,
    cast(items.freight_value as number(12,2))                                                       as freight_value

from items
inner join orders on orders.order_id = items.order_id
