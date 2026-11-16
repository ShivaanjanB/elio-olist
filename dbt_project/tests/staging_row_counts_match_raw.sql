{#
  Staging must be a 1:1 view of RAW once repeated keys are collapsed: no row gained, and none lost except a repeat of
  a key.
#}
with counts as (

    select 'orders' as model,
           (select count(*) from {{ ref('stg_olist__orders') }}) as staged,
           (select count(distinct order_id) from {{ source('olist', 'orders') }}) as raw_distinct_keys
    union all
    select 'order_items',
           (select count(*) from {{ ref('stg_olist__order_items') }}),
           (select count(distinct concat_ws('|', order_id, order_item_id)) from {{ source('olist', 'order_items') }})
    union all
    select 'customers',
           (select count(*) from {{ ref('stg_olist__customers') }}),
           (select count(distinct customer_id) from {{ source('olist', 'customers') }})
    union all
    select 'order_payments',
           (select count(*) from {{ ref('stg_olist__order_payments') }}),
           (select count(distinct concat_ws('|', order_id, payment_sequential)) from {{ source('olist', 'order_payments') }})
    union all
    select 'order_reviews',
           (select count(*) from {{ ref('stg_olist__order_reviews') }}),
           (select count(distinct concat_ws('|', review_id, order_id)) from {{ source('olist', 'order_reviews') }})
    union all
    select 'products',
           (select count(*) from {{ ref('stg_olist__products') }}),
           (select count(distinct product_id) from {{ source('olist', 'products') }})
    union all
    select 'sellers',
           (select count(*) from {{ ref('stg_olist__sellers') }}),
           (select count(distinct seller_id) from {{ source('olist', 'sellers') }})
    union all
    select 'product_category_translation',
           (select count(*) from {{ ref('stg_olist__product_category_translation') }}),
           (select count(distinct product_category_name) from {{ source('olist', 'product_category_name_translation') }})

)

select * from counts where staged <> raw_distinct_keys
