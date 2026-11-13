{#
  A surrogate key: one 32-character hash built from the natural key column(s), so a dimension or fact has a single,
  stable key column to join on. Same idea and same call shape as dbt_utils.generate_surrogate_key, written locally (D30, D42).

  - Deterministic: the same inputs always give the same key, so a rebuild reproduces the same keys.
  - NULL-safe: a NULL is written as a fixed marker, so a NULL in one column can never collide with an empty string.
  - Delimited: the values are joined with '-', so ('ab', 'c') and ('a', 'bc') give different keys.

  Usage:  {{ generate_surrogate_key(['order_id', 'order_item_id']) }}
#}
{% macro generate_surrogate_key(field_list) -%}
    md5(
    {%- for field in field_list %}
        coalesce(cast({{ field }} as varchar), '_null_')
        {%- if not loop.last %} || '-' || {% endif -%}
    {%- endfor %}
    )
{%- endmacro %}
