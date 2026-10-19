-- 1 行 = 注文に対する支払い 1 回
--
-- 金額は合計したときに誤差が出ないよう、FLOAT64 ではなく NUMERIC にする (元データは小数点以下 2 桁まで)。

with source as (
    select * from {{ source('olist', 'order_payments') }}
),

renamed as (
    select
        order_id,
        cast(payment_sequential as int64) as payment_sequential,
        payment_type,
        cast(payment_installments as int64) as payment_installments,
        cast(payment_value as numeric) as payment_value
    from source
)

select * from renamed
