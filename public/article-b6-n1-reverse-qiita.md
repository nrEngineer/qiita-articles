---
title: 既存コードから N+1 を仕様化する ― reverse 9タグ活用ガイド
tags:
  - N+1問題
  - SFAD
  - AI駆動開発
  - ClaudeCode
  - パフォーマンス
private: true
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---

## TL;DR

- 保守案件で受け継いだコードに仕様書がない ― でも N+1 は **100% の確率で眠っている**
- SFAD `reverse` コマンドは既存コードから **9種類の問題タグ** を自動抽出する
- 9タグ: [DEAD CODE] / [SECURITY] / **[N+1 QUERY]** / [SESSION HOLD] / [DEPRECATED] / [CIRCULAR DEP] / [MAGIC NUMBER] / [BROKEN TEST] / [MISSING AUDIT]
- 本記事では特に **[N+1 QUERY]** に絞って、検出パターン 5 種類と修正方法を Python/TypeScript/Go/Ruby の4言語で解説
- 実プロジェクト (匿名化) で reverse を走らせた結果: **1.2秒 → 80ms に短縮** した修正例を公開
- Art-06 (3/16 公開) で紹介した reverse コマンドの続編。今回は「問題タグ」側にフォーカス

## この記事でできること

| やりたいこと | 対応セクション |
|---|---|
| 仕様書がない保守案件でも N+1 を潰したい | reverse の使いどころ |
| 9タグ全体を把握したい | 9タグ一覧 |
| N+1 の検出パターンを知りたい | [N+1 QUERY] 5 パターン |
| 言語別の修正方法を知りたい | 修正パターン (4言語) |
| Before/After のベンチマークを見たい | 実測値 |

---

ある日、SaaS の機能追加案件を引き継ぎました。ソースコードはあります。仕様書はありません。Git ログには「fix bug」「update」「wip」しか書かれていません。

最初の 1 週間で 3 つの N+1 を踏み抜きました。本番でレスポンスが 5秒ハング、ユーザーから「重い」と苦情、Datadog のアラートが鳴る。**全て「既存コードに潜んでいた N+1 の上に機能を乗せた」** パターンでした。

Art-06 (3/16 公開) で紹介した `sfad:reverse` コマンドは、既存コードから仕様を逆抽出するツールですが、実は **9種類の問題タグ** も一緒に検出します。その中で特に遭遇率が高いのが **[N+1 QUERY]**。

この記事では、9タグ全体像を把握しつつ、**[N+1 QUERY]** タグを軸に、検出パターンと修正を 4言語 (Python/TypeScript/Go/Ruby) で解説します。

---

## sfad:reverse の 9タグ一覧

既存コードに `sfad:reverse {feature_name}` を実行すると、コードから仕様候補を抽出しつつ、以下9種類のタグで問題を可視化します。

| タグ | 意味 | 典型例 |
|---|---|---|
| [DEAD CODE] | 使われていないコード | 参照されない関数、消し忘れた import |
| [SECURITY] | OWASP 相当の脆弱性 | bare except、未認証 endpoint、Mass Assignment |
| **[N+1 QUERY]** | **ループ内の個別クエリ** | **for user in users: user.orders** |
| [SESSION HOLD] | DBセッション長時間保持 | request 全体で 1 セッション占有 |
| [DEPRECATED] | 非推奨 API 使用 | PyCrypto、moment.js、deprecated library |
| [CIRCULAR DEP] | 循環依存 | A が B を import、B が A を import |
| [MAGIC NUMBER] | 説明のない定数 | if x > 86400: ... (これは何秒?) |
| [BROKEN TEST] | 偽物テスト (Art-12参照) | 本番を import していないテスト |
| [MISSING AUDIT] | 監査ログなしの mutation | DELETE なのにログが無い |

### 9タグの確信度レベル

各検出には **高 / 中 / 低** の確信度が付きます。

- **高**: ほぼ間違いなく問題 (例: 明らかな N+1 ループ)
- **中**: 要確認 (例: リスト内包だが条件によっては問題)
- **低**: ヒューリスティックに引っかかったが誤検出の可能性 (例: 関数名に "delete" を含むが実装は削除していない)

確信度「高」から順に対処していくのが実務的です。

---

## [N+1 QUERY] タグの検出パターン

reverse が [N+1 QUERY] としてフラグを立てる代表パターン5種です。

### パターン1: for ループ内の個別 get

```python
# Python (SQLAlchemy)
orders = await db.execute(select(Order))
for order in orders.scalars():
    user = await db.get(User, order.user_id)  # ← N+1
```

**確信度**: 高。ループ内で DB クエリを発行しているのが明白。

### パターン2: Lazy load の誘爆

```python
# Python (SQLAlchemy)
orders = await db.execute(select(Order))
for order in orders.scalars():
    print(order.user.name)  # ← relationship が lazy load なら N+1
```

**確信度**: 中。relationship の load 戦略によって挙動が変わる。

### パターン3: Serializer 内クエリ

```python
# FastAPI / Pydantic
class OrderResponse(BaseModel):
    id: UUID
    user_name: str

    @validator("user_name", pre=True, always=True)
    def fetch_user_name(cls, v, values):
        return db.query(User).get(values["user_id"]).name  # ← N+1
```

**確信度**: 高。validator/serializer 内でクエリ発行。

### パターン4: 外部 API の個別 fetch

```typescript
// TypeScript
const users = await db.users.findMany();
for (const user of users) {
  const profile = await externalApi.getProfile(user.id);  // ← 外部 API の N+1
  ...
}
```

**確信度**: 高。外部 API コールは DB より遅いので、N+1 がより致命的。

### パターン5: キャッシュミス連鎖

```python
for product_id in product_ids:
    cached = cache.get(f"product:{product_id}")
    if cached is None:
        product = db.query(Product).get(product_id)  # ← キャッシュミス時に N+1
        cache.set(f"product:{product_id}", product)
```

**確信度**: 中。ウォームアップ時のみ問題。

---

## 修正パターン (4言語)

検出された N+1 を修正する方法を、主要 4 言語で解説します。

### Python (SQLAlchemy)

```python
# Before: N+1
orders = await db.execute(select(Order))
for order in orders.scalars():
    user = await db.get(User, order.user_id)

# After: selectinload
from sqlalchemy.orm import selectinload

orders = await db.execute(
    select(Order).options(selectinload(Order.user))
)
for order in orders.scalars():
    print(order.user.name)  # ← 追加クエリなし
```

**selectinload vs joinedload**:
- `selectinload`: IN 句で一括取得 (1対多で推奨)
- `joinedload`: LEFT JOIN で一括取得 (1対1で推奨)

### TypeScript (Prisma)

```typescript
// Before: N+1
const orders = await prisma.order.findMany();
for (const order of orders) {
  const user = await prisma.user.findUnique({ where: { id: order.userId } });
}

// After: include
const orders = await prisma.order.findMany({
  include: { user: true },
});
for (const order of orders) {
  console.log(order.user.name);
}
```

**Prisma の include vs select**:
- `include`: 関連を丸ごと取得
- `select`: 特定フィールドのみ取得 (転送量削減)

### Go (GORM)

```go
// Before: N+1
var orders []Order
db.Find(&orders)
for _, order := range orders {
    var user User
    db.First(&user, order.UserID)
}

// After: Preload
var orders []Order
db.Preload("User").Find(&orders)
for _, order := range orders {
    fmt.Println(order.User.Name)
}
```

### Ruby (Rails)

```ruby
# Before: N+1
orders = Order.all
orders.each do |order|
  puts order.user.name  # ← N+1
end

# After: includes
orders = Order.includes(:user)
orders.each do |order|
  puts order.user.name  # ← 追加クエリなし
end
```

**includes vs preload vs eager_load**:
- `includes`: Rails が自動で判断 (preload or eager_load)
- `preload`: 常に別クエリで取得
- `eager_load`: 常に LEFT JOIN で取得

---

## 実プロジェクト適用例 (匿名化)

実際に受け継いだ案件で reverse を走らせて、N+1 を潰した記録です。

### 対象

- SaaS のダッシュボード画面
- 1 画面に 200 案件のサマリを表示
- レスポンスタイム: 平均 1.2 秒、p99: 3.5 秒

### reverse 実行結果 (抜粋)

```
Feature: dashboard
File: app/services/dashboard.py

[N+1 QUERY] (確信度: 高)
  Location: dashboard.py:42
  Code: for case in cases: case.assignee.name
  Reason: `assignee` relationship is lazy-loaded
  Estimated queries: 1 + 200 = 201

[N+1 QUERY] (確信度: 高)
  Location: dashboard.py:58
  Code: for case in cases: len(case.tags.all())
  Reason: `tags` relationship is lazy-loaded
  Estimated queries: 1 + 200 = 201

[N+1 QUERY] (確信度: 中)
  Location: dashboard.py:71
  Code: for case in cases: external_api.fetch_status(case.external_id)
  Reason: external API call inside loop
  Estimated cost: 200 API calls / request

[MISSING AUDIT] (確信度: 高)
  Location: dashboard.py:103
  Code: case.status = 'closed'; db.commit()
  Reason: mutation without audit log entry
```

### 修正後

```python
# Before
cases = await db.execute(select(Case))
for case in cases.scalars():
    row = {
        "assignee": case.assignee.name,  # N+1
        "tag_count": len(case.tags),     # N+1
        "status": external_api.fetch_status(case.external_id),  # 外部 N+1
    }

# After
cases = await db.execute(
    select(Case)
    .options(
        selectinload(Case.assignee),
        selectinload(Case.tags),
    )
)
case_list = cases.scalars().all()

# 外部 API は batch 化
external_ids = [case.external_id for case in case_list]
statuses = await external_api.fetch_statuses_batch(external_ids)

for case, status in zip(case_list, statuses):
    row = {
        "assignee": case.assignee.name,
        "tag_count": len(case.tags),
        "status": status,
    }
```

### ベンチマーク (実測)

| 指標 | Before | After | 変化 |
|---|---|---|---|
| 平均レスポンスタイム | 1,200ms | 80ms | **-93%** |
| p99 レスポンスタイム | 3,500ms | 180ms | **-95%** |
| SQL 発行数 | 401 | 3 | **-99%** |
| 外部 API コール数 | 200 | 1 | **-99.5%** |

---

## reverse でタグが出た後の運用フロー

### Step 1: 優先度付け

- [N+1 QUERY] 高 → 即修正 (ユーザー体験直撃)
- [SECURITY] 高 → 即修正 (事故リスク)
- [BROKEN TEST] 高 → 即修正 (品質の前提が崩れる)
- [DEPRECATED] 高 → 次スプリント (依存ライブラリ整備)
- [MAGIC NUMBER] 低 → バックログ

### Step 2: 修正 + テスト追加

修正するときは必ず **回帰テスト** を追加。次に同じ N+1 が入らないように `assert_max_queries` 系のテストを書く。

```python
# pytest + sqlalchemy-utils
from sqlalchemy_utils import assert_max_queries

def test_dashboard_query_count(client):
    with assert_max_queries(3):
        response = client.get("/dashboard")
    assert response.status_code == 200
```

### Step 3: 仕様書化

reverse で抽出された Example Mapping 候補を元に `functional.md` / `threat.md` / `resilience.md` を作成。以降は仕様駆動で保守。

### Step 4: 回帰テストを CI に入れる

N+1 の再発防止は、**CI で SQL 発行数上限を機械的にチェック** するのが一番確実。`assert_max_queries` を主要画面に全部入れる。

---

## まとめ

- 仕様書がない保守案件でも、`sfad:reverse` の 9タグで問題を可視化できる
- [N+1 QUERY] タグは遭遇率が最も高く、インパクトも大きい
- 検出パターン 5種類: for ループ / Lazy load / Serializer / 外部 API / キャッシュミス
- 修正は `selectinload` / `include` / `Preload` / `includes` など言語別 ORM 機能
- 実案件で **1.2秒 → 80ms (-93%)** の改善例
- 修正後は `assert_max_queries` 系テストを CI に入れて再発防止
- reverse の 9 タグは N+1 だけでなく、[BROKEN TEST] (Art-12) / [SECURITY] (Art-11) / [DEPRECATED] など、AI 駆動開発で頻出する罠を網羅

保守案件を引き継いだらまず `sfad:reverse` を走らせて、**9タグの「高」確信度項目から順に潰す** ― これで初手が自動化できます。

---

## 次回予告: Season 2「SFAD実践編」開幕 (7月〜)

ここまで Season 1 では「78バグから学んだ基礎」として、SFAD の仕組みと運用を扱ってきました。次回から Season 2「SFAD実践編」がスタートします。

- AIが書いたコードをリファクタリングする技術 ― 安全に構造を変える手順
- AI×型安全 ― TypeScript/Go/Rust の型システムで AI の暴走を防ぐ
- AIに書かせたコードのセキュリティ監査 ― OWASP Top 10 を SFAD で防ぐ
- CI パイプラインに品質ゲートを組む ― AI コードを自動で検査する仕組み

現場の「これどうするの?」を SFAD で解く実践編、お楽しみに。

次回 Season 2 第1話: **「AIが書いたコードをリファクタリングする技術」** (7月前半公開予定)
