-- 1 行 = 注文ごとの顧客情報 (customer_id は注文ごとに発行される)
--
-- 元データは型・表記ともに整っているため、列を選ぶだけにする。
-- 郵便番号は数値ではなく識別子のため、STRING のままにする。

with source as (
    select * from {{ source('olist', 'customers') }}
),

renamed as (
    select
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state
    from source
)

select * from renamed
