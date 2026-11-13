{#
  Use the schema name a model asks for EXACTLY (STAGING, INTERMEDIATE, MARTS), instead of dbt's default
  of gluing it onto the target schema (which would give STAGING_STAGING). Decision D02.
  A model with no schema of its own falls back to the target's schema.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema | trim }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
