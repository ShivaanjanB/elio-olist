{#
  Money and counts in the marts must add up to the staging tables they came from. This is the test that catches fan-out:
  a join that repeats rows leaves the row counts of a dimension fine but inflates a SUM, which is exactly what the
  careless join in docs/relationship_checks.sql did (+26.9% on payments, +4.5% on prices). Returns one row per measure
  that does not match; the test passes when nothing is returned (D45).

  Debugging a failure: the two sides are shown, so the gap says whether rows were repeated (mart too high) or lost
  (mart too low).
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
