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

)

select * from typed
