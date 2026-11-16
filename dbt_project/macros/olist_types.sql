{#
  The type decisions of docs/data_model.md section 4 (D07), written once so every staging model applies them the same
  way.
#}

{#
  Source timestamps look like 2017-10-02 10:56:33, with no time zone, so they stay TIMESTAMP_NTZ (D09).
#}
{% macro olist_timestamp(column) -%}
    to_timestamp_ntz({{ column }}, 'YYYY-MM-DD HH24:MI:SS')
{%- endmacro %}

{# Money: at most 2 decimals in the data (price up to 6,735.00, payment up to 13,664.08). #}
{% macro olist_money(column) -%}
    cast({{ column }} as number(12, 2))
{%- endmacro %}

{# Whole numbers: counts, positions, lengths, weights and sizes. #}
{% macro olist_integer(column) -%}
    cast({{ column }} as number(10, 0))
{%- endmacro %}
