{#
  Staging must be a 1:1 view of RAW: no row gained, none lost. Returns one row per model whose row count differs
  from its source table; the test passes when nothing is returned.

  Why this exists: a wrong join or filter added to a staging model would not trip a key test, because
  the surviving rows can still be unique. A count comparison catches it.

  Debugging a failure: compare the two counts, then check the model's SQL for a where clause or join.
#}
with counts as (

    select 'orders' as model,
           (select count(*) from {{ ref('stg_olist__orders') }}) as staged,
           (select count(*) from {{ source('olist', 'orders') }}) as raw
    union all
    select 'order_items',
           (select count(*) from {{ ref('stg_olist__order_items') }}),
           (select count(*) from {{ source('olist', 'order_items') }})
    union all
    select 'customers',
           (select count(*) from {{ ref('stg_olist__customers') }}),
           (select count(*) from {{ source('olist', 'customers') }})
    union all
    select 'order_payments',
           (select count(*) from {{ ref('stg_olist__order_payments') }}),
           (select count(*) from {{ source('olist', 'order_payments') }})
    union all
    select 'order_reviews',
           (select count(*) from {{ ref('stg_olist__order_reviews') }}),
           (select count(*) from {{ source('olist', 'order_reviews') }})
    union all
    select 'products',
           (select count(*) from {{ ref('stg_olist__products') }}),
           (select count(*) from {{ source('olist', 'products') }})
    union all
    select 'sellers',
           (select count(*) from {{ ref('stg_olist__sellers') }}),
           (select count(*) from {{ source('olist', 'sellers') }})
    union all
    select 'product_category_translation',
           (select count(*) from {{ ref('stg_olist__product_category_translation') }}),
           (select count(*) from {{ source('olist', 'product_category_name_translation') }})

)

select * from counts where staged <> raw
