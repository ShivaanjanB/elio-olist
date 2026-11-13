with source as (

    select * from {{ source('olist', 'sellers') }}

),

typed as (

    select
        cast(seller_id as varchar(32))                  as seller_id,
        cast(seller_zip_code_prefix as varchar(5))      as seller_zip_code_prefix,
        seller_city,
        cast(seller_state as varchar(2))                as seller_state,

        _source_file,
        _source_row,
        _loaded_at

    from source

)

select * from typed
