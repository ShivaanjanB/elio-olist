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

)

select * from typed
