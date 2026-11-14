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

),

deduplicated as (

    -- One row per key. If a file were ever loaded twice, the newest load wins, and a tie is broken by file and row
    -- number, so the choice never depends on the order Snowflake reads the rows. No key repeats today (the
    -- raw_keys_are_unique test reports it if one does), so this removes nothing.
    select *
    from typed
    qualify row_number() over (
        partition by order_id, payment_sequential
        order by _loaded_at desc, _source_file desc, _source_row desc
    ) = 1

)

select * from deduplicated
