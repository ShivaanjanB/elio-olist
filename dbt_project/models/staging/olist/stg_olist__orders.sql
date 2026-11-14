with source as (

    select * from {{ source('olist', 'orders') }}

),

typed as (

    select
        cast(order_id as varchar(32))                                  as order_id,
        cast(customer_id as varchar(32))                               as customer_id,
        order_status,
        {{ olist_timestamp('order_purchase_timestamp') }}              as order_purchase_timestamp,
        {{ olist_timestamp('order_approved_at') }}                     as order_approved_at,
        {{ olist_timestamp('order_delivered_carrier_date') }}          as order_delivered_carrier_date,
        {{ olist_timestamp('order_delivered_customer_date') }}         as order_delivered_customer_date,
        {{ olist_timestamp('order_estimated_delivery_date') }}         as order_estimated_delivery_date,

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
        partition by order_id
        order by _loaded_at desc, _source_file desc, _source_row desc
    ) = 1

)

select * from deduplicated
