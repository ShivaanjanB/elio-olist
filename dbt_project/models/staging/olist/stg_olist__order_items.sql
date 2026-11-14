with source as (

    select * from {{ source('olist', 'order_items') }}

),

typed as (

    select
        cast(order_id as varchar(32))                      as order_id,
        {{ olist_integer('order_item_id') }}               as order_item_id,
        cast(product_id as varchar(32))                    as product_id,
        cast(seller_id as varchar(32))                     as seller_id,
        {{ olist_timestamp('shipping_limit_date') }}       as shipping_limit_date,
        {{ olist_money('price') }}                         as price,
        {{ olist_money('freight_value') }}                 as freight_value,

        _source_file,
        _source_row,
        _loaded_at

    from source

),

deduplicated as (

    -- One row per key. If a file were ever loaded twice, the newest load wins, and a tie is broken by file and row
    -- number, so the choice never depends on the order Snowflake reads the rows. No key repeats today (the
    -- raw_keys_are_unique test reports it if one does), so this removes nothing.
    select *
    from typed
    qualify row_number() over (
        partition by order_id, order_item_id
        order by _loaded_at desc, _source_file desc, _source_row desc
    ) = 1

)

select * from deduplicated
