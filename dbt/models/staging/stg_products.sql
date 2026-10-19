-- 1 行 = 1 商品
--
-- 元データの列名のスペルミス (lenght) を直す。数値の列はすべて整数のため INT64 にする。
-- カテゴリ名はポルトガル語のまま。英語名との結合は mart で行う (staging では結合しない)。

with source as (
    select * from {{ source('olist', 'products') }}
),

renamed as (
    select
        product_id,
        product_category_name,
        cast(product_name_lenght as int64) as product_name_length,
        cast(product_description_lenght as int64) as product_description_length,
        cast(product_photos_qty as int64) as product_photos_qty,
        cast(product_weight_g as int64) as product_weight_g,
        cast(product_length_cm as int64) as product_length_cm,
        cast(product_height_cm as int64) as product_height_cm,
        cast(product_width_cm as int64) as product_width_cm
    from source
)

select * from renamed
