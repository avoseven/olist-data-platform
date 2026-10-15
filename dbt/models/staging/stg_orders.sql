-- 1 行 = 1 注文
--
-- 元データの日時にはタイムゾーンの情報がないため、TIMESTAMP (UTC の絶対時刻) ではなく
-- DATETIME に変換する。列名は、DATETIME の列は _at、DATE の列は _date で終わるようにそろえる。

with source as (
    select * from {{ source('olist', 'orders') }}
),

renamed as (
    select
        order_id,
        customer_id,
        order_status,
        cast(order_purchase_timestamp as datetime) as order_purchased_at,
        cast(order_approved_at as datetime) as order_approved_at,
        cast(order_delivered_carrier_date as datetime) as order_delivered_carrier_at,
        cast(order_delivered_customer_date as datetime) as order_delivered_customer_at,
        -- 時刻は常に 00:00:00 のため、DATE にする
        cast(cast(order_estimated_delivery_date as datetime) as date) as order_estimated_delivery_date
    from source
)

select * from renamed
