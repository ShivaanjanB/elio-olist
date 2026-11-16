{#
  A surrogate key: one 32-character hash built from the natural key column(s), so a dimension or fact has a single,
  stable key column to join on.
#}
{% macro generate_surrogate_key(field_list) -%}
    md5(
    {%- for field in field_list %}
        coalesce(cast({{ field }} as varchar), '_null_')
        {%- if not loop.last %} || '-' || {% endif -%}
    {%- endfor %}
    )
{%- endmacro %}
