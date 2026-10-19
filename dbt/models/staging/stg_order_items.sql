-- 1 行 = 注文の明細 1 行
--
-- 数量の列はなく、同じ商品を複数個買うと明細が複数行になる。
-- 金額は合計したときに誤差が出ないよう、FLOAT64 ではなく NUMERIC にする (元データは小数点以下 2 桁まで)。

with source as (
    select * from {{ source('olist', 'order_items') }}
),

renamed as (
    select
        order_id,
        cast(order_item_id as int64) as order_item_id,
        product_id,
        seller_id,
        cast(shipping_limit_date as datetime) as shipping_limit_at,
        cast(price as numeric) as price,
        cast(freight_value as numeric) as freight_value
    from source
)

select * from renamed
