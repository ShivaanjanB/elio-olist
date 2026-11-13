{#
  Rolls the item rows up to ORDER grain: one row per order that has items. An order can have up to 21 items, so
  joining items to orders directly would repeat the order's row (D15, D29). Orders with no items are absent here and
  become 0 in fct_orders.
#}
select
    order_id,
    count(*)                    as item_count,
    count(distinct seller_id)   as seller_count,
    sum(price)                  as items_price_total,
    sum(freight_value)          as freight_total

from {{ ref('stg_olist__order_items') }}
group by order_id
