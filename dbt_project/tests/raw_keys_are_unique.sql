{{ config(severity='warn') }}

{#
  Reports any RAW table in which a key appears more than once, for example after a file was loaded twice without
  truncating first.
#}
with counts as (

    select 'customers' as raw_table, count(*) as raw_rows, count(distinct customer_id) as distinct_keys
    from {{ source('olist', 'customers') }}
    union all
    select 'order_items' as raw_table, count(*) as raw_rows, count(distinct concat_ws('|', order_id, order_item_id)) as distinct_keys
    from {{ source('olist', 'order_items') }}
    union all
    select 'order_payments' as raw_table, count(*) as raw_rows, count(distinct concat_ws('|', order_id, payment_sequential)) as distinct_keys
    from {{ source('olist', 'order_payments') }}
    union all
    select 'order_reviews' as raw_table, count(*) as raw_rows, count(distinct concat_ws('|', review_id, order_id)) as distinct_keys
    from {{ source('olist', 'order_reviews') }}
    union all
    select 'orders' as raw_table, count(*) as raw_rows, count(distinct order_id) as distinct_keys
    from {{ source('olist', 'orders') }}
    union all
    select 'product_category_name_translation' as raw_table, count(*) as raw_rows, count(distinct product_category_name) as distinct_keys
    from {{ source('olist', 'product_category_name_translation') }}
    union all
    select 'products' as raw_table, count(*) as raw_rows, count(distinct product_id) as distinct_keys
    from {{ source('olist', 'products') }}
    union all
    select 'sellers' as raw_table, count(*) as raw_rows, count(distinct seller_id) as distinct_keys
    from {{ source('olist', 'sellers') }}

)

select * from counts where raw_rows <> distinct_keys
