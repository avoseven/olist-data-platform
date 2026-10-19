-- 1 行 = 1 カテゴリ (ポルトガル語名と英語名の対応)
--
-- 元データは整っているため、列を選ぶだけにする。

with source as (
    select * from {{ source('olist', 'product_category_name_translation') }}
),

renamed as (
    select
        product_category_name,
        product_category_name_english
    from source
)

select * from renamed
