---
title: 仕様書を4ファイルに分けたらAIが迷わなくなった ― SFAD cycle 8 Phase 構成
tags:
  - SFAD
  - AI駆動開発
  - ClaudeCode
  - 仕様書
  - BDD
private: true
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---

## TL;DR

- `spec.md` 1枚で書いていた仕様書は、**コンテキストウィンドウと責務混在** の二重苦でAIが迷子になっていた
- SFAD cycle の最新版は、仕様を **4ファイルに分割**: `functional.md` / `threat.md` / `resilience.md` / `plan.md`
- 分割の最大の効果は **「AI に読ませる 1 ファイルの粒度を小さくできる」** こと。認可を考えるときは `threat.md` だけ、リトライを考えるときは `resilience.md` だけを AI に渡せる
- `cycle` コマンドは 8 Phase 化: Example Mapping → 4ファイル生成 → 受け入れテスト → UC TDD → 静的解析
- 並行作業も圧倒的に楽: PO が functional、セキュリティ担当が threat、SRE が resilience を **同時に埋められる**
- 運用してみた結論: 1ファイル 200〜300行に収まる粒度が、AI にとっても人間にとっても読みやすい

## この記事でできること

| やりたいこと | 対応セクション |
|---|---|
| spec.md 1枚だと何が起きるか知りたい | なぜ破綻したか |
| 4ファイルそれぞれの責務を把握したい | 4ファイルの役割 |
| SFAD cycle 8 Phase のマッピングを知りたい | 8 Phase との対応 |
| チームで並行して仕様を書きたい | 並行作業のメリット |
| このバグはどのファイルの不備かを判定したい | レビュー練習問題 |

---

ある日、仕様書として `spec.md` 1枚を AI に渡して「この通りに実装して」と依頼しました。出てきた PR を見たら、機能は動いているものの、**認可がガバガバ・リトライがない・テストが偽物** という三重苦でした。

AI が悪いわけではありません。`spec.md` には機能要件しか書いていなかったのです。セキュリティ要件も障害時の振る舞いも、書かれていないものは AI にとって存在しないのと同じでした。

この記事では、1枚だった `spec.md` を **4ファイルに分割** したらなぜ AI が迷わなくなったのか、運用してわかった境界の引き方、並行作業のメリット、そして「このバグはどのファイルの不備か」を判定するレビュー練習問題を書きます。

---

## なぜ spec.md 1枚では破綻したか

### 1. コンテキストウィンドウ問題

`spec.md` は機能を追加するたびに肥大化します。半年運用したあるプロジェクトでは 4,800 行になりました。

AI に「認可まわりをレビューして」と頼むと、**機能要件・エラーコード一覧・画面遷移・DB スキーマ** まで全部読ませることになります。読ませたからには「これも参考になるかな」と推論に巻き込まれます。結果、的外れな指摘や、存在しない制約をでっち上げる幻覚が増えました。

人間は「今読むべき章」を飛ばし読みできますが、AI は渡されたコンテキスト全体を均等に重みづけします。**1ファイルに詰め込めば詰め込むほど、AI の精度は落ちる**のです。

### 2. 責務混在問題

`spec.md` の中に機能要件・セキュリティ・障害対応・実装順序が混ざると、レビュー観点が絡み合います。

```markdown
## 注文作成 API

- POST /orders エンドポイント
- リクエスト: {product_id, quantity}
- バリデーション: quantity > 0
- 認可: 認証必須
- リトライ: 3回まで、exponential backoff
- 実装順序: Repository → Service → Endpoint
```

上のような書き方だと、「このバグはどこの不備?」と問うたときに「仕様書全体」としか言えなくなります。認可ゼロ事件が起きても、障害時に二重課金が起きても、原因は同じ `spec.md` の中に埋もれます。

### 3. 並行更新問題

PO が機能要件を書き、セキュリティ担当が脅威モデルを書き、SRE が障害対応を書く ― 本来は並行作業が可能なはずです。

しかし 1ファイルだと **同時編集でコンフリクトが連発** します。レビュー差分も「PO の変更と SRE の変更が混在した diff」になって読みにくい。結果、「誰か 1 人が書く」運用に逆戻りし、視点の偏りが生まれます。

---

## 4ファイルの役割と境界

SFAD cycle の最新版は、仕様を以下の4ファイルに分割します。

### `functional.md` ― 機能要件・ハッピーパス

何を作るか、誰がどう使うか、期待される振る舞いは何か。Example Mapping のアウトプットをそのまま Given-When-Then に展開します。

```markdown
## Feature: 注文作成

### Rule 1: 在庫がある商品のみ注文可能
- Example 1.1: 在庫10個の商品を1個注文 → 成功、在庫9個に減る
- Example 1.2: 在庫0個の商品を注文 → 失敗、エラー OUT_OF_STOCK

### Given-When-Then
Given: 認証済みユーザー、在庫10個の商品 P1
When: POST /orders {product_id: P1, quantity: 1}
Then: 201 Created、order_id を返す、在庫が9個に減っている
```

ここには **攻撃シナリオも障害シナリオも書きません**。純粋に「正常系で何が起きるべきか」に集中します。

### `threat.md` ― 攻撃者視点・OWASP対応・認可マトリクス

誰が攻撃してくるか、どう攻撃してくるか、どう防ぐか。Three Amigos の4人目「攻撃者」が埋める専用ファイルです。

```markdown
## Authorization Matrix

| 操作 | 未認証 | 一般ユーザー | リソース所有者 | 管理者 |
|---|---|---|---|---|
| GET /orders/{id} | ❌ 401 | ❌ 403 | ✅ | ✅ |
| POST /orders | ❌ 401 | ✅ | - | ✅ |
| DELETE /orders/{id} | ❌ 401 | ❌ 403 | ✅ | ✅ |

## IDOR チェック

- path parameter {id} は current_user の owner_id と DB で突き合わせる
- id を改竄した場合は 404 (存在を隠す) or 403 (明示拒否) のどちらかに統一

## Mass Assignment

- クライアントから受け取る: product_id, quantity
- サーバー側で設定する: id, owner_id, created_at, status
- クライアントが送ってはいけない: id, owner_id, status, price_override
```

**`threat.md` を開けば、セキュリティ担当だけで独立してレビュー可能** になります。

### `resilience.md` ― 障害シナリオ・リトライ・タイムアウト

外部依存が落ちたら、内部例外が起きたら、リソースが枯渇したら何が起きるか。SRE 視点の仕様です。

```markdown
## 外部依存の障害対応

### 在庫サービス (外部 API)
- Timeout: 3秒
- Retry: 最大3回、exponential backoff (0.5s, 1s, 2s)
- Circuit Breaker: 直近10リクエストで50%失敗したら30秒オープン
- Fallback: キャッシュから最終在庫を返す、stale_warning フラグを true に

### DB (PostgreSQL)
- Connection pool 枯渇時: 503 Service Unavailable を返す
- Deadlock: 自動再試行 1回のみ
```

### `plan.md` ― 実装順序・依存関係・スコープ外の明示

何をどの順番で実装するか、何を今回はやらないか。実装者と AI のガイドです。

```markdown
## 実装順序

1. OrderRepository (DB 層)
   - Out of Scope: 在庫サービス連携 (step 3 で追加)
2. OrderService (ドメイン層)
   - 在庫チェックはモックで仮実装
3. InventoryClient (外部連携)
4. POST /orders エンドポイント
5. 認可ミドルウェア追加 (`threat.md` の Authorization Matrix に準拠)

## Out of Scope (今回やらないこと)

- 注文キャンセル機能 (次スプリント)
- 非同期決済連携 (次スプリント)
```

`plan.md` は **「書かれていないことはやらない」宣言** でもあります。AI がスコープを超えて実装するのを防ぐ境界線。

---

## 8 Phase とファイルのマッピング

SFAD cycle は 8 Phase で 4ファイルを埋めていきます。

| Phase | 作業 | 出力ファイル | 参照ファイル |
|---|---|---|---|
| 1 | Example Mapping | (ドラフト) | なし |
| 2 | functional.md 生成 | functional.md | Example Map |
| 3 | threat.md 生成 | threat.md | functional.md |
| 4 | resilience.md 生成 | resilience.md | functional.md |
| 5 | plan.md 生成 | plan.md | 上記 3ファイル |
| 6 | 受け入れテスト生成 | tests/acceptance/* | functional.md, threat.md |
| 7 | UC TDD | implementation + tests | plan.md, 全仕様ファイル |
| 8 | 静的解析ゲート | lint/type check | 実装コード全般 |

重要なのは、Phase 6 以降で **「このコードをレビューするとき、どのファイルを AI に渡すか」が明確になる** ことです。

- 認可漏れが疑わしい → `threat.md` + 該当エンドポイントコード
- リトライが効いていない → `resilience.md` + 該当呼び出しコード
- 仕様通り動いていない → `functional.md` + 受け入れテスト

渡す範囲が小さいほど、AI の指摘は的確になります。

---

## ケーススタディ: 注文作成機能を4ファイルに分けて書く

実際に1つの機能で4ファイル全部を書いてみましょう。題材は「認証済みユーザーが商品を注文する」機能です。

### Phase 1-2: Example Mapping → functional.md

Rule 1: 在庫があれば注文できる / Rule 2: 在庫がなければ注文できない / Rule 3: 数量は1以上 / Rule 4: 同じユーザーが30秒以内に同じ商品を注文したら重複として扱う

これを Given-When-Then に落として `functional.md` へ。120行くらい。

### Phase 3: threat.md

- `POST /orders` は認証必須
- `GET /orders/{id}` は所有者のみ
- quantity は int で受ける (float で送られたら 422)
- product_id は UUID 形式、悪意あるSQL文字列を弾く
- price_override をクライアントから受け取らない (Mass Assignment)

180行くらい。

### Phase 4: resilience.md

- 在庫サービス timeout → リトライ3回
- DB deadlock → 自動再試行1回
- 二重注文防止に idempotency key を受け取れるようにする

100行くらい。

### Phase 5: plan.md

実装順序: OrderRepository → OrderService → InventoryClient → POST /orders → 認可 → idempotency key 対応

80行くらい。

**4ファイル合計で 480行**。spec.md 1枚で書いていたら 600行超えて読みづらくなっていた内容が、責務ごとに分かれて読みやすくなりました。

---

## レビュー練習問題

以下のバグは、4ファイルのどれの不備でしょうか？ 解答は末尾に。

### 問1

本番で起きたバグ: **他人の注文を自分の注文として削除できた**。`DELETE /orders/{id}` で、他人の order_id を指定しても 200 が返った。

### 問2

本番で起きたバグ: **在庫サービスが 60秒ハングした結果、全ユーザーの注文がタイムアウト**。リクエストごとに60秒待たされた。

### 問3

本番で起きたバグ: **仕様にない「予約注文」機能が勝手に実装されていた**。AI が「将来必要になるだろう」と自発的に追加。

### 解答

- 問1: `threat.md` の Authorization Matrix が不備。所有者チェックが書かれていなかった
- 問2: `resilience.md` の Timeout/Circuit Breaker が不備。外部依存の障害対応が抜けていた
- 問3: `plan.md` の Out of Scope が不備。「予約注文は次スプリント」と明記すべきだった

バグの原因がどのファイルにあるかを特定できる ― これこそが4ファイル分割の最大の効用です。**どのファイルを更新すれば再発防止できるか** も一目でわかります。

---

## 並行作業のメリット

4ファイル分割の副産物として、チーム内の並行作業が格段にやりやすくなります。

| 担当 | 担当ファイル | 得意領域 |
|---|---|---|
| Product Owner | functional.md | ユーザー体験、ビジネスルール |
| セキュリティ担当 | threat.md | OWASP、認可、入力検証 |
| SRE / Platform | resilience.md | 障害モード、リトライ戦略 |
| Tech Lead | plan.md | 実装順序、スコープ管理 |

各担当が独立して書けて、レビュー差分も綺麗に分かれます。Git の rebase コンフリクトも激減しました。

「Three Amigos」で4人目の攻撃者を招待する話と組み合わせると、**4視点 × 4ファイル** で仕様策定の網羅性が一段上がります (これは次の記事で詳しく書きます)。

---

## まとめ

- `spec.md` 1枚では **コンテキスト肥大・責務混在・並行編集コンフリクト** の三重苦で破綻する
- 4ファイル分割 (`functional.md` / `threat.md` / `resilience.md` / `plan.md`) で責務を分離すると、AI が迷わない
- SFAD cycle は 8 Phase で4ファイルを埋めていく。Phase ごとに AI に渡すコンテキストが最小化される
- バグが起きたときも **「どのファイルの不備か」を特定しやすい** ため、再発防止の当たりがつきやすい
- チーム内の並行作業も圧倒的にやりやすい。各担当が独立してレビューできる
- 1ファイル 200〜300行に収まる粒度が、AI にも人間にも優しい

spec.md 1枚で苦しんでいるチームは、一度4分割を試してみてください。**最初は冗長に感じますが、3機能目くらいで「これ以上書けない」から「これ以外に書くことがない」に変わります**。

---

## 次の記事: AIに攻撃者視点を持たせる Three Amigos (5/14 公開予定)

4ファイルのうち `threat.md` を埋めるには、Three Amigos (PO/Dev/QA) に **4人目の攻撃者** を加える必要があります。AI を攻撃者として演じさせるプロンプト設計、OWASP Top 10 との対応、実際のセッション記録を次回公開します。
