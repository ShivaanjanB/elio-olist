with source as (

    select * from {{ source('olist', 'products') }}

),

typed as (

    select
        cast(product_id as varchar(32))                           as product_id,
        product_category_name,
        -- the source misspells these two as "lenght"; fixed once, here (D06)
        {{ olist_integer('product_name_lenght') }}                as product_name_length,
        {{ olist_integer('product_description_lenght') }}         as product_description_length,
        {{ olist_integer('product_photos_qty') }}                 as product_photos_qty,
        {{ olist_integer('product_weight_g') }}                   as product_weight_g,
        {{ olist_integer('product_length_cm') }}                  as product_length_cm,
        {{ olist_integer('product_height_cm') }}                  as product_height_cm,
        {{ olist_integer('product_width_cm') }}                   as product_width_cm,

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
        partition by product_id
        order by _loaded_at desc, _source_file desc, _source_row desc
    ) = 1

)

select * from deduplicated
