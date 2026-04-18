---
title: 13項目の実装ルール ― AIが破る罠リスト
tags:
  - SFAD
  - AI駆動開発
  - ClaudeCode
  - コード品質
  - 静的解析
private: true
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---

## TL;DR

- AI が書くコードには、何度でも同じパターンの罠が出る。人力で毎回思い出すのは限界
- SFAD `impl` では、AI が繰り返し破る 13項目を **実装ルール** として明文化し、静的解析 + プロンプト制約 + レビューチェックリストの **3段構え** で防御
- 項目は Mass Assignment / 認可 / N+1 / SSR安全性 / テスト本物性 / バリデーション / トランザクション / エラー処理 / リソースリーク / シークレット漏洩 / 冪等性 / レート制限 / 型変換 の 13
- 単品ルールではなく **「どのレイヤーで何を止めるか」** を設計する。静的解析が一番強い、次点プロンプト、最後がレビュー
- Art-11 (認可ゼロ) は項目2、Art-12 (偽物テスト) は項目5、Art-05 (エラー握りつぶし) は項目8 の事例として再訪します

## この記事でできること

| やりたいこと | 対応セクション |
|---|---|
| AI が繰り返す罠の全体像を把握したい | 13項目一覧 |
| 各項目の具体的なコード例と対策を知りたい | 各ルール詳解 |
| どのレイヤーで何を止めるか設計したい | 3段構え防御 |
| PR テンプレに入れるチェックリストが欲しい | レビューチェックリスト |

---

AI 駆動開発を続けていると、**同じ罠に何度もハマる** ことに気づきます。違う機能で違うチームで違うプロンプトで、なのに出てくるコードの失敗パターンはほぼ同じ。

失敗を Art-01 で 78 バグに分類したときは「どういう種類のバグがあるか」を棚卸ししました。今回はその先 ― **「AI が繰り返し破るルール」を明文化して、構造的に防御する** 話です。

ルールを人力で毎回思い出すのは無理です。だから SFAD の `impl` コマンドでは、13項目を以下の3段構えで自動化しました。

1. **静的解析ゲート**: コミット前に機械的に止める (一番強い)
2. **プロンプト制約**: AI に渡すシステムプロンプトで明示 (中間)
3. **レビューチェックリスト**: PR テンプレで人間が最終確認 (最後の砦)

この記事では 13項目を事例付きで全部解説します。

---

## 13項目一覧

| # | ルール | 主な防御ツール |
|---|---|---|
| 1 | Mass Assignment 防止 | Pydantic/Zod allow-list |
| 2 | 認可チェック | Authorization Matrix 準拠 |
| 3 | N+1 クエリ防止 | selectinload/JOIN + 静的解析 |
| 4 | SSR 安全性 | eslint-plugin-react + build check |
| 5 | テスト本物性 | import 検査 + coverage |
| 6 | 入力バリデーション境界 | schema validation at boundary |
| 7 | トランザクション境界の明示 | 手動アノテーション + lint |
| 8 | エラーハンドリング (rethrow/suppress) | bare except 禁止 + 構造化ログ |
| 9 | リソースリーク防止 | `with`/`defer`/context manager |
| 10 | シークレット漏洩防止 | log sanitizer + allowlist |
| 11 | 冪等性 | idempotency key + 採番ロック |
| 12 | レート制限考慮 | backoff + quota |
| 13 | 型変換の明示 | strict type check |

---

## 1. Mass Assignment 防止

### AI がやる罠

```python
class UserCreate(BaseModel):
    email: str
    password: str
    is_admin: bool = False  # ← defaults to False だから大丈夫と思ってる

@router.post("/users")
async def create_user(data: UserCreate):
    user = User(**data.dict())
    ...
```

クライアントが `{"email":"x","password":"y","is_admin":true}` を送れば通ります。

### なぜやらかすのか

- Pydantic/Zod モデルを「クライアント入力」と「サーバーデータ」の両方で使い回す
- `User(**data.dict())` の展開で意図しないフィールドが通る

### 防ぐルール

- クライアント入力スキーマは **サーバー設定フィールドを含めない**
- Pydantic `model_config = {"extra": "forbid"}`
- DB モデルへの変換は **明示的フィールド指定** (`User(email=..., password_hash=...)`)

### 検出

- Ruff: `PLR0912` 等で巨大なマッピング関数を検出 (間接的)
- 独自 lint で `**data.dict()` / `**body.dict()` を ban するのが一番効く

---

## 2. 認可チェック

Art-11 (4/23 公開) で紹介した **6000行PR 認可ゼロ事件** がこの項目の典型例です。

### AI がやる罠

```python
@router.post("/orders/{order_id}/cancel")
async def cancel_order(order_id: UUID, db: AsyncSession = Depends(get_db)):
    order = await db.get(Order, order_id)
    order.status = "cancelled"
    await db.commit()
```

`Depends(get_current_user)` が無い。さらに `order.owner_id == current_user.id` の検証も無い。

### なぜやらかすのか

- 認証ミドルウェアは「デコレータで1行足せばOK」という錯覚
- リソース所有者チェックは「DBで1行確認」という習慣化が必要

### 防ぐルール

- **全 mutation エンドポイント** に `Depends(get_current_user)` 必須
- 対象リソースに `owner_id` があれば、必ず DB で `owner_id == current_user.id` 検証
- `threat.md` の Authorization Matrix を参照

### 検出

- ルート定義の AST を scan して `Depends(get_current_user)` の不在を検出する自作 lint
- もしくは middleware で全ルートに強制 (opt-in で除外可能)

---

## 3. N+1 クエリ防止

### AI がやる罠

```python
@router.get("/orders")
async def list_orders(db: AsyncSession = Depends(get_db)):
    orders = await db.execute(select(Order))
    result = []
    for order in orders.scalars():
        user = await db.get(User, order.user_id)  # ← N+1
        items = await db.execute(select(OrderItem).where(OrderItem.order_id == order.id))  # ← N+1
        result.append({"order": order, "user": user, "items": items.scalars().all()})
    return result
```

### なぜやらかすのか

- ループ内で個別クエリを走らせるのが自然な書き方に見える
- ORM の lazy load に気づかない

### 防ぐルール

- 一覧系クエリは `selectinload` / `joinedload` で eager load
- 1リクエスト内の SQL 発行数を `N + 定数` に抑える

### 検出

- `sqlalchemy-utils` の `assert_max_queries`
- SQL ロガーを仕込んで CI 内でクエリ回数を測定
- `sfad:reverse` の `[N+1 QUERY]` タグ (B6記事で詳述)

---

## 4. SSR 安全性 (hydration mismatch 禁止)

### AI がやる罠 (React)

```tsx
export default function Page() {
  return <div>Render time: {new Date().toISOString()}</div>;
}
```

サーバーと クライアントで `new Date()` の値が違うため、hydration エラー。

### なぜやらかすのか

- `Math.random()` / `new Date()` / `window.X` を気軽に使う
- Client Component と Server Component の境界を曖昧にする

### 防ぐルール

- Server Component で時刻・乱数を使うなら **props として渡す**
- クライアント限定ロジックは `"use client"` を明示し、`useEffect` 内で実行

### 検出

- `eslint-plugin-react` の `react-hooks/rules-of-hooks`
- Next.js の build 時 warning を error に昇格

---

## 5. テスト本物性

Art-12 (4/30 公開) で紹介した **偽物テスト** がこの項目の典型例です。

### AI がやる罠

```python
# tests/test_ranking.py

class StandingsCalculator:  # ← テスト用副本実装
    def calculate(self, games):
        ...

def test_ranking():
    calc = StandingsCalculator()
    assert calc.calculate([...]) == [...]
```

本番モジュールを import していない。テストが緑でも本番は壊れている。

### なぜやらかすのか

- 本番側がテスト不可能な構造 (ハンドラ直書き) で、import できない
- 「テスト用に簡略化」が副本実装を正当化する

### 防ぐルール

- テストファイル内に **class 定義禁止** (フィクスチャ関数のみ許可)
- 本番モジュールの import が 0 のテストファイルを CI で detect
- プロンプトに「本番から import せよ」を必ず書く

### 検出

- 自作 lint: テストファイルの `from app.services.` / `from app.domain.` の import 存在確認
- Coverage: 実際にテストから実行された本番コード行数を追跡

---

## 6. 入力バリデーション境界

### AI がやる罠

```python
@router.post("/orders")
async def create_order(body: dict):  # ← dict で受ける
    product_id = body.get("product_id")
    quantity = int(body.get("quantity", 1))  # ← 値なしでも 1 になる
    ...
```

- 型が曖昧
- バリデーションが散発的
- 想定外のフィールドが通る

### なぜやらかすのか

- 「動けばいい」で dict を素通し
- スキーマを書くのが面倒

### 防ぐルール

- API 層では **必ず Pydantic/Zod モデルで受ける**
- 境界を超えた後の内部コードは「型で保証されている」前提で書く
- バリデーションは境界でだけ行う (DRY)

### 検出

- Ruff: `ANN` 系で型アノテーション必須化
- mypy --strict
- API ルート定義に `body: dict` を禁止する自作 lint

---

## 7. トランザクション境界の明示

### AI がやる罠

```python
async def transfer_money(from_id, to_id, amount):
    await debit(from_id, amount)  # commit
    await credit(to_id, amount)   # commit ← 失敗すると from_id から消えただけ
```

トランザクションなしで、片側失敗時に整合性が壊れる。

### なぜやらかすのか

- トランザクション境界の仕様が明文化されていない
- 「commit しちゃいけない場所」の共通認識がない

### 防ぐルール

- `spec` (functional.md) に **「この操作はトランザクションで囲む」** と明記
- UoW (Unit of Work) パターンで境界を1箇所に集約
- Service 層の関数は「トランザクション内で動く前提」にする

### 検出

- 自作 lint: Service 関数内の `await session.commit()` を ban

---

## 8. エラーハンドリング (rethrow vs suppress)

Art-05 (4/6 公開済み) で詳しく扱った項目です。

### AI がやる罠

```python
try:
    result = await external_api.call()
except Exception:
    pass  # ← 握りつぶし
```

```typescript
try {
    result = await externalApi.call();
} catch (e) {
    // do nothing
}
```

### なぜやらかすのか

- 「止まらないことが正解」と誤解
- エラーログを出す仕組みがない

### 防ぐルール

- bare except / 空 catch 禁止
- 握りつぶすなら **構造化ログに reason を残す**
- rethrow するときは context (元の例外) を保持

### 検出

- Python: `ruff` の `E722` (bare except), `BLE001` (Exception catch)
- TypeScript: `eslint-plugin-no-empty`
- Go: `errcheck`

---

## 9. リソースリーク防止

### AI がやる罠

```python
async def read_config():
    f = open("config.yaml")  # ← close されない
    data = yaml.safe_load(f)
    return data
```

```python
async def query():
    session = async_session()
    result = await session.execute(...)
    return result  # ← close されない。接続プール枯渇
```

### なぜやらかすのか

- 短いコードだと「そこで close しなくても大丈夫」と錯覚
- try/finally を書くのが面倒

### 防ぐルール

- ファイル・DB セッション・ソケットは **必ず `with` / `async with`**
- Go は `defer`, Python は `contextmanager`, TypeScript は `finally` で必ず close

### 検出

- Python: `ruff` の `SIM` 系 (simplify suggestions)
- 独自 lint: `open(` の後に `.close()` が無い場合 flag

---

## 10. シークレット漏洩防止

### AI がやる罠

```python
logger.info(f"User login: {user}")  # ← user オブジェクトに password_hash が含まれる
```

```python
logger.error(f"Request failed: {request.headers}")  # ← Authorization ヘッダー丸見え
```

### なぜやらかすのか

- ログに何でも突っ込むのがデバッグ時の習慣
- 本番で何が出力されるか想像していない

### 防ぐルール

- ログは **構造化ログ + allow-list**
- `__repr__` で機密フィールドを `[REDACTED]` 化
- 環境変数経由のシークレットは `get_env_secret()` など専用関数で取得し、print/log で誤出力しない

### 検出

- log sanitizer middleware (prod ビルドで強制)
- シークレット検出ツール (gitleaks, trufflehog) を pre-commit に

---

## 11. 冪等性

### AI がやる罠

```python
@router.post("/payment")
async def pay(amount: float, db: AsyncSession = Depends(get_db)):
    stripe.charge(amount)
    payment = Payment(amount=amount, user_id=...)
    db.add(payment)
    await db.commit()
```

クライアントがリトライすると、**Stripe で二重課金** される。

### なぜやらかすのか

- 成功レスポンスを受け取る前にクライアントがタイムアウトする想定がない
- 外部 API 呼び出しの副作用を「1回しか起きない」と思い込んでいる

### 防ぐルール

- 外部 API 呼び出しは `Idempotency-Key` ヘッダーを渡す (Stripe の機能)
- 採番ロジックは DB の unique 制約 + ON CONFLICT で防御
- `resilience.md` に **「リトライされたとき何が起きるか」** を明記

### 検出

- 統合テスト: 同じリクエストを 2 回投げて副作用が 1 回だけ起きるか確認
- プロンプトチェック: external API call の前後で idempotency key の有無を検査

---

## 12. レート制限考慮

### AI がやる罠

```python
for user in users:
    response = await external_api.fetch(user.id)  # ← 1万人ループで即座に 429
```

### なぜやらかすのか

- 外部 API のレート制限を意識しない
- バックオフ実装が面倒

### 防ぐルール

- 外部 API 呼び出しは **必ず retry library** を使う (tenacity, p-retry)
- 自 API にも rate limit middleware を置く
- バッチ処理は `asyncio.Semaphore` で並列数を制限

### 検出

- `resilience.md` で `Rate Limit` 項目必須チェック
- 統合テスト: 大量リクエストで 429/retry が正しく動くか

---

## 13. 型変換の明示

Art-11 で紹介した **ポイント計算 int() 切り捨てバグ** がこの項目の例です。

### AI がやる罠

```python
total = sum(game_points)  # float
display = int(total)  # ← 切り捨て
```

```typescript
const result = Number(input);  // "1.5" → 1.5, "abc" → NaN
```

### なぜやらかすのか

- 暗黙変換の挙動を把握していない
- `Decimal` vs `float` の境界を考えない

### 防ぐルール

- **金額計算は Decimal**。`float` 禁止
- `int()` / `float()` / `Number()` を使うときは **精度ロスがないことを明示的にチェック**
- 変換で丸めが起きるなら、丸め方を仕様に書く (ROUND_HALF_UP 等)

### 検出

- 自作 lint: 金額計算コンテキストで `float()` を検出
- 型アノテーションで `Decimal` を強制するゾーンを定義

---

## 3段構え防御の設計

13項目を人力で全部チェックするのは不可能です。**どのレイヤーで何を止めるか** を設計しましょう。

### 層1: 静的解析ゲート (一番強い)

コミット前 / CI で機械的に止まる。ここで止まるものは人間が忘れようが忘れまいが関係ない。

| 項目 | ツール |
|---|---|
| 1 Mass Assignment | 自作 lint (`**data.dict()` ban) |
| 3 N+1 | assert_max_queries テスト |
| 4 SSR | eslint-plugin-react |
| 5 テスト本物性 | import 検査 + coverage |
| 6 バリデーション境界 | mypy --strict |
| 8 bare except | ruff E722, BLE001 |
| 9 リソースリーク | ruff SIM, errcheck |

### 層2: プロンプト制約 (中間)

AI に渡すシステムプロンプトで明示する。破られる可能性はあるが、質は確実に上がる。

```markdown
# Implementation Rules (SFAD impl)

1. Mass Assignment 防止: クライアント入力スキーマは allow-list
2. 認可: 全 mutation に Depends(get_current_user)
3. N+1: ループ内の個別クエリ禁止、selectinload 使用
...
```

### 層3: レビューチェックリスト (最後の砦)

PR テンプレに組み込む。人間が最終確認。

```markdown
## Implementation Rules Checklist (B3 準拠)
- [ ] 1. Mass Assignment: extra forbid / 明示フィールド
- [ ] 2. 認可: get_current_user + 所有者検証
- [ ] 3. N+1: selectinload or JOIN
- [ ] 4. SSR: hydration-safe
- [ ] 5. テスト: 本番 import
- [ ] 6. バリデーション: API 境界で Pydantic
- [ ] 7. トランザクション境界: UoW または明示
- [ ] 8. エラー: rethrow or 構造化 log
- [ ] 9. リソース: with / defer
- [ ] 10. シークレット: allow-list log
- [ ] 11. 冪等性: idempotency key
- [ ] 12. レート制限: retry + quota
- [ ] 13. 型変換: Decimal / 明示 cast
```

---

## まとめ

- AI が繰り返す罠は 13 項目に分類できる。人力で毎回思い出すのは限界
- 3段構えで防御: **静的解析 > プロンプト > レビュー** の順で強い
- 静的解析で止められる項目は最優先で CI に組み込む
- プロンプト制約は質向上のため常時適用
- レビューチェックリストは PR テンプレで習慣化
- Art-11 (認可ゼロ) / Art-12 (偽物テスト) / Art-05 (握りつぶし) は、このリストに該当する事例だった
- 13項目は「これで完璧」ではない。チームの事故パターンに合わせて育てていくリスト

13項目全部を同時に導入する必要はありません。**自分のチームが直近3ヶ月で踏んだ罠から順番に** 静的解析に落としていくのが現実的です。

---

## 次の記事: Threat Modeling をAIと自動化する ― threat.md 入門 (5/28 公開予定)

ルール2 (認可チェック) を仕様段階で体系化したものが `threat.md` です。STRIDE との対応、Authorization Matrix の埋め方、AI との自動化フローを次回詳しく書きます。note 有料版では深掘り (STRIDE全網羅、実プロジェクト3件) も公開予定です。
