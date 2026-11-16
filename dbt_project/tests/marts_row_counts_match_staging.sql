{#
  The marts must neither lose nor invent rows.
#}
with counts as (

    select 'fct_orders' as model,
           (select count(*) from {{ ref('fct_orders') }}) as in_mart,
           (select count(*) from {{ ref('stg_olist__orders') }}) as expected
    union all
    select 'fct_order_items',
           (select count(*) from {{ ref('fct_order_items') }}),
           (select count(*) from {{ ref('stg_olist__order_items') }})
    union all
    select 'dim_customer',
           (select count(*) from {{ ref('dim_customer') }}),
           (select count(distinct customer_unique_id) from {{ ref('stg_olist__customers') }})
    union all
    select 'dim_product',
           (select count(*) from {{ ref('dim_product') }}),
           (select count(*) from {{ ref('stg_olist__products') }})
    union all
    select 'dim_seller',
           (select count(*) from {{ ref('dim_seller') }}),
           (select count(*) from {{ ref('stg_olist__sellers') }})
    union all
    select 'dim_date',
           (select count(*) from {{ ref('dim_date') }}),
           datediff(day, to_date('2016-01-01'), to_date('2018-12-31')) + 1

)

select * from counts where in_mart <> expected
