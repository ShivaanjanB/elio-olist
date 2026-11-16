{#
  One row per seller (D23). Taken straight from staging: a seller is already one row per seller_id there.
#}
with sellers as (

    select * from {{ ref('stg_olist__sellers') }}

)

select
    cast({{ generate_surrogate_key(['seller_id']) }} as varchar(32))   as seller_sk,
    cast(seller_id as varchar(32))                                      as seller_id,
    cast(seller_zip_code_prefix as varchar(5))                          as zip_code_prefix,
    cast(seller_city as varchar)                                        as city,
    cast(seller_state as varchar(2))                                    as state

from sellers
