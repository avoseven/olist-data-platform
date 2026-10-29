# 顧客特徴量の仕様

顧客セグメンテーションの入力になる `customer_features` (1 行 = 1 人) の、特徴量ごとの定義をまとめた仕様書。
設計の原則は [ADR 007](decisions/007_customer_feature_principles.md)、前提となる mart の方針は [ADR 006](decisions/006_mart_design.md) を参照。

件数は 2026-10-21 時点の staging のデータで集計したもの。

## 前提

| 項目 | 内容 | 根拠 |
|---|---|---|
| 対象の注文 | `order_status = 'delivered'` の注文 | ADR 006 の A |
| 対象の顧客 | delivered の注文を 1 件以上持つ `customer_unique_id` (93,358 人) | ADR 006 の A |
| 基準日 | delivered の注文の最後の購入日 (2018-08-29)。`reference_date` として列に持つ | ADR 006 の D |
| 入力 | `fct_delivered_orders` (1 行 = 1 注文) と、顧客 × カテゴリの集計 | ADR 007 の原則 1 |
| 金額 | 明細から計算する。購入金額は価格だけ、送料は別 | ADR 006 の B |
| レビュー | 注文ごとに採用した 1 件を使う。顧客単位では `review_id` の重複を除く | ADR 006 の C |
| 不整合な値 | 修正せず、それを使う特徴量でだけ NULL として扱う | ADR 006 の E |

## 区分

| 区分 | 内容 |
|---|---|
| ① 基本 | 購入回数、購入金額、最終購入からの日数など |
| ② 行動の違い | 購買行動の中身の違いを捉えるもの |
| ③ 慎重に検討 | NULL が多いもの、互いに似た情報を表すもの、顧客の行動より注文の条件の影響が強いもの |
| ④ 解釈用 | クラスタリングには入力せず、クラスタを説明するために使う属性 |

区分①〜③のクラスタリングへの採用は、データ確認の後に判断する。

## 一覧

| 観点 | 特徴量 | 区分 | 型 | NULL になる顧客 |
|---|---|:---:|---|---:|
| 金額 | [`total_items_amount`](#total_items_amount) | ① | NUMERIC | 0 |
| 金額 | [`avg_order_items_amount`](#avg_order_items_amount) | ③ | NUMERIC | 0 |
| 金額 | [`avg_item_price`](#avg_item_price) | ② | NUMERIC | 0 |
| 金額 | [`freight_ratio`](#freight_ratio) | ③ | NUMERIC | 0 |
| 時期 | [`order_count`](#order_count) | ① | INT64 | 0 |
| 時期 | [`days_since_last_purchase`](#days_since_last_purchase) | ① | INT64 | 0 |
| 時期 | [`days_since_first_purchase`](#days_since_first_purchase) | ③ | INT64 | 0 |
| 商品 | [`item_count`](#item_count) | ② | INT64 | 0 |
| 商品 | [`distinct_category_count`](#distinct_category_count) | ③ | INT64 | 1,260 |
| 商品 | [`top_category`](#top_category) | ④ | STRING | 1,260 |
| 支払い | [`credit_card_order_ratio`](#credit_card_order_ratio) | ② | FLOAT64 | 1 |
| 支払い | [`avg_card_installments`](#avg_card_installments) | ③ | FLOAT64 | 21,333 |
| 支払い | [`has_used_voucher`](#has_used_voucher) | ③ | BOOL | 1 |
| 支払い | [`main_payment_type`](#main_payment_type) | ④ | STRING | 1 |
| 体験 | [`avg_review_score`](#avg_review_score) | ② | FLOAT64 | 604 |
| 体験 | [`has_review_comment`](#has_review_comment) | ③ | BOOL | `avg_review_score` と同じ |
| 体験 | [`avg_delivery_days`](#avg_delivery_days) | ③ | FLOAT64 | 8 |
| 体験 | [`avg_delivery_delay_days`](#avg_delivery_delay_days-と-late_delivery_ratio) | ③ | FLOAT64 | 8 |
| 体験 | [`late_delivery_ratio`](#avg_delivery_delay_days-と-late_delivery_ratio) | ③ | FLOAT64 | 8 |
| 地域 | [`customer_state`](#customer_state) | ④ | STRING | 0 |
| - | `reference_date` | - | DATE | 0 |

`avg_delivery_delay_days` と `late_delivery_ratio` は、同じ配送の実績を違う方法で要約した比較候補であり、データ確認の後にどちらか一方を選ぶ。

## クラスタリングへの採用

データ確認の結果、K-means に入力する特徴量を次のとおり決めた。理由は [ADR 008](decisions/008_feature_selection.md) を参照。
不採用の特徴量も、クラスタの解釈や見直しに使うため、`customer_features` の列としては残す。

| 採用状況 | 特徴量 |
|---|---|
| 採用 | `total_items_amount` (対数変換), `order_count`, `days_since_last_purchase`, `item_count`, `credit_card_order_ratio`, `avg_review_score`, `has_review_comment`, `late_delivery_ratio` |
| 保留 | `avg_card_installments` |
| 不採用 | `avg_order_items_amount`, `avg_item_price`, `freight_ratio`, `days_since_first_purchase`, `distinct_category_count`, `has_used_voucher`, `avg_delivery_days`, `avg_delivery_delay_days` |
| 解釈用 (区分④) | `top_category`, `main_payment_type`, `customer_state` |

> その後、K-means の結果から、最終的なセグメントはクラスタリングではなくルールで作ることにした ([ADR 010](decisions/010_rule_flags_and_clustering_scope.md)・[011](decisions/011_segmentation_purpose_and_roles.md))。
> セグメントの分類には `order_count` と `total_items_amount` だけを使い、ほかの特徴量はセグメントどうしの比較や解釈に使う ([ADR 012](decisions/012_segment_definition.md))。

## 定義

### 金額

#### `total_items_amount`

- **意味**: 商品にいくら使ったか (購入金額)
- **定義**: 注文ごとの `items_amount` (明細の価格の合計) を、顧客の注文すべてについて合計する
- **NULL**: ならない
- **備考**: 偏りが大きいと考えられるため、データ確認で分布を見て、必要なら対数変換などを検討する

#### `avg_order_items_amount`

- **意味**: 1 回の購入あたり、商品にいくら使うか
- **定義**: 注文ごとの `items_amount` を、注文間で平均する (注文ごとの値の平均)
- **NULL**: ならない
- **備考**: 1 回しか購入していない顧客では `total_items_amount` と同じ値になるため、区分③

#### `avg_item_price`

- **意味**: 高い商品を買う傾向があるか
- **定義**: `items_amount` の合計 ÷ `item_count` の合計 (合計どうしの比。商品 1 個あたりの価格)
- **NULL**: ならない (delivered の注文はすべて明細を持つ)
- **備考**: `total_items_amount` との関係をデータ確認で見る

#### `freight_ratio`

- **意味**: 支払った金額のうち、送料がどれくらいを占めるか
- **定義**: `freight_amount` の合計 ÷ `total_amount` の合計 (合計どうしの比)
- **値の範囲**: 0 以上 1 未満
- **NULL**: ならない (価格は 0 より大きいため、分母は必ず正)
- **0**: 送料無料の注文しかない顧客 (330 人)
- **合計どうしの比を選んだ理由**:
  - 金額に関する特徴量であり、購入金額も合計で計算するため、全体として支払った金額のうち送料がどれくらいかを表す。
  - 注文ごとの割合を平均すると、送料の割合が高い少額の注文の影響が大きくなる。送料は顧客の判断より注文の条件で決まる部分が大きいと考えられるため、1 回ごとの割合を同じ重みで平均する意味は薄い。
- **補足**: 1 回しか購入していない顧客では、注文ごとの割合の平均と同じ値になる。リピーター 2,801 人に限ると、2 つの計算方法の相関は 0.9415、差の中央値は 0.6 ポイント、上位 10% では 6.2 ポイント以上の差がある。
- **備考**: 顧客の行動より、地域・商品の大きさ・配送条件の影響が強い可能性があるため、区分③

### 時期

#### `order_count`

- **意味**: 購入回数
- **定義**: delivered の注文の数
- **NULL**: ならない (対象の顧客は全員 1 以上)
- **備考**: 約 97% の顧客が 1。リピーターを捉えるために残す

#### `days_since_last_purchase`

- **意味**: 最後に購入してから何日経っているか
- **定義**: `reference_date` − 最後の注文の購入日 (日付どうしの差)
- **NULL**: ならない
- **備考**:
  - 現在の顧客の状況ではなく、データの観測期間の終わり (基準日 2018-08-29) 時点での最近性を表す
  - データの最後の 1 週間ほどは不完全なため、0〜数日の顧客は実際より少なく見えている可能性がある (ADR 006 の D)

#### `days_since_first_purchase`

- **意味**: 最初に購入してから何日経っているか (利用期間)
- **定義**: `reference_date` − 最初の注文の購入日 (日付どうしの差)
- **NULL**: ならない
- **備考**: 1 回しか購入していない顧客では `days_since_last_purchase` と同じ値になるため、区分③

### 商品

#### `item_count`

- **意味**: 購入した商品の個数 (まとめ買いをするか)
- **定義**: 注文ごとの明細の行数を合計する。数量の列はなく、同じ商品を複数個買うと明細が複数行になるため、行数が個数になる
- **NULL**: ならない

#### `distinct_category_count`

- **意味**: いろいろなカテゴリの商品を買うか
- **入力**: 顧客 × カテゴリの集計
- **定義**: カテゴリがわかる商品の、カテゴリの種類の数。カテゴリが NULL の明細は数えない
- **NULL**: カテゴリがわかる商品を 1 つも買っていない顧客 (1,260 人)。0 にはしない
- **備考**: 2 種類以上の顧客は 2,161 人 (カテゴリがわかる顧客の約 2.35%) で、ほとんどの顧客が 1。顧客を分ける力は限定的と予想されるため、分布を確認して採用を判断する

#### `top_category`

- **意味**: 主に買うカテゴリ (クラスタの解釈用)
- **入力**: 顧客 × カテゴリの集計 (カテゴリが NULL の明細は除く)
- **定義**: 次の順に並べた先頭のカテゴリ
  1. そのカテゴリの商品を含む注文の数が多い順。同じ注文に同じカテゴリの明細が複数あっても、その注文は 1 回だけ数える
  2. そのカテゴリの明細の `price` の合計が大きい順
  3. カテゴリ名 (ポルトガル語の `product_category_name`) の辞書順
- **出力する値**: 英語名。英訳がないカテゴリは、ポルトガル語名で代用する
- **NULL**: カテゴリがわかる商品を 1 つも買っていない顧客 (1,260 人)
- **補足**: 複数のカテゴリを買った 2,161 人のうち、注文の数を基準にするか個数を基準にするかで代表のカテゴリが変わるのは 140 人。採用の理由は、解釈しやすく再現できるルールであることとする

### 支払い

#### `credit_card_order_ratio`

- **意味**: 支払い方法として、カードを選ぶ傾向があるか
- **注文単位**: 支払いにクレジットカードが含まれていれば 1、含まれていなければ 0。有効な支払い情報がない注文は NULL
- **顧客単位**: 注文単位の値を、NULL を除いて注文間で平均する (カードを使った注文の割合)
- **0**: カードを使った注文はないが、ほかの支払いの記録はある顧客 (21,330 人)
- **NULL**: 有効な支払いの記録がない顧客 (1 人)
- **注文数を基準にした理由**: 金額を基準にすると、カードとほかの支払い方法を併用した場合に、カード以外の支払い金額の影響を受ける。2 つの基準で 50 ポイント以上違う顧客は 1,435 人で、該当する注文 (1,454 件) はすべてカードとバウチャーの併用だった。金額を基準にすると「カードを選ぶか」に「バウチャーをどれだけ使ったか」が混ざる
- **備考**: 0 と 1 以外の値をとる顧客は 266 人だけ。割合のまま使うか、フラグとして扱うかは分布を見て判断する

#### `avg_card_installments`

- **意味**: カードを使った注文で、何回払いを選ぶ傾向があるか
- **注文単位**: その注文で使われたカード払いの最大の分割回数 (その注文の代表的な分割回数ではない)。対象は分割回数が 1 以上のクレジットカードの支払い
- **注文単位で NULL**: カードの支払いがない注文、分割回数が 0 のカード払いしかない注文、支払いのレコードがない注文
- **顧客単位**: 注文単位の値を、NULL を除いて注文間で平均する
- **NULL**: カードを使っていないか、有効な分割回数が得られなかった顧客 (21,333 人、22.9%)
- **カードの支払いだけで計算する理由**: 分割払いができるのはクレジットカードだけで、ほかの支払い方法は常に 1 回である。これを含めると、「分割払いを使うか」と「カードを使うか」という別の行動が混ざる。カードを使うかどうかは `credit_card_order_ratio` で表す
- **備考**:
  - クラスタリングでは NULL をそのまま扱えないため、補完、除外、別の方法を検討する (レビューの NULL と同じ方法で処理する必要はない)
  - `credit_card_order_ratio` が 0 の顧客では、この特徴量は分割回数の情報を持たない。両方を使う場合は、この関係を確認する

#### `has_used_voucher`

- **意味**: バウチャーで支払ったことがあるか
- **注文単位**: `payment_type = 'voucher'` かつ `payment_value > 0` の支払いが 1 件以上あれば TRUE、なければ FALSE。支払いのレコードがない注文は NULL
- **顧客単位**: 1 つの注文でも TRUE なら TRUE。支払いの記録があり、すべて FALSE なら FALSE。有効な支払いの記録がなければ NULL
- **TRUE**: 3,591 人 (3.8%)
- **NULL**: 1 人
- **正の支払額を基準にした理由**: 支払いのレコードがあることではなく、バウチャーによる支払いが実際に発生したことを表すため。金額が 0 のバウチャーのレコード (4 件) が仕様上のものか異常かは断定しない。現在のデータでは、レコードの有無を基準にしても結果が変わる顧客はいない

#### `main_payment_type`

- **意味**: 主に使う支払い方法 (クラスタの解釈用)
- **定義**: 顧客ごとに、支払い方法別に「その方法を使った注文の数」と「その方法で払った金額の合計」を出し、次の順に並べた先頭
  1. その方法を使った注文の数が多い順
  2. その方法で払った金額の合計が大きい順
  3. 支払い方法の名前の辞書順
- **複数の方法を含む注文**: 各方法に 1 注文として数える。そのため、方法別の注文の数の合計は、顧客の注文の数と一致しないことがある
- **NULL**: 有効な支払いの記録がない顧客 (1 人)

### 体験

#### `avg_review_score`

- **意味**: 購入体験への満足度
- **注文単位**: ADR 006 の C で採用したレビューのスコア。採用したレビューがなければ NULL
- **顧客単位**: `review_id` の重複を除いてから平均する (同じ回答を 1 回だけ数える)
- **NULL**: 採用したレビューが 1 つもない顧客 (604 人)。ADR 006 の C に記載した 603 人は、時系列が矛盾したレビュー (6 件) を除く前の人数で、除いたことで 1 人増えている
- **前提**: 同じ `review_id` は、顧客・スコア・内容がすべて同じ。この前提を dbt のテストで検証する

#### `has_review_comment`

- **意味**: レビューで、自由記述の意見を書く傾向があるか
- **注文単位**: 採用したレビューのタイトルか本文に、空白以外の文字があれば TRUE。どちらにもなければ FALSE。採用したレビューがなければ NULL
- **顧客単位**: 1 つの注文でも TRUE なら TRUE。採用したレビューがあり、すべて FALSE なら FALSE。採用したレビューがなければ NULL
- **NULL**: `avg_review_score` が NULL の顧客と同じ
- **タイトルも判定に含める理由**: タイトルだけのレビュー (1,704 件) も、「Ótimo (最高)」「Recomendo (おすすめ)」のような短い感想になっている
- **空白の扱い**: staging でコメントの前後の空白を除き、空白だけのものは NULL にしている。そのため mart では、NULL でなければ空白以外の文字があると判定できる
- **観察**: 本文があるレビューのスコアの平均は 3.77、本文がないレビューは 4.42。`avg_review_score` と両方を使うかは、相関やクラスタリングへの影響を見て判断する

#### `avg_delivery_days`

- **意味**: 購入から配達までにかかる日数
- **注文単位**: `DATE(order_delivered_customer_at) − DATE(order_purchased_at)`。配達日時がない注文は NULL
- **顧客単位**: NULL を除いて注文間で平均する
- **NULL**: 配達日時がある注文を持たない顧客 (8 人)
- **備考**: 中央値 10 日に対して最大 210 日と、右に長く伸びた分布。分布と外れ値の影響を確認し、必要なら対数変換を検討する。外れ値は自動的に除外しない。顧客の行動より、配送先や物流の影響が強い可能性があるため、区分③

#### `avg_delivery_delay_days` と `late_delivery_ratio`

同じ配送の実績を違う方法で要約した比較候補。データ確認の後に、どちらか一方を選ぶ。

| | `avg_delivery_delay_days` | `late_delivery_ratio` |
|---|---|---|
| 意味 | 配送予定日と比べて、どれくらい早く・遅く届くか | 配送の遅れを経験したか |
| 注文単位 | `DATE(order_delivered_customer_at) − order_estimated_delivery_date`。プラスなら遅れ、マイナスなら予定より早い | 配達日が配送予定日より後なら 1、当日以前なら 0 |
| 顧客単位 | NULL を除いて注文間で平均する | NULL を除いて注文間で平均する (0〜1) |
| NULL | 配達日時がある注文を持たない顧客 (8 人) | 同左 |

- 配送予定日は余裕を持って設定されているようで、遅れの中央値は −12 日 (12 日早い)、予定日より遅れた注文は 6.8% だった。遅れの平均は、顧客の体験より配送予定日の設定の長さを主に表す可能性がある。
- 比べる観点は、分布・値の種類の数、NULL の割合、`avg_review_score` との関係、既存の特徴量との重複とする。レビューとの相関が強いほうを、自動的に採用することはしない。

### 地域

#### `customer_state`

- **意味**: 最後の delivered の注文に紐づく顧客情報の州 (クラスタの解釈用)
- **定義**: delivered の注文を、購入日時の降順、次に `order_id` の昇順で並べた先頭の注文について、`stg_customers.customer_state` を取る
- **NULL**: ならない (staging の非欠損テストを前提とする)
- **補足**: 複数の州で注文した顧客は 37 人。最後の購入日時が同じ注文を複数持つ顧客は 246 人いるが、それらの注文で州が違う顧客はいない

## 実装の構成

### 入力

`customer_features` は、次の 3 つの集計から計算する (ADR 007 の原則 1)。

| 入力 | 粒度 | 置き場所 | 使う特徴量 |
|---|---|---|---|
| `fct_delivered_orders` | 1 行 = 1 注文 (delivered のみ) | 独立したモデル (mart) | 下の 2 つ以外のすべて |
| 顧客 × カテゴリの集計 | 1 行 = 顧客 × カテゴリ | `customer_features` の CTE | `top_category`, `distinct_category_count` |
| 顧客 × 支払い方法の集計 | 1 行 = 顧客 × 支払い方法 | `customer_features` の CTE | `main_payment_type` |

2 つの集計を独立したモデル (中間層) にせず CTE にするのは、現時点では `customer_features` でしか使わないためである。
[ADR 002](decisions/002_layer_architecture.md) の「複数の mart で同じ中間処理を使い回すようになったら中間層を追加する」という方針を維持する。
別のモデルからも使うようになった段階で、中間モデルにすることを再検討する。

CTE は単独のモデルとしてテストできないため、次のように検証する。

| 検証の対象 | 検証の方法 |
|---|---|
| 顧客 × カテゴリの粒度 | CTE を `GROUP BY 顧客, カテゴリ` で集計しているため、組み合わせごとに 1 行になることは SQL の構造上保証される。同じ集計をテストで書いても独立した検証にならないため、個別のテストは設けない |
| 顧客 × 支払い方法の粒度 | 同上 (`GROUP BY 顧客, 支払い方法`) |
| 粒度の誤りによる値の重複 | 顧客数・注文数・購入金額を `fct_delivered_orders` と突き合わせる (`assert_customer_features_matches_fct`) |
| `top_category`, `distinct_category_count` | staging から、モデルとは別の書き方 (`row_number`) で再計算し、一致することを確かめる (`assert_top_category_matches_recomputation`) |
| `main_payment_type` | 同上 (`assert_main_payment_type_matches_recomputation`) |

### `fct_delivered_orders` の列

| 種類 | 列 | 定義 | 使う特徴量 |
|---|---|---|---|
| キー | `order_id` | 注文 ID (主キー) | - |
| キー | `customer_unique_id` | 人を識別する ID | 顧客単位への集約 |
| 属性 | `customer_state` | その注文に紐づく顧客情報の州 | `customer_state` |
| 属性 | `order_purchased_at` | 購入日時 | `customer_state` (最後の注文の決定) |
| 属性 | `order_purchase_date` | 購入日 | 最終購入日・最初の購入日、基準日、配送日数 |
| 明細 | `item_count` | 明細の行数 | `item_count`, `avg_item_price` |
| 明細 | `items_amount` | 価格の合計 | 金額の特徴量 |
| 明細 | `freight_amount` | 送料の合計 | `freight_ratio` |
| 明細 | `total_amount` | `items_amount` + `freight_amount` | `freight_ratio` |
| 支払い | `has_credit_card_payment` | カードの支払いがあれば TRUE、なければ FALSE。支払いのレコードがなければ NULL | `credit_card_order_ratio` |
| 支払い | `max_card_installments` | 分割回数が 1 以上のカード払いの最大の分割回数。対象がなければ NULL | `avg_card_installments` |
| 支払い | `has_voucher_payment` | 金額が正のバウチャーの支払いがあれば TRUE、なければ FALSE。支払いのレコードがなければ NULL | `has_used_voucher` |
| レビュー | `review_id` | 採用したレビューの ID。なければ NULL | `avg_review_score` (重複の除去) |
| レビュー | `review_score` | 採用したレビューのスコア。なければ NULL | `avg_review_score` |
| レビュー | `has_review_comment` | 採用したレビューにコメントがあれば TRUE、なければ FALSE。レビューがなければ NULL | `has_review_comment` |
| 配送 | `delivery_days` | 配達日 − 購入日。配達日時がなければ NULL | `avg_delivery_days` |
| 配送 | `delivery_delay_days` | 配達日 − 配送予定日 (プラスなら遅れ)。配達日時がなければ NULL | `avg_delivery_delay_days` |
| 配送 | `is_late_delivery` | 配達日が配送予定日より後なら TRUE、当日以前なら FALSE。配達日時がなければ NULL | `late_delivery_ratio` |

明細・支払い・レビューは、それぞれ注文単位に集約してから結合する (ADR 006)。

## 見送った候補

| 候補 | 見送った理由 |
|---|---|
| 購入した曜日・時間帯の傾向 (週末に購入した注文の割合など) | 1 回しか購入していない顧客では 0 か 1 になり、継続的な傾向を表しにくい。曜日や時間帯の偏りが安定した嗜好なのか偶然なのかを区別しにくい。今の目的に対して優先度が高くない。リピーターの行動を分析する場合は再検討する |
