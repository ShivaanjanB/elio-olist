with source as (

    select * from {{ source('olist', 'product_category_name_translation') }}

),

typed as (

    select
        product_category_name,
        product_category_name_english,

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
        partition by product_category_name
        order by _loaded_at desc, _source_file desc, _source_row desc
    ) = 1

)

select * from deduplicated
