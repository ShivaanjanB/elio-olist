{#
  One row per product. The category shown to analysts is the English name, else the Portuguese one, else 'unknown' (D22):
  13 products sit in 2 categories the translation table lacks, and 610 products have no category at all.
  volume_cm3 is length x height x width of the package, NULL when any of the three is unknown (2 products).
#}
with products as (

    select * from {{ ref('stg_olist__products') }}

),

translation as (

    select * from {{ ref('stg_olist__product_category_translation') }}

)

select
    cast({{ generate_surrogate_key(['products.product_id']) }} as varchar(32))   as product_sk,
    cast(products.product_id as varchar(32))                                      as product_id,
    cast(
        coalesce(
            translation.product_category_name_english,
            products.product_category_name,
            'unknown'
        ) as varchar
    )                                                                             as category_name,
    cast(products.product_weight_g as number(10,0))                               as weight_g,
    cast(
        products.product_length_cm * products.product_height_cm * products.product_width_cm
        as number(10,0)
    )                                                                             as volume_cm3

from products
left join translation
    on translation.product_category_name = products.product_category_name
