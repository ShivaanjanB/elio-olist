with source as (

    select * from {{ source('olist', 'order_payments') }}

),

typed as (

    select
        cast(order_id as varchar(32))                      as order_id,
        {{ olist_integer('payment_sequential') }}          as payment_sequential,
        payment_type,
        {{ olist_integer('payment_installments') }}        as payment_installments,
        {{ olist_money('payment_value') }}                 as payment_value,

        _source_file,
        _source_row,
        _loaded_at

    from source

)

select * from typed
