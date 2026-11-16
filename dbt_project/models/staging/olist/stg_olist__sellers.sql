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

),

deduplicated as (

    -- One row per key. If a file were ever loaded twice, the newest load wins, and a tie is broken by file and row
    -- number, so the choice never depends on the order Snowflake reads the rows.
    select *
    from typed
    qualify row_number() over (
        partition by seller_id
        order by _loaded_at desc, _source_file desc, _source_row desc
    ) = 1

)

select * from deduplicated
