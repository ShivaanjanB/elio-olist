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

)

select * from typed
