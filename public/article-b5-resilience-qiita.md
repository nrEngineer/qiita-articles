---
title: Resilience Modeling ― 障害シナリオを仕様に書く
tags:
  - 障害対応
  - SRE
  - SFAD
  - AI駆動開発
  - ClaudeCode
private: true
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---

## TL;DR

- デグレや連鎖障害を **仕様段階で予防** するのが Resilience Modeling
- `threat.md` が **悪意による脅威**、`resilience.md` は **事故による障害** を扱う姉妹ファイル
- 必ず扱う 4 カテゴリ: **外部依存障害 / 内部エラー / リソース枯渇 / データ破損**
- Timeout / Retry / Fallback / Circuit Breaker を仕様に書き、実装時に参照する
- Art-04 で紹介した「デグレ11回」事件は、resilience.md があれば仕様段階で大半を防げた
- 入門版サイズは 100〜150行。深掘り (Chaos Engineering連携、SLO設計、3プロジェクト適用例) は note 有料版 ¥500

## この記事でできること

| やりたいこと | 対応セクション |
|---|---|
| 障害対応を仕様段階で書く理由を理解したい | なぜ仕様段階か |
| 必ず扱う4カテゴリを知りたい | 基本の4カテゴリ |
| Retry/Timeout/Fallback/CircuitBreaker の書き方 | 4パターン詳解 |
| 最小の resilience.md が欲しい | 注文作成サンプル |
| よくある失敗を避けたい | よくある失敗 |

---

Art-04 (3/2 公開) で紹介した **デグレ11回事件**、その 7 件は「リトライすると二重実行される」「Timeout が無くて60秒ハング」「DB 落ちたら全機能停止」という **障害時の振る舞いの仕様漏れ** でした。

テストでデグレを検出するのは大事ですが、**仕様段階で「障害が起きたら何が起きるか」を書く** のが先です。SFAD cycle の第4 Phase で埋める `resilience.md` が、その役割を担います。

この記事では、Resilience Modeling の基本 4 カテゴリ、代表的な 4 パターン (Retry / Timeout / Fallback / Circuit Breaker)、最小 resilience.md のサンプルを書きます。

---

## なぜ仕様段階で障害を書くのか

テスト段階で障害ケースを追加しようとすると:

- 「どの障害パターンをテストすべきか」が網羅できない
- 実装が障害対応前提になっていないので、テストを追加しても通らない
- 「とりあえず動いた」で本番投入 → 事故

仕様段階で書くメリット:

1. **実装者 (AI 含む) が最初から障害対応コードを書く**
2. **QA が網羅的なシナリオテストを設計できる**
3. **SRE が事前に監視・アラートを整備できる**

仕様の 100 行は、本番事故の 1 件を防ぐ。

---

## 基本の4カテゴリ

resilience.md で必ず扱う障害カテゴリは以下の4つです。

### カテゴリ1: 外部依存障害

- DB、キャッシュ、外部 API、メッセージキュー、外部ストレージ
- パターン: Timeout / 不達 / 部分的不達 / 認証失敗 / レート制限超過

### カテゴリ2: 内部エラー

- 想定外の例外、null/undefined、panic
- パターン: データ異常 / ロジックバグ / 境界値超過

### カテゴリ3: リソース枯渇

- メモリ、接続プール、ディスク、ファイルディスクリプタ
- パターン: スパイク / 漏れ / Quota 超過

### カテゴリ4: データ破損

- 部分的書き込み失敗、整合性崩壊、非同期反映ラグ
- パターン: Write after failure / 複製ラグ / キャッシュ不整合

1機能につき、**この4カテゴリそれぞれについて「何が起きるか / どう対応するか / ユーザーに何を見せるか」** を書きます。

---

## 4パターン詳解

障害対応の実装パターンとして、以下の4つを resilience.md に書きます。

### パターン1: Timeout (死なないために)

```markdown
## Timeout 設定

### 外部 API: Stripe
- 接続 Timeout: 3秒
- 読み込み Timeout: 10秒
- 合計最大: 15秒
- 超過時: 504 Gateway Timeout を返し、ユーザーに「しばらく待ってから再試行」

### DB: PostgreSQL
- クエリ Timeout: 5秒 (statement_timeout)
- トランザクション Timeout: 10秒
- 超過時: トランザクションロールバック、503 Service Unavailable
```

実装 (Python + tenacity):

```python
from tenacity import retry, stop_after_delay
import httpx

@retry(stop=stop_after_delay(15))
async def call_stripe(...):
    async with httpx.AsyncClient(timeout=httpx.Timeout(connect=3.0, read=10.0)) as client:
        return await client.post(...)
```

### パターン2: Retry (一時的失敗への対応)

```markdown
## Retry 戦略

### Stripe API
- 最大試行: 3回
- バックオフ: exponential (0.5s, 1s, 2s)
- Retry 対象: 5xx エラー、Network エラー、Timeout
- Retry 対象外: 4xx (特に 400, 401, 403, 422)
- 冪等性: Idempotency-Key ヘッダー必須

### DB
- Deadlock: 自動再試行 1 回
- Connection Lost: connection pool から新規取得して 1 回再試行
```

実装 (TypeScript + p-retry):

```typescript
import pRetry from "p-retry";

await pRetry(
  () => stripe.charges.create(payload, { idempotencyKey: key }),
  {
    retries: 3,
    minTimeout: 500,
    factor: 2,
    onFailedAttempt: (e) => {
      if (e.response?.status >= 400 && e.response?.status < 500) throw e;
    },
  }
);
```

### パターン3: Fallback (全部ダメなときの退却)

```markdown
## Fallback 戦略

### 在庫サービス不達時
- Fallback: キャッシュから最終既知の在庫を返す
- ユーザー表示: 「在庫情報は最新ではない可能性があります」(stale_warning 表示)
- 記録: `stale_inventory_used` メトリクスをインクリメント

### 画像解析 AI 不達時
- Fallback: 画像解析を非同期キューに積み、ユーザーには「結果は後ほど通知」を返す
- 再試行: バックグラウンドで10分後に retry
```

### パターン4: Circuit Breaker (連鎖障害の遮断)

```markdown
## Circuit Breaker

### 在庫サービス
- 閾値: 直近 20 リクエストで 50% 失敗
- 発動時: 30秒間は全リクエストを即座に Fallback に回す
- 半開き復帰: 30秒後に 1 リクエストだけ通して成功すれば閉じる
```

実装 (Python + pybreaker):

```python
import pybreaker

inventory_breaker = pybreaker.CircuitBreaker(
    fail_max=10,
    reset_timeout=30,
)

@inventory_breaker
async def get_inventory(product_id):
    return await inventory_api.get(product_id)

try:
    stock = await get_inventory(product_id)
except pybreaker.CircuitBreakerError:
    stock = await get_cached_inventory(product_id)  # Fallback
```

---

## 最小 resilience.md サンプル (注文作成機能)

実際に書く粒度はこれくらいです。

```markdown
# resilience.md: 注文作成機能

## 1. 外部依存障害

### Stripe (決済)
- Timeout: 3s / 10s (合計15s)
- Retry: 3回、exponential backoff
- Fallback: なし (決済は失敗を明示、ユーザーに再試行を促す)
- Idempotency-Key: 必須

### 在庫サービス
- Timeout: 2s
- Retry: 2回
- Fallback: キャッシュから最終既知在庫 + stale_warning フラグ
- Circuit Breaker: fail_max=10, reset=30s

### ウェルカムメール (SendGrid)
- Timeout: 5s
- Retry: 非同期キューで最大24時間
- Fallback: なし (メール失敗は注文成立をブロックしない)

## 2. 内部エラー

### 想定外例外
- 全エンドポイントを middleware で try/except
- ログ: 構造化ログに request_id/user_id/stack trace
- レスポンス: 500 Internal Server Error + "request_id: xxx"

### データ整合性違反 (unique 制約など)
- 409 Conflict
- メッセージ: "該当リソースは既に存在します"

## 3. リソース枯渇

### DB 接続プール枯渇
- レスポンス: 503 Service Unavailable
- 自動スケールアウト: 5分以内に新規インスタンス追加
- アラート: Slack #alert-ops

### メモリ超過 (画像解析など)
- 事前制限: 画像は 10MB 以下
- 超過時: 413 Payload Too Large

## 4. データ破損

### 部分的書き込み失敗
- トランザクション境界: OrderService.create_order() 全体
- 失敗時: 全ロールバック (Stripe charge も refund)
- Compensating Transaction: Stripe refund が失敗したら手動対応キュー

### キャッシュ不整合
- TTL: 5分
- 書き込み後の cache invalidation: order作成直後に該当 user の order list cache を削除

## 5. 監視項目

- order_creation_duration_p99: < 3s
- stripe_retry_count: > 10/min で警告
- inventory_breaker_state: open が 1分以上続いたらアラート
- db_pool_usage: > 80% で警告
```

これで 120 行前後。書き切れる範囲で保守可能です。

---

## よくある失敗

### 失敗1: Retry を書いたが冪等性がない

外部 API を retry する前に、**Idempotency-Key** や **DB の unique 制約 + ON CONFLICT** で冪等性を確保する。そうでないと二重課金・二重作成が発生。

### 失敗2: Fallback で stale データを返したのに表示がそのまま

ユーザーに「これは古いデータかもしれない」を表示する UI がないと、気づかないまま誤操作される。フラグとして必ず返す仕様にする。

### 失敗3: Circuit Breaker が開きっぱなし

reset_timeout 後に復帰テストを 1 リクエスト走らせる "half-open" 状態を実装しないと、外部依存が回復しても通らないまま。

### 失敗4: Timeout と Retry の累積時間を考えていない

Timeout 5s × Retry 3回 = 最大15秒ハング。ユーザーが待てる時間を超えてしまう。**総最大時間** を明記する。

---

:::note info
この記事は Qiita 無料の入門版です。

- Chaos Engineering との連携手順
- SLO (Service Level Objective) 設計との対応
- 3プロジェクト実例の resilience.md 全文 (計1800行)
- Retry library 選定ガイド (Python/TS/Go/Rust)

これらは note 有料版「Resilience Modeling 完全ガイド ― 本番で壊れない仕様の作り方」(¥500) で公開しています。
:::

---

## まとめ

- `resilience.md` は `threat.md` の姉妹ファイル。脅威ではなく **障害** を扱う
- 必ず扱う 4カテゴリ: 外部依存 / 内部エラー / リソース枯渇 / データ破損
- 4パターン: Timeout / Retry / Fallback / Circuit Breaker を各カテゴリに割り当てる
- 入門版サイズは 100〜150行。それ以上は肥大化のサイン
- 仕様段階で書くから、実装者 (AI含む) が最初から障害対応コードを書く
- Art-04 (デグレ11回) の多くは resilience.md があれば仕様段階で防げた

「リトライを書くことを忘れた」を個人のミスにしないために、**仕様ファイルにテンプレとして入れておく** のが一番確実です。

---

## 次の記事: 新SFAD cycle の 8 Phase を一周した記録 ― 認証機能を題材に (6/8 公開予定)

ここまで B1 (4ファイル分割) / B2 (攻撃者視点) / B3 (13ルール) / B4 (Threat) / B5 (Resilience) を紹介してきました。次回は **これらを統合した 8 Phase を、認証機能で実際に一周した実録** を公開します。各 Phase での AI 対話ログ、生成された4仕様ファイル、テストコード、実装コードまで全部見せます。
