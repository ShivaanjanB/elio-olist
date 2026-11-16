{#
  Money and counts in the marts must add up to the staging tables they came from.
#}
with checks as (

    select 'item price: fct_order_items vs staging' as measure,
           (select sum(price) from {{ ref('fct_order_items') }}) as in_mart,
           (select sum(price) from {{ ref('stg_olist__order_items') }}) as in_staging
    union all
    select 'item freight: fct_order_items vs staging',
           (select sum(freight_value) from {{ ref('fct_order_items') }}),
           (select sum(freight_value) from {{ ref('stg_olist__order_items') }})
    union all
    select 'item price: fct_orders vs staging',
           (select sum(items_price_total) from {{ ref('fct_orders') }}),
           (select sum(price) from {{ ref('stg_olist__order_items') }})
    union all
    select 'item count: fct_orders vs staging',
           (select sum(item_count) from {{ ref('fct_orders') }}),
           (select count(*) from {{ ref('stg_olist__order_items') }})
    union all
    select 'payments: fct_orders vs staging',
           (select sum(payment_total) from {{ ref('fct_orders') }}),
           (select sum(payment_value) from {{ ref('stg_olist__order_payments') }})
    union all
    select 'payment count: fct_orders vs staging',
           (select sum(payment_count) from {{ ref('fct_orders') }}),
           (select count(*) from {{ ref('stg_olist__order_payments') }})
    union all
    select 'orders with a review: fct_orders vs staging',
           (select count(review_score) from {{ ref('fct_orders') }}),
           (select count(distinct order_id) from {{ ref('stg_olist__order_reviews') }})

)

select * from checks where in_mart <> in_staging
