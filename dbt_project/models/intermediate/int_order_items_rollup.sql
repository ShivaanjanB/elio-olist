{#
  Rolls the item rows up to ORDER grain: one row per order that has items.
#}
select
    order_id,
    count(*)                    as item_count,
    count(distinct seller_id)   as seller_count,
    sum(price)                  as items_price_total,
    sum(freight_value)          as freight_total

from {{ ref('stg_olist__order_items') }}
group by order_id
