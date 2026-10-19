-- 1 行 = アンケート回答 (review_id) × 対象の注文 (order_id)
--
-- 1 注文に複数のレビューが付くことも、1 つのレビューが複数の注文に紐づくこともある
-- (notebooks/01_order_reviews_duplicates.ipynb)。staging では行を除かず、そのまま残す。

with source as (
    select * from {{ source('olist', 'order_reviews') }}
),

renamed as (
    select
        review_id,
        order_id,
        cast(review_score as int64) as review_score,
        -- 時刻は 00:00:00、またはブラジルの夏時間が始まった日の 01:00:00 のみのため、DATE にする
        cast(cast(review_creation_date as datetime) as date) as review_creation_date,
        cast(review_answer_timestamp as datetime) as review_answered_at,
        -- 前後の空白を除き、空白だけのコメントは NULL にする
        nullif(trim(review_comment_title), '') as review_comment_title,
        nullif(trim(review_comment_message), '') as review_comment_message
    from source
)

select * from renamed
