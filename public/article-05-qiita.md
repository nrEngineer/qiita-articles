---
title: エラーを「握りつぶす」コードの見抜き方 ― Python・TypeScript・Go・Rustで学ぶエラーハンドリング設計
tags:
  - Python
  - TypeScript
  - エラーハンドリング
  - AI駆動開発
  - ClaudeCode
private: true
updated_at: '2026-03-01T19:02:18+09:00'
id: ea782ba7f73199d258c3
organization_url_name: null
slide: false
ignorePublish: false
---

## TL;DR

- AIは「止まらないこと」を優先するため、4言語すべてで**エラーを握りつぶすコード**を生成しがち
- Python `except: pass` / TS `catch (e) {}` / Go `_ = err` / Rust `.unwrap()` ── 構文は違えど構造は同じ
- 5つの共通兆候を知れば、どの言語のコードレビューでも「動くけど危ない」コードを見抜ける
- **lint strict + CI** で機械的にブロックする仕組みをDay 0に入れるのが唯一の確実な解決策
- 本記事の設定ファイルはすべてコピペ可能

## この記事でできること

| やりたいこと | 対応セクション |
|---|---|
| 4言語の「握りつぶし」パターンを一覧で把握したい | 各言語のパターン |
| レビューで危険なコードを見抜くチェックリストが欲しい | 5つの共通兆候 |
| lint設定をコピペしてすぐ使いたい | lint設定一覧 |
| Day 0に入れるべき設定を言語別に知りたい | Day 0設定 |

---

本番障害の原因を調べたら、`except: pass` が埋まっていました。

AIが書いた「動くけど危ないコード」を21件見つけた話です。そして、この問題はPythonだけの話ではありませんでした。

---

## 21件の「動くけど危ないコード」

ある業務システムをClaude Codeで開発して、リリース後に78件のバグを分類しました。その中に、テストは通る、CIも緑、動作も正常 ── でもコードレビューで見つけた瞬間に冷や汗が出るカテゴリがありました。

| カテゴリ | 件数 |
|---|---|
| bare except（例外の握りつぶし） | 12件 |
| 型安全の問題 | 9件 |
| **合計** | **21件** |

全部テストをパスしていました。全部CIを通っていました。でも本番環境に出した瞬間、時限爆弾になるコードでした。

この記事では、Python・TypeScript・Go・Rustの4言語で「エラーを握りつぶす」パターンを横断的に見ていきます。AIがなぜこういうコードを書くのか、どうやって見抜くのか、どう防ぐのかを整理します。

---

## 各言語の「エラーを握りつぶす」パターン

### Python: `except: pass` ― 全てを飲み込む闇

Pythonの「握りつぶし」は、bare exceptと呼ばれるパターンです。

```python
# AIが書いたコード（実際にあったもの）
def parse_config(config_str: str) -> dict:
    try:
        return json.loads(config_str)
    except:
        return {}  # 何が起きたか、誰にもわからない
```

このコードの何が問題か。`except:` は全ての例外をキャッチします。`json.JSONDecodeError` だけでなく、`KeyboardInterrupt`（Ctrl+C）や `SystemExit`（プロセス終了要求）まで握りつぶします。つまり、プロセスを正常に停止できなくなる可能性があります。

もう少し「惜しい」パターンもありました。

```python
# 一見まともに見えるが、まだ問題がある
def fetch_user(user_id: int) -> dict:
    try:
        response = api_client.get(f"/users/{user_id}")
        return response.json()
    except Exception:
        return None  # ログもなし、呼び出し元にも伝わらない
```

`except Exception:` は `except:` よりましです。`SystemExit` や `KeyboardInterrupt` は捕まえません。でも、ネットワークエラーなのか認証エラーなのかタイムアウトなのか、何が起きたかの情報が全て消えます。そして `return None` で何事もなかったかのように処理が続きます。

**AIがこのパターンを書く理由**: AIは「止まらないこと」を優先します。エラーが発生してクラッシュするより、何かしら値を返して処理を続けるコードを生成しがちです。「堅牢なコード」を「止まらないコード」と解釈しているように見えます。

```python
# あるべき姿
def parse_config(config_str: str) -> dict:
    try:
        return json.loads(config_str)
    except json.JSONDecodeError as e:
        logger.error(f"Config parse failed: {e}", exc_info=True)
        raise ConfigurationError(f"Invalid config format: {e}") from e
```

### TypeScript: `catch (e) {}` ― 空のcatchブロック

TypeScriptでは、空のcatchブロックが同じ問題を引き起こします。

```typescript
// AIが書きがちなコード
async function fetchUserProfile(userId: string) {
  try {
    const response = await fetch(`/api/users/${userId}`);
    return await response.json();
  } catch (e) {
    // 何もしない。エラーは虚空に消える。
  }
}
```

この関数は、ネットワークエラーが起きると `undefined` を返します。呼び出し元は「ユーザーが存在しない」のか「通信に失敗した」のか区別できません。

さらに厄介なのが、型安全を破壊するパターンとの組み合わせです。

```typescript
// @ts-ignore と空catchの合わせ技
async function processPayment(amount: number, token: string) {
  try {
    // @ts-ignore
    const result = await paymentGateway.charge(amount, token);
    return result as any;  // 型情報を全て捨てている
  } catch (e) {}
}
```

`// @ts-ignore` で型チェックを黙らせ、`as any` で型情報を捨て、空の `catch` でエラーを握りつぶす。三重の防御壁を全て無力化しています。

**AIがこのパターンを書く理由**: TypeScriptのcatchブロックでは、`e` の型がデフォルトで `unknown` です。適切に型を絞り込む処理を書くのが面倒なので、AIは空のcatchブロックで「とりあえず動く」コードを生成します。

```typescript
// あるべき姿
async function fetchUserProfile(userId: string): Promise<UserProfile> {
  try {
    const response = await fetch(`/api/users/${userId}`);
    if (!response.ok) {
      throw new ApiError(`Failed to fetch user: ${response.status}`);
    }
    return await response.json() as UserProfile;
  } catch (e) {
    if (e instanceof ApiError) {
      logger.error("API error fetching user profile", { userId, error: e.message });
      throw e;
    }
    logger.error("Unexpected error fetching user profile", { userId, error: String(e) });
    throw new ApiError("Failed to fetch user profile", { cause: e });
  }
}
```

### Go: `_ = err` ― 明示的に捨てるという選択

Goのエラーハンドリングは、他の言語とは設計思想が根本的に違います。Goには例外がありません。エラーは戻り値として返されます。そして、その戻り値を意図的に無視するコードが書けてしまいます。

```go
// AIが書きがちなコード
func parseConfig(data []byte) map[string]interface{} {
    var config map[string]interface{}
    _ = json.Unmarshal(data, &config)  // エラーを明示的に捨てている
    return config
}
```

`_ = err` は「このエラーを意識的に無視する」という宣言です。Goのコンパイラは未使用の変数を許しませんが、`_` に代入すれば通ります。AIはコンパイルを通すためにこのパターンを使います。

もう一つ、より危険なパターンがあります。

```go
// エラーを返さずに握りつぶす
func getUser(userID string) *User {
    user, err := db.FindUser(userID)
    if err != nil {
        return nil  // エラーを呼び出し元に伝えない
    }
    return user
}
```

この関数のシグネチャは `*User` のみを返します。エラーが起きても `nil` が返るだけです。呼び出し元は「ユーザーが見つからなかった」のか「データベース接続に失敗した」のか判別できません。

**AIがこのパターンを書く理由**: Goの `if err != nil` パターンは冗長になりがちです。AIは「コードをシンプルにしたい」という意図で、エラーハンドリングを省略することがあります。エラーを返す戻り値を追加すると関数シグネチャが変わり、呼び出し元も変更が必要になるため、「動く」ことを優先してエラーを握りつぶします。

```go
// あるべき姿
func getUser(userID string) (*User, error) {
    user, err := db.FindUser(userID)
    if err != nil {
        return nil, fmt.Errorf("failed to get user %s: %w", userID, err)
    }
    return user, nil
}
```

### Rust: `.unwrap()` ― panicという名の時限爆弾

Rustは型システムで「エラーが起きうること」を強制的に表現する言語です。`Result<T, E>` 型は成功と失敗を明示します。でも `.unwrap()` を使えば、その安全性を全て迂回できます。

```rust
// AIが書きがちなコード
fn parse_config(data: &str) -> Config {
    let config: Config = serde_json::from_str(data).unwrap();  // パース失敗でpanic
    config
}
```

`.unwrap()` は、`Result` が `Ok` なら値を取り出し、`Err` ならプログラムを即座に停止（panic）させます。開発中は問題になりませんが、本番環境でpanicが起きるとプロセスが落ちます。

`.expect("msg")` も本質的には同じです。

```rust
// .expect() もpanicする点は同じ
fn get_database_url() -> String {
    std::env::var("DATABASE_URL")
        .expect("DATABASE_URL must be set")  // 環境変数がなければpanic
}
```

メッセージがつくので `.unwrap()` よりましですが、本番でpanicする事実は変わりません。

**AIがこのパターンを書く理由**: Rustの `Result` を適切にハンドリングするには、`match` 式や `?` 演算子を使ってエラーを伝播させる必要があります。AIは「エラーが起きないだろう」という楽観的な判断で `.unwrap()` を使い、コードをシンプルに見せようとします。特にサンプルコードやプロトタイプの延長で本番コードを書くとき、このパターンが頻出します。

```rust
// あるべき姿
fn parse_config(data: &str) -> Result<Config, ConfigError> {
    let config: Config = serde_json::from_str(data)
        .map_err(|e| ConfigError::ParseFailed(e.to_string()))?;
    Ok(config)
}
```

**言語を超えた教訓**: どの言語にも「エラーを簡単に無視できる構文」があり、AIは「動くこと」を優先してその構文を使う傾向がある。

---

## 本番で何が起きるか

エラーの握りつぶしがテスト環境で見つからないのは、テスト環境では「正常系」が中心だからです。DB接続は安定している、外部APIは応答する、ネットワークは切れない。だからbare exceptがあっても問題が表面化しません。

本番は違います。

### シナリオ: 決済処理にbare exceptが入った場合

```python
# 実際にあったコードを簡略化
async def process_payment(order_id: str, amount: float):
    try:
        result = await payment_gateway.charge(amount)
        await db.update_order_status(order_id, "paid")
        return {"status": "success"}
    except:
        return {"status": "failed"}  # ログなし、リトライなし
```

このコードが本番で引き起こすシナリオは以下の通りです。

- 決済ゲートウェイへの通信がタイムアウト → 課金されたかどうか不明 → `{"status": "failed"}` が返る → ユーザーには「失敗」と表示 → でも実は課金されている
- DBの接続プールが枯渇 → ステータス更新に失敗 → でも課金は成功 → データの不整合が発生
- これらの全てでログが残らない → 障害調査ができない → 「原因不明」としか報告できない

### シナリオ: JSONパースのエラーを握りつぶした場合

```typescript
// 設定値をAPIから取得するコード
async function getUserPreferences(userId: string): Promise<Preferences> {
  try {
    const response = await fetch(`/api/preferences/${userId}`);
    const data = await response.json();
    return data;
  } catch (e) {
    return DEFAULT_PREFERENCES;  // 全ユーザーにデフォルト値
  }
}
```

APIがエラーを返し始めたとき、全ユーザーの設定がデフォルト値にリセットされます。ユーザーからの「設定が消えた」という問い合わせで初めて気づきます。ログには何も残っていません。

**言語を超えた教訓**: エラーを握りつぶすと「デバッグ不可能な状態」が生まれる。本番障害の調査で最も恐ろしいのは、手がかりが何もないことである。

---

## 型安全の言語横断パターン

エラーの握りつぶしと並んで、型安全の問題が9件ありました。型が緩いコードは、エラーの握りつぶしと同じ構造を持っています。問題の発見を遅らせるのです。

### Python: `Any` と `Optional` の落とし穴

```python
# AIが書いたコード: Any相当
def get_user(user_id):  # 型ヒントなし = 何でも入る
    user = db.query(User).get(user_id)
    return user.name  # userがNoneのときAttributeError

# AIが書いたコード: Optionalのチェック漏れ
def get_display_name(user: Optional[User]) -> str:
    return user.name  # Noneチェックなし

# AIが書いたコード: Union型の不適切な使用
def process_id(item_id: str | int) -> str:
    return str(item_id)  # 動くけど、呼び出し側が混乱する
```

Pythonは型ヒントがなくても動きます。だからAIは「動くコード」を書けてしまいます。型の厳密さは実行時には強制されないため、問題は本番で予期しない入力が来たときに初めて顕在化します。

### TypeScript: `any` と type assertionの乱用

```typescript
// AIが書いたコード: any型キャスト
function processApiResponse(response: any): UserData {
  return response.data.user;  // 実行時エラーの温床
}

// AIが書いたコード: optional chainingの過剰使用
function getUserEmail(user?: User): string {
  return user?.profile?.email ?? "unknown";
  // undefinedの連鎖を ?? で隠している
  // 本当にデータがないのか、バグなのか区別できない
}

// AIが書いたコード: type assertion
function parseResponse(data: unknown): Config {
  return data as Config;  // 実行時の検証なし
}
```

`any` はTypeScriptの型システムを完全に無効化します。`as` による型アサーションは「私はこの型だと知っている」という宣言ですが、実行時には何もチェックしません。AIは型エラーを黙らせるためにこれらを使います。

### Go: `interface{}` と型アサーションの不足

```go
// AIが書いたコード: interface{}で何でも受け取る
func processData(data interface{}) string {
    // 型アサーションなしでアクセス
    result := data.(map[string]interface{})  // panic の可能性
    return result["name"].(string)           // ここでも panic の可能性
}
```

Go 1.18以降は `any` が `interface{}` のエイリアスとして使えますが、問題の本質は変わりません。型アサーションに失敗すると即座にpanicします。

```go
// あるべき姿: 安全な型アサーション
func processData(data interface{}) (string, error) {
    result, ok := data.(map[string]interface{})
    if !ok {
        return "", fmt.Errorf("expected map, got %T", data)
    }
    name, ok := result["name"].(string)
    if !ok {
        return "", fmt.Errorf("expected string for name, got %T", result["name"])
    }
    return name, nil
}
```

### Rust: 不要な `Box<dyn Error>`

```rust
// AIが書いたコード: エラー型を曖昧にする
fn process_data(input: &str) -> Result<Output, Box<dyn std::error::Error>> {
    let parsed = parse(input)?;
    let validated = validate(parsed)?;
    Ok(transform(validated)?)
    // 全てのエラーが Box<dyn Error> に丸められ、呼び出し側でパターンマッチできない
}
```

Rustでは `Box<dyn Error>` を使うと「何かしらのエラー」としか分からなくなります。呼び出し側でエラーの種類に応じた処理ができません。

```rust
// あるべき姿: 列挙型で明示的にエラーを定義
#[derive(Debug, thiserror::Error)]
enum ProcessError {
    #[error("Parse failed: {0}")]
    ParseFailed(String),
    #[error("Validation failed: {0}")]
    ValidationFailed(String),
    #[error("Transform failed: {0}")]
    TransformFailed(String),
}

fn process_data(input: &str) -> Result<Output, ProcessError> {
    let parsed = parse(input).map_err(|e| ProcessError::ParseFailed(e.to_string()))?;
    let validated = validate(parsed).map_err(|e| ProcessError::ValidationFailed(e.to_string()))?;
    Ok(transform(validated).map_err(|e| ProcessError::TransformFailed(e.to_string()))?)
}
```

### 各言語の型厳密モード

型安全の問題は、各言語の厳密モードを有効にすることで機械的に検出できます。

| 言語 | ツール / 設定 | 効果 |
|---|---|---|
| **Python** | `mypy --strict src/` | Any の暗黙的使用、Optional のチェック漏れ、型ヒントの欠落が全て検出される |
| **TypeScript** | `tsconfig.json` で `strict: true`, `noImplicitAny: true`, `strictNullChecks: true` | any型、暗黙的any、nullチェック漏れが全て検出される |
| **Go** | `golangci-lint run --enable gocritic,govet` | 静的型付けが基本だが、`interface{}` の使用をlintで制限できる |
| **Rust** | `cargo clippy -- -D warnings -W clippy::unwrap_used` | デフォルトで厳密な型チェックが有効。clippyで `.unwrap()` 等を追加チェック |

**言語を超えた教訓**: 型が緩いコードは「問題の発見を遅らせるエラーの握りつぶし」の変形である。各言語の厳密モードを最初から有効にすることで、問題を書いた瞬間に検出できる。

---

## 「動くけど危ない」コードの見抜きパターン: 5つの共通兆候

4言語のパターンを横断して見ると、言語に依存しない共通の兆候が浮かび上がります。

### 兆候1: catch/exceptブロックが空、またはログなしで処理を続ける

| 言語 | 握りつぶしパターン |
|---|---|
| Python | `except: pass` / `except Exception: return None` |
| TypeScript | `catch (e) {}` / `catch (e) { return undefined; }` |
| Go | `_ = err` / `if err != nil { return nil }` |
| Rust | `.unwrap()` / `.unwrap_or_default()` |

エラーが発生したことを誰にも伝えないコードは、全て「握りつぶし」です。

### 兆候2: 型が過度に緩い

| 言語 | 型が緩いパターン |
|---|---|
| Python | `Any`, 型ヒントの欠落 |
| TypeScript | `any`, `as unknown as T` |
| Go | `interface{}` の多用 |
| Rust | 不要な `Box<dyn Error>`, `dyn Any` |

型が緩いコードは「何が入ってくるかわからない」状態です。実行時エラーの温床になります。

### 兆候3: エラー時にデフォルト値を返す

| 言語 | デフォルト値パターン |
|---|---|
| Python | `except: return {}` |
| TypeScript | `catch (e) { return DEFAULT_CONFIG; }` |
| Go | `if err != nil { return &Config{} }` |
| Rust | `.unwrap_or_default()` |

デフォルト値を返すこと自体が悪いわけではありません。問題は「なぜデフォルト値が使われたのか」がログに残らないことです。

### 兆候4: ログなしでエラーを処理

エラーが発生した事実をどこにも記録せずに処理を続けるコードは、本番で「何が起きたかわからない」状態を作ります。ログがなければ、障害調査はコードリーディングから始めるしかありません。

### 兆候5: 複数の責務が1つの関数に集中

```python
# 1つの関数で: API呼び出し + パース + バリデーション + DB保存 + エラー処理
async def sync_user_data(user_id: str):
    try:
        response = await api.get(f"/users/{user_id}")
        data = response.json()
        validated = validate(data)
        await db.save(validated)
    except:
        pass  # 全部まとめて握りつぶし
```

責務が集中すると、エラーの原因を特定できません。どの処理で失敗したのかわからないまま、まとめて握りつぶされます。

**言語を超えた教訓**: 「動くけど危ない」コードの5つの兆候は、言語を問わず同じパターンで現れる。見抜く目を養えば、どの言語のコードレビューでも応用できる。

---

## 設計原則（言語に依存しない）

### Fail Fast, Fail Explicitly

エラーは即座に、明示的に処理する。これがエラーハンドリングの大原則です。

「Fail Fast」とは、エラーが発生したら可能な限り早い段階で検知して処理することです。エラーを握りつぶして先に進むと、問題の原因から遠い場所で症状が出ます。デバッグコストが跳ね上がります。

「Fail Explicitly」とは、エラーが何であるかを明示することです。「何かエラーが起きた」ではなく、「設定ファイルのJSON形式が不正」「データベース接続がタイムアウト」「認証トークンが期限切れ」と具体的に伝えます。

各言語での「Fail Fast, Fail Explicitly」の実装は以下の通りです。

```python
# Python: 具体的な例外 + ログ + 再raise
try:
    config = json.loads(config_str)
except json.JSONDecodeError as e:
    logger.error(f"Config parse failed at line {e.lineno}: {e.msg}")
    raise ConfigurationError(f"Invalid JSON: {e}") from e
```

```typescript
// TypeScript: 型ガード + カスタムエラー
try {
  const config = JSON.parse(configStr);
  if (!isValidConfig(config)) {
    throw new ConfigurationError("Config validation failed");
  }
} catch (e) {
  if (e instanceof SyntaxError) {
    logger.error("Config parse failed", { error: e.message });
    throw new ConfigurationError("Invalid JSON format", { cause: e });
  }
  throw e;  // 未知のエラーは再throw
}
```

```go
// Go: エラーラッピング + 呼び出し元への伝播
config, err := parseConfig(data)
if err != nil {
    return nil, fmt.Errorf("failed to load config: %w", err)
}
```

```rust
// Rust: Result型 + ? 演算子 + カスタムエラー型
let config: Config = serde_json::from_str(data)
    .map_err(|e| ConfigError::ParseFailed {
        source: e,
        context: format!("Failed to parse config from: {}", path),
    })?;
```

### 仕組みで防ぐ: lint strict + CI で機械的にブロック

個人の注意力に頼るのをやめることです。AIが何十個もの関数を書いてくれるとき、一個一個を人間が目で確認するのは現実的ではありません。

各言語のlint設定で、エラーの握りつぶしを機械的にブロックできます。

**Python: ruff**

```toml
# pyproject.toml
[tool.ruff.lint]
select = [
    "E",      # pycodestyle errors
    "W",      # pycodestyle warnings
    "F",      # pyflakes
    "B",      # flake8-bugbear
    "T20",    # flake8-print (print禁止)
    "S",      # flake8-bandit (セキュリティ)
    "UP",     # pyupgrade
    "ANN",    # flake8-annotations (型ヒント強制)
]

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101"]  # テストではassert許可

# B001: bare except の検出
# B904: raise without from の検出
# ANN001: 型ヒント欠落の検出
```

**TypeScript: eslint**

```json
{
  "rules": {
    "no-empty": "error",
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-unused-vars": "error",
    "@typescript-eslint/strict-boolean-expressions": "error",
    "no-console": "error"
  }
}
```

**Go: golangci-lint**

```yaml
# .golangci.yml
linters:
  enable:
    - errcheck      # 未チェックのエラーを検出
    - govet         # 怪しいコード構造を検出
    - staticcheck   # 静的解析
    - gosimple      # コード簡略化の提案
    - gocritic      # 追加の静的解析

linters-settings:
  errcheck:
    check-type-assertions: true  # 型アサーションの失敗もチェック
    check-blank: true            # _ = err を検出
```

**Rust: clippy**

```toml
# clippy.toml or Cargo.toml
[lints.clippy]
unwrap_used = "deny"        # .unwrap() を禁止
expect_used = "warn"        # .expect() を警告
panic = "deny"              # panic! を禁止
todo = "warn"               # todo! を警告
```

**言語を超えた教訓**: エラーハンドリングの問題は「気をつける」では防げない。lintとCIで機械的にブロックする仕組みを入れることが唯一の確実な解決策である。

---

## Day 0に品質基盤を整える

78件のバグのうち、35件はlint strictの設定で防げました。

| 検出対象 | 件数 | 検出ルール |
|---|---|---|
| print残留 | 23件 | `T20`（Python） / `no-console`（TypeScript） |
| bare except | 12件 | `B001`（Python） / `errcheck`（Go） / `clippy::unwrap_used`（Rust） |
| **合計** | **35件** | - |

「後から入れればいい」と思っていましたが、それが間違いでした。後からlintを厳しくすると、既存コードにエラーが大量に出ます。修正コストが跳ね上がります。

プロジェクト初日にやるべき設定を、言語別にまとめます。

**Python プロジェクト初日**:

```toml
# pyproject.toml
[tool.ruff.lint]
select = ["E", "W", "F", "B", "T20", "S", "ANN", "UP"]

[tool.mypy]
strict = true
warn_return_any = true
disallow_untyped_defs = true
```

**TypeScript プロジェクト初日**:

```json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noUncheckedIndexedAccess": true
  }
}
```

**Go プロジェクト初日**:

```yaml
# .golangci.yml
linters:
  enable:
    - errcheck
    - govet
    - staticcheck
    - gosimple
    - gocritic
    - exhaustive
```

**Rust プロジェクト初日**:

```toml
# Cargo.toml
[lints.clippy]
unwrap_used = "deny"
expect_used = "warn"
panic = "deny"
missing_docs = "warn"
```

**CI設定（全言語共通のパターン）**:

```yaml
# .github/workflows/ci.yml（概念的な例）
steps:
  - name: Lint
    run: |
      # 言語に応じたlintコマンド
      # Python: ruff check . && mypy --strict src/
      # TypeScript: eslint . && tsc --noEmit
      # Go: golangci-lint run
      # Rust: cargo clippy -- -D warnings

  - name: Test
    run: |
      # 言語に応じたテストコマンド
```

CIでlintとテストを通さないとマージできない設定にすることで、AIが書いたコードは最初から品質基盤の上に乗ります。

**言語を超えた教訓**: 品質基盤は「後から入れる」のではなく「初日に入れる」もの。コードが1行もない状態で設定するのが最もコストが低い。

---

## まとめ

21件の「動くけど危ないコード」から学んだことを整理します。

- エラーの握りつぶしは、Python・TypeScript・Go・Rustの全てに存在する。構文は違っても、「エラーを無視して処理を続ける」という構造は同じ。
- AIは「止まらないこと」を優先するため、エラーを握りつぶすコードを生成しがちである。
- 本番でエラーの握りつぶしが問題になるのは、ログが残らず「原因不明」の障害になるから。
- 5つの兆候（空catchブロック、過度に緩い型、デフォルト値のリターン、ログなし、責務の集中）を知っていれば、どの言語のコードレビューでも見抜ける。
- 「Fail Fast, Fail Explicitly」と「仕組みで防ぐ」という2つの設計原則は、言語に依存しない。
- 78件中35件はlint strictで防げた。品質基盤はDay 0に入れるべきである。

品質基盤ができたら、次の課題は「既存のコードに潜む問題をどう発見するか」です。次回は、仕様書がない認証機能のコードをAIに読ませて仕様を逆算した話（仕様考古学）を紹介します。

---

この記事は、AI開発で78件のバグから生まれた設計手法 SFAD（Spec-First AI Development）シリーズの一部です。

---

:::note info
このシリーズの有料記事（7つの設計原則 / 6コマンド設計思想 / Skill作成ガイド）はnoteで公開しています。
→ https://note.com/because_and_so
:::

:::note info
SFADシリーズ全10本の一覧はこちら。
→ https://note.com/because_and_so/m/me824ba1a6796
:::
