{#
  The marts must neither lose nor invent rows. Returns one row per model whose count differs from what it should be;
  the test passes when nothing is returned.

  Why this exists: a join that fans out or an inner join that drops rows can leave every key unique and every relationship
  valid, and still be wrong. Only a count against the source of the grain catches it (D45).

  Expected counts and where they come from:
    fct_orders        one row per order           = rows in stg_olist__orders
    fct_order_items   one row per unit            = rows in stg_olist__order_items
    dim_customer      one row per person          = distinct customer_unique_id in stg_olist__customers
    dim_product       one row per product         = rows in stg_olist__products
    dim_seller        one row per seller          = rows in stg_olist__sellers
    dim_date          one row per day             = days from 2016-01-01 to 2018-12-31 inclusive (1,096)

  Debugging a failure: compare the two counts, then look for a join in that model that can repeat or drop rows.
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
