{#
    モデルを作るデータセット名を決めるマクロ (dbt の標準のマクロを上書きする)。

    dbt の標準では、モデルに schema を指定すると
    「<profiles.yml の schema>_<指定した schema>」というデータセット名になる。
    このプロジェクトでは、指定した名前 (olist_staging, olist_mart) をそのまま使う。
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
