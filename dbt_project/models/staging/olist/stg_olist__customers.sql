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

)

select * from typed
