---
title: AIと開発して78個のバグを踏んだので全部分類した ― Python・TypeScript・Goの共通パターンと防止策
tags:
  - AI駆動開発
  - ClaudeCode
  - Python
  - TypeScript
  - Go
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---

## TL;DR

- AI開発で踏んだ78件のバグを6カテゴリに全分類（print残留23件、仕様齟齬15件、bare except 12件、テスト不足11件、型安全9件、その他8件）
- Python・TypeScript・Go共通のパターンがあり、言語に依存しない構造的問題
- **78件中46件はlint strict + CIで防げた**（Day 0品質基盤の重要性）
- 各カテゴリの具体的なコード例・検出方法・防止策をコピペ可能な設定ファイル付きで提供
- 「AIが悪い」のではなく、開発プロセスの穴が問題

## この記事でできること

| やりたいこと | この記事で得られるもの |
|---|---|
| AI開発のバグ傾向を把握したい | 78件の完全分類データ |
| lint設定をコピペしてすぐ使いたい | Python/TS/Go/Rustの設定ファイル |
| Day 0に何を入れるべきか知りたい | 品質基盤チェックリスト |
| チームに共有できるデータが欲しい | カテゴリ別の件数と防止率 |

---

78個。

ある業務システムをClaude Codeで開発し、リリース後にふりかえりをしたとき、記録に残っていたバグの数です。「多い」と思うかもしれませんし、「まあそんなものか」と思うかもしれません。私は最初、恥ずかしくてこの数字を公開するつもりはありませんでした。

でも全件を分類してみたら、思ったよりも構造的な話が見えてきました。しかもその構造は、PythonでもTypeScriptでもGoでも同じでした。言語を超えて共通するパターンがあったのです。

この記事では、78件のバグを6つのカテゴリに分類し、各カテゴリについて複数言語でのコード例と防止策を書き残します。「AIが悪い」という話ではありません。開発プロセスに穴があると、AIが書くコードにも人間が書くコードにも同じパターンのバグが出る、という話です。

## 78件の内訳

まず全体像です。

```
===== バグ分類（78件） =====

print残留              23件  ██████████████████░░░░░ 29%
仕様の認識齟齬          15件  ████████████░░░░░░░░░░░ 19%
bare except            12件  █████████░░░░░░░░░░░░░░ 15%
テスト不足によるデグレ   11件  █████████░░░░░░░░░░░░░░ 14%
型安全でない箇所         9件  ███████░░░░░░░░░░░░░░░░ 12%
その他                  8件  ██████░░░░░░░░░░░░░░░░░ 10%

合計: 78件
```

最多カテゴリが「print残留」です。最先端のAIと開発しているのに、最も多いバグがprint文の消し忘れ。最初にこれを見たとき、正直笑ってしまいました。

でもこの結果こそが、問題の本質を示していました。

---

## カテゴリ1: print残留（23件）― 全言語共通の「デバッグ出力問題」

### なぜAIはprint文を残すのか

この23件を分析して見えた構造は3つあります。

**1. 仕様にロギング方針がなかった**

私がClaude Codeに渡していた指示は「○○機能を実装してください」という内容でした。そこに「ロギングはloggerを使うこと」「print/console.log/fmt.Printlnは使用禁止」という記述はありませんでした。書いていないことを守れないのは、人間もAIも同じです。

**2. AIは「動くこと」を優先する**

デバッグ用のprintが入っていても、機能は動きます。「動くコードを生成する」という観点では、printの存在は問題ではありません。品質の問題は、仕様に品質基準が含まれていなければ、AIの判断軸に入りません。

**3. 指摘しても次の機能で再発する**

「printを消してください」と伝えれば、その会話の中では消してくれます。でも次の機能を実装するとき、また同じパターンが出てきます。AIはセッションをまたいでルールを引き継がないので、毎回同じ指摘を繰り返すことになります。

### Python: print残留の実例

```python
# 実際にあったパターン1: loggerの代わりにprint
def get_user_orders(user_id: int):
    orders = db.query(Order).filter(Order.user_id == user_id).all()
    print(f"取得件数: {len(orders)}")          # 本番のログに垂れ流し
    print(orders)                              # オブジェクトをそのままprint
    return orders

# 実際にあったパターン2: APIレスポンス確認用
async def call_external_api(payload: dict):
    response = await client.post(url, json=payload)
    print(response.json())                     # レスポンス全体が出る（機密情報の可能性）
    print(f"status: {response.status_code}")
    return response.json()

# 実際にあったパターン3: 変数確認用
def calculate_tax(price: float, tax_rate: float) -> float:
    base = price * (1 + tax_rate)
    print(f"debug: price={price}, tax_rate={tax_rate}, base={base}")
    rounded = round(base, 2)
    print(f"debug: rounded={rounded}")
    return rounded
```

```python
# あるべき姿
import logging

logger = logging.getLogger(__name__)

def get_user_orders(user_id: int):
    orders = db.query(Order).filter(Order.user_id == user_id).all()
    logger.debug("注文一覧を取得しました", extra={"user_id": user_id, "count": len(orders)})
    return orders
```

### TypeScript: console.logの等価パターン

TypeScriptでも全く同じ問題が起きます。`console.log`がデバッグ出力のデフォルトだからです。

```typescript
// AIが生成しがちなパターン
async function fetchUserProfile(userId: string): Promise<UserProfile> {
  const response = await fetch(`/api/users/${userId}`);
  console.log("response:", response.status);           // 毎リクエストで出力
  const data = await response.json();
  console.log("user data:", JSON.stringify(data));      // ユーザーデータを丸ごと出力
  return data;
}

// フロントエンドで特に多いパターン
function CartComponent({ items }: CartProps) {
  const total = items.reduce((sum, item) => sum + item.price, 0);
  console.log("cart items:", items);                    // レンダリングのたびに出力
  console.log("total:", total);
  return <div>{/* ... */}</div>;
}
```

```typescript
// あるべき姿
import { logger } from "@/lib/logger";

async function fetchUserProfile(userId: string): Promise<UserProfile> {
  const response = await fetch(`/api/users/${userId}`);
  logger.debug("ユーザープロフィールを取得", { userId, status: response.status });
  const data = await response.json();
  return data;
}
```

### Go: fmt.Printlnの等価パターン

Goでは`fmt.Println`や`fmt.Printf`がデバッグ出力に使われます。

```go
// AIが生成しがちなパターン
func GetUserOrders(ctx context.Context, userID int64) ([]Order, error) {
    orders, err := repo.FindByUserID(ctx, userID)
    if err != nil {
        fmt.Println("error fetching orders:", err)     // 標準出力にエラーが漏れる
        return nil, err
    }
    fmt.Printf("found %d orders for user %d\n", len(orders), userID)
    return orders, nil
}
```

```go
// あるべき姿
func GetUserOrders(ctx context.Context, userID int64) ([]Order, error) {
    orders, err := repo.FindByUserID(ctx, userID)
    if err != nil {
        return nil, fmt.Errorf("failed to fetch orders for user %d: %w", userID, err)
    }
    slog.DebugContext(ctx, "注文一覧を取得",
        slog.Int64("user_id", userID),
        slog.Int("count", len(orders)),
    )
    return orders, nil
}
```

### lint設定で機械的にブロックする

この23件は全て、lintルールで機械的に防止できました。

| 言語 | ツール | ルール | 効果 |
|------|--------|--------|------|
| Python | ruff | `T201` (print found) | print()を検出してエラーにする |
| TypeScript | ESLint | `no-console` | console.log/warn/errorを検出 |
| Go | forbidigo | `fmt.Print.*` | fmt.Println等を禁止 |

```toml
# Python: pyproject.toml
[tool.ruff.lint]
select = ["T20"]  # T201: print found, T203: pprint found
```

```json
// TypeScript: .eslintrc.json
{
  "rules": {
    "no-console": "error"
  }
}
```

```yaml
# Go: .forbidigo.yml
forbid:
  - pattern: "fmt\\.Print.*"
    msg: "fmt.Print系は禁止です。slogを使ってください"
```

**言語を超えた教訓**: デバッグ出力の混入は言語の問題ではなく、ロギング方針の不在とlint設定の不在が原因です。

---

## カテゴリ2: bare except（12件）― エラーを握りつぶす3つの言語パターン

エラーを握りつぶすコードは、全ての言語に存在します。書き方は違いますが、構造は同じです。「エラーが起きたことを隠す」という振る舞いです。

### Python: bare except

```python
# 実際にあったパターン: 設定ファイルのパース
def parse_config(config_str: str) -> dict:
    try:
        return json.loads(config_str)
    except:                                    # 何が起きても空dictを返す
        return {}

# さらに危険なパターン: 決済処理
def process_payment(amount: float, card_token: str):
    try:
        result = payment_gateway.charge(amount, card_token)
        return result
    except:                                    # 決済エラーも全部握りつぶす
        return {"status": "failed"}
```

`except:`は全ての例外（`KeyboardInterrupt`や`SystemExit`を含む）を捕捉します。決済処理でこれをやると、「課金に失敗したのかネットワークエラーなのかプログラムのバグなのか」が区別できません。

```python
# あるべき姿
def parse_config(config_str: str) -> dict:
    try:
        return json.loads(config_str)
    except json.JSONDecodeError as e:
        logger.error("設定ファイルのパースに失敗", extra={"error": str(e), "input_length": len(config_str)})
        raise ConfigurationError(f"Invalid config format: {e}") from e
```

### TypeScript: empty catch

```typescript
// AIが生成しがちなパターン
async function loadUserPreferences(userId: string): Promise<Preferences> {
  try {
    const response = await fetch(`/api/preferences/${userId}`);
    return await response.json();
  } catch (e) {                                // 何が起きてもデフォルト値
    return DEFAULT_PREFERENCES;
  }
}

// さらに悪いパターン: 完全な握りつぶし
async function syncData(): Promise<void> {
  try {
    await dataService.sync();
  } catch {                                    // エラーを完全に無視
    // do nothing
  }
}
```

```typescript
// あるべき姿
async function loadUserPreferences(userId: string): Promise<Preferences> {
  try {
    const response = await fetch(`/api/preferences/${userId}`);
    if (!response.ok) {
      throw new ApiError(`Failed to load preferences: ${response.status}`);
    }
    return await response.json();
  } catch (error) {
    logger.error("ユーザー設定の取得に失敗", { userId, error });
    throw error;  // 呼び出し元に判断を委ねる
  }
}
```

### Go: `_ = err` パターン

Goにはtry-catchがありませんが、エラーを握りつぶす等価パターンがあります。

```go
// AIが生成しがちなパターン1: エラーを無視
func LoadConfig(path string) *Config {
    data, _ := os.ReadFile(path)               // エラーを捨てている
    var cfg Config
    _ = json.Unmarshal(data, &cfg)             // ここも捨てている
    return &cfg
}

// パターン2: エラーをログに出すだけで処理しない
func SaveUser(ctx context.Context, user *User) {
    err := repo.Save(ctx, user)
    if err != nil {
        fmt.Println("save failed:", err)       // ログに出すが、呼び出し元には成功と見せる
    }
}
```

```go
// あるべき姿
func LoadConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("failed to read config file %s: %w", path, err)
    }
    var cfg Config
    if err := json.Unmarshal(data, &cfg); err != nil {
        return nil, fmt.Errorf("failed to parse config file %s: %w", path, err)
    }
    return &cfg, nil
}
```

### lint設定で機械的にブロックする

| 言語 | ツール | ルール | 効果 |
|------|--------|--------|------|
| Python | ruff | `E722` (bare except) | `except:`を検出 |
| TypeScript | ESLint | `no-empty` + `@typescript-eslint/no-unused-vars` | 空catchブロックを検出 |
| Go | errcheck | デフォルト | 未処理のerrorを検出 |

```toml
# Python: pyproject.toml
[tool.ruff.lint]
select = ["E722"]  # bare exceptを禁止
```

```json
// TypeScript: .eslintrc.json
{
  "rules": {
    "no-empty": ["error", { "allowEmptyCatch": false }]
  }
}
```

```bash
# Go: errcheckを実行
errcheck ./...
```

**言語を超えた教訓**: 「エラーを隠す」コードは全ての言語に存在します。構文は違えど、問題の構造は同じです。

---

## カテゴリ3: 仕様の認識齟齬（15件）― 言語に関係ない普遍的問題

この15件は、コードの品質ではなく「何を作るか」の認識のズレでした。これは言語に依存しない、最も根深い問題です。

### 典型的なズレの実例

私が指示した内容と、Claude Codeが実装した内容を並べてみます。

| 私の指示 | AIが実装した内容 | 私が期待していた内容 | ズレの本質 |
|----------|-----------------|---------------------|-----------|
| 「お問い合わせ一覧を作って」 | 全件表示、ソートなし | ページネーション+日付降順ソート | 暗黙の要件が多すぎた |
| 「ページネーションをつけて」 | 1ページ10件、URLパラメータ | 1ページ20件、無限スクロール | 「ページネーション」の定義が曖昧 |
| 「バリデーションをかけて」 | 必須チェックだけ | 形式チェック+文字数制限+禁止文字 | 「バリデーション」のスコープ未定義 |
| 「エラー処理を追加して」 | catchで500を返す | ユーザーフレンドリーなメッセージ+ログ | エラー時のUXが仕様にない |
| 「検索機能をつけて」 | タイトル部分一致 | タイトル+本文の全文検索 | 検索スコープが未定義 |

### この問題が難しい理由

仕様齟齬は、lintでは防げません。テストでも防げません。なぜなら「AIが書いたコードは、AIが解釈した仕様に対しては正しい」からです。

```python
# 「一覧を作って」に対するAIの実装
# これはAIの解釈としては正しい
def get_contacts():
    return db.query(Contact).all()  # 全件返す。仕様に制限がなかったから。
```

```python
# 私が期待していたもの
def get_contacts(page: int = 1, per_page: int = 20, sort_by: str = "created_at"):
    query = db.query(Contact).order_by(desc(sort_by))
    return query.offset((page - 1) * per_page).limit(per_page).all()
```

どちらも「一覧を作って」の解釈として成立します。問題は仕様の曖昧さです。

### 仕様齟齬を防ぐ方法: Example Mapping

15件の仕様齟齬を分析して見えたのは、全てのケースで**ルール**と**具体例**と**疑問点**が欠落していたことです。Example Mappingという手法を使うと、この抜け漏れを構造的に防げます。

```markdown
## お問い合わせ一覧

### ルール
- 1ページ20件で表示する
- 作成日の降順でソートする
- 0件のときは「お問い合わせはまだありません」と表示する

### 具体例
- 100件中、1ページ目: 1〜20件が表示される
- 最終ページ: 残り8件が表示される
- 0件: メッセージが表示される

### 疑問点
- 削除済みのお問い合わせも表示するか？ → 表示しない
- 検索機能は必要か？ → v1では不要
```

この仕様があれば、AIはページネーションもソートも0件表示も最初から実装します。

**言語を超えた教訓**: 仕様齟齬はコードの問題ではなく、コミュニケーションの問題です。言語が何であっても同じ頻度で発生します。

---

## カテゴリ4: テスト不足によるデグレ（11件）― コンテキスト窓の限界

### なぜAIはデグレを起こすのか

AIには「コンテキスト窓」と呼ばれる、一度に処理できるテキスト量の限界があります。プロジェクト全体のコードを常に把握しているわけではありません。

機能Aを修正したとき、関連する機能Bの存在をAIが「見えていない」ことがあります。見えていないものは考慮できません。

### Python: デグレの実例

```python
# 元々の実装
def calculate_discount(price: float, member_rank: str) -> float:
    if member_rank == "gold":
        return price * 0.8   # ゴールドは20%オフ
    return price

# 「シルバーランクも追加して」で修正
def calculate_discount(price: float, member_rank: str) -> float:
    if member_rank == "gold":
        return price * 0.8
    if member_rank == "silver":
        return price * 0.9   # シルバーは10%オフ
    return price
```

これだけ見ると問題なさそうです。でも別のファイルに、この関数の戻り値に依存するコードがありました。

```python
# 別ファイル: order_service.py（AIのコンテキストに入っていなかった）
def apply_campaign_discount(order: Order) -> float:
    base_discount = calculate_discount(order.price, order.user.rank)
    # ゴールド会員にはさらにキャンペーン割引を適用
    if order.user.rank == "gold":
        return base_discount * 0.95  # 追加5%オフ
    return base_discount
```

この関数の存在をAIが知らなかったため、テストもこの関数に対しては追加されませんでした。

### TypeScript: デグレの実例

```typescript
// 元の型定義
interface User {
  id: string;
  name: string;
  email: string;
}

// 「電話番号も追加して」で修正
interface User {
  id: string;
  name: string;
  email: string;
  phone: string;        // 必須フィールドとして追加
}
```

```typescript
// 別ファイルのユーザー作成処理（修正漏れ）
function createUser(name: string, email: string): User {
  return {
    id: generateId(),
    name,
    email,
    // phone がない → TypeScriptなら型エラーで気づけるが、
    // strict: falseだと見逃す
  };
}
```

### Go: デグレの実例

```go
// 元の構造体
type Config struct {
    Host string
    Port int
}

// 「タイムアウト設定も追加して」で修正
type Config struct {
    Host    string
    Port    int
    Timeout time.Duration  // 追加
}
```

```go
// 別ファイルのテストヘルパー（修正漏れ）
func newTestConfig() Config {
    return Config{
        Host: "localhost",
        Port: 8080,
        // Timeout が未設定 → ゼロ値（0秒）になる
        // テストでタイムアウトが即座に発生する
    }
}
```

### デグレを防ぐ方法

デグレの本質は「変更の影響範囲をAIが把握していない」ことです。防止策は2つあります。

**1. テストを先に書く**

```python
# テストが先にあれば、変更の影響が即座にわかる
def test_gold_member_gets_20_percent_off():
    assert calculate_discount(1000, "gold") == 800

def test_campaign_discount_for_gold():
    # このテストがあれば、calculate_discountの変更時に気づける
    order = create_test_order(price=1000, rank="gold")
    assert apply_campaign_discount(order) == 760  # 800 * 0.95
```

**2. 変更時に影響範囲を確認する仕組み**

```bash
# CIで依存関係を可視化する
# Pythonの場合
grep -rn "calculate_discount" --include="*.py"

# TypeScriptの場合: tsc --noEmit で型エラーを検出
npx tsc --noEmit

# Goの場合: go vet + テスト
go vet ./... && go test ./...
```

**言語を超えた教訓**: AIはコンテキスト窓の外を見られません。テストこそが「変更の影響範囲を教えてくれる仕組み」です。

---

## カテゴリ5: 型安全でない箇所（9件）― 各言語の「型を曖昧にする」パターン

型を曖昧にするコードは、どの言語にも特有の書き方があります。書き方は違いますが、結果は同じです。「実行時に初めてエラーに気づく」という状態になります。

### Python: `Any`と`Optional`未処理

```python
# AIが生成しがちなパターン1: Anyで全部受け取る
from typing import Any

def process_data(data: Any) -> Any:
    return data["result"]["value"]             # KeyErrorが潜んでいる

# パターン2: Optionalを考慮していない
def get_user_name(user_id: int) -> str:
    user = db.query(User).get(user_id)
    return user.name                           # userがNoneのときAttributeError
```

```python
# あるべき姿
from typing import Optional

def process_data(data: dict[str, dict[str, str]]) -> str:
    result = data.get("result")
    if result is None:
        raise ValueError("'result' key is missing from data")
    value = result.get("value")
    if value is None:
        raise ValueError("'value' key is missing from result")
    return value

def get_user_name(user_id: int) -> Optional[str]:
    user = db.query(User).get(user_id)
    if user is None:
        return None
    return user.name
```

### TypeScript: `any`の乱用

```typescript
// AIが生成しがちなパターン
async function processApiResponse(response: any): Promise<any> {
  const data = response.data;                  // dataが存在するか不明
  return data.items.map((item: any) => ({      // itemsがarrayか不明
    id: item.id,
    name: item.name,
  }));
}
```

```typescript
// あるべき姿
interface ApiItem {
  id: string;
  name: string;
}

interface ApiResponse {
  data: {
    items: ApiItem[];
  };
}

async function processApiResponse(response: ApiResponse): Promise<Pick<ApiItem, "id" | "name">[]> {
  return response.data.items.map((item) => ({
    id: item.id,
    name: item.name,
  }));
}
```

### Go: `interface{}`と型アサーション

```go
// AIが生成しがちなパターン
func ProcessPayload(payload interface{}) interface{} {
    m := payload.(map[string]interface{})      // panicの可能性
    result := m["result"].(map[string]interface{})
    return result["value"]
}
```

```go
// あるべき姿
type Payload struct {
    Result ResultData `json:"result"`
}

type ResultData struct {
    Value string `json:"value"`
}

func ProcessPayload(payload Payload) (string, error) {
    if payload.Result.Value == "" {
        return "", fmt.Errorf("payload.result.value is empty")
    }
    return payload.Result.Value, nil
}
```

### 型安全を強制する設定

| 言語 | ツール | 設定 | 効果 |
|------|--------|------|------|
| Python | mypy | `disallow_any_explicit = true` | 明示的なAnyを禁止 |
| TypeScript | tsconfig | `"strict": true, "noImplicitAny": true` | 暗黙のanyを禁止 |
| Go | go vet | デフォルト | 型アサーションの安全性チェック |

```toml
# Python: pyproject.toml
[tool.mypy]
disallow_any_explicit = true
disallow_any_generics = true
warn_return_any = true
```

```json
// TypeScript: tsconfig.json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true
  }
}
```

**言語を超えた教訓**: 型を曖昧にするコードは、言語が提供する型システムを無効化する行為です。strictモードを最初から有効にすれば防げます。

---

## カテゴリ6: その他（8件）― 個別だが示唆的なケース

残り8件は明確なカテゴリに分類しにくいものでしたが、いくつか示唆的なケースがありました。

| 件数 | 内容 | 原因 |
|------|------|------|
| 3件 | ハードコードされた設定値 | 環境変数の管理方針が仕様になかった |
| 2件 | 未使用のimport | lintで検出可能だったが設定が甘かった |
| 2件 | 非効率なDB問合せ（N+1） | パフォーマンス要件が仕様になかった |
| 1件 | 競合状態（race condition） | 並行処理の要件が明記されていなかった |

これらも「仕組みで防げたか」という視点で見ると、ほとんどが「はい」です。

---

## 言語を超えた共通構造: 78件を「仕組みで防げたか」で再分類する

78件を「どうすれば防げたか」で再分類してみます。

```
===== 防止策による再分類（78件） =====

lint strict           35件  ████████████████████████████░░ 45%
  print残留(23) + bare except(12)

仕様書の事前作成      15件  ████████████░░░░░░░░░░░░░░░░░░ 19%
  仕様齟齬(15)

テスト基盤            11件  █████████░░░░░░░░░░░░░░░░░░░░░ 14%
  デグレ(11)

型チェックstrict       9件  ███████░░░░░░░░░░░░░░░░░░░░░░░ 12%
  型安全(9)

その他の仕組み         8件  ██████░░░░░░░░░░░░░░░░░░░░░░░░ 10%
  ハードコード(3) + import(2) + N+1(2) + race(1)

合計: 78件
```

注目すべきは、**lint strictだけで45%（35件）が防止可能**だったことです。最も効果が大きく、最も導入コストが低い。これを最初にやるべきでした。

### 言語別の対応表

| 防止策 | Python | TypeScript | Go |
|--------|--------|------------|-----|
| lint strict | ruff (`T201`, `E722`) | ESLint (`no-console`, `no-empty`) | forbidigo, errcheck |
| 型チェック | mypy --strict | tsc --strict | go vet (標準) |
| テスト | pytest + coverage | vitest / jest | go test -race |
| フォーマッタ | ruff format | prettier | gofmt (標準) |
| CI統合 | GitHub Actions | GitHub Actions | GitHub Actions |

言語が違っても、必要な仕組みの構成は同じです。「lint + 型チェック + テスト + CI」の4点セットが、どの言語でもバグの大半を防ぎます。

---

## 抽象原則: AIが書くコードの問題は、開発プロセスの問題である

78件を分析して到達した結論はこうです。

**AIが書くコードの品質は、AIの能力ではなく、開発プロセスの整備度に依存する。**

- lint設定がなければ、AIはprint文を残す。人間も残す。
- 仕様が曖昧なら、AIは曖昧に解釈する。人間も曖昧に解釈する。
- テストがなければ、AIはデグレを起こす。人間もデグレを起こす。
- 型チェックがなければ、AIは型を曖昧にする。人間も曖昧にする。

AIを「品質が低い」と批判する前に、品質を担保する仕組みがあるかどうかを確認すべきです。仕組みがなければ、誰が書いても同じ問題が起きます。

78件のバグのうち70件以上が「仕組み」で防止可能でした。これは「AIが悪い」のではなく、「私が品質基盤のない状態でAIに開発してもらっていた」ことが原因です。

---

## この経験から作ったもの

78件のバグ分析から、「仕組みで品質を作り込む」ことを体系化した**SFAD（Spec-First AI Development）**という開発手法を作りました。

核となる考え方は3つです。

1. **Day 0にlint strict + CI + テスト基盤を整える** ― コードを書く前にガードレールを置く
2. **仕様を先に書いてからコードを書く** ― Example Mappingで要件を構造化する
3. **既存コードから仕様を逆算する** ― テストのないコードに後から品質を注入する

詳細は後続の記事で書いていきますが、まずは「78件のバグの45%はlint一発で防げた」という事実を持ち帰っていただければと思います。

最初にやるべきは、高度なテスト戦略でも精巧な仕様書でもなく、`ruff`や`ESLint`の設定ファイルを1つ追加することです。

---

この記事はSFAD（Spec-First AI Development）シリーズの一部です。
