with source as (

    select * from {{ source('olist', 'customers') }}

),

typed as (

    select
        cast(customer_id as varchar(32))                as customer_id,
        cast(customer_unique_id as varchar(32))         as customer_unique_id,
        -- text, not a number: 23,995 prefixes start with 0 (D08)
        cast(customer_zip_code_prefix as varchar(5))    as customer_zip_code_prefix,
        customer_city,
        cast(customer_state as varchar(2))              as customer_state,

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
        partition by customer_id
        order by _loaded_at desc, _source_file desc, _source_row desc
    ) = 1

)

select * from deduplicated
