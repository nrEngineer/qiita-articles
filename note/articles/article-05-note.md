# 金曜日の夜、ログが「空っぽ」だった ― AIが書いたコードで本番障害を起こした話

金曜日の夜21時、Slackの障害チャンネルに通知が飛んできました。

「決済ステータスの不整合が発生しています。対象ユーザー数: 不明」

「不明」── この2文字が一番怖かった。ログを見に行きました。何も残っていませんでした。

エラーが起きていたのは確実なのに、ログには正常系の記録しかない。犯人を探してコードを読み始めて、3時間後にようやく見つけたのが `except: pass` の一行でした。AIが書いたコードが、エラーをすべて飲み込んで、何事もなかったかのように処理を続けていたのです。

この夜から、私はAIが書いたコードを「動くかどうか」ではなく「壊れたとき何が起きるか」で見るようになりました。

---

## 21件の時限爆弾

翌週、コードベース全体をgrepしました。`except: pass`、空の`catch`ブロック、`_ = err`......。21件見つかりました。

全部テストをパスしていました。全部CIを通っていました。でも、金曜日の夜に起きたことを考えれば、これら21件は全て同じ種類の時限爆弾でした。そして驚いたのは、この問題がPythonだけではなかったことです。TypeScript、Go、Rust ── 4言語すべてに、構文は違えど同じ構造の「握りつぶし」が埋まっていました。

この記事では、あの金曜日の夜から何を学んだのかをお話しします。

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

**Python**:

```bash
# mypy --strict で全ての型チェックを有効化
mypy --strict src/
# Any の暗黙的使用、Optional のチェック漏れ、型ヒントの欠落が全て検出される
```

**TypeScript**:

```json
// tsconfig.json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true
  }
}
```

**Go**:

```bash
# Goは静的型付け言語なので基本的に型安全
# ただし interface{} の使用を制限するにはlintが必要
golangci-lint run --enable gocritic,govet
```

**Rust**:

```bash
# Rustはデフォルトで厳密な型チェックが有効
# clippy で追加のチェックを行う
cargo clippy -- -D warnings -W clippy::unwrap_used
```

**言語を超えた教訓**: 型が緩いコードは「問題の発見を遅らせるエラーの握りつぶし」の変形である。各言語の厳密モードを最初から有効にすることで、問題を書いた瞬間に検出できる。

---

## 「動くけど危ない」コードの見抜きパターン: 5つの共通兆候

4言語のパターンを横断して見ると、言語に依存しない共通の兆候が浮かび上がります。

### 兆候1: catch/exceptブロックが空、またはログなしで処理を続ける

```python
# Python
except:
    pass

except Exception:
    return None
```

```typescript
// TypeScript
catch (e) {}

catch (e) {
  return undefined;
}
```

```go
// Go
_ = err

if err != nil {
    return nil
}
```

```rust
// Rust
.unwrap()

.unwrap_or_default()  // デフォルト値で隠蔽
```

エラーが発生したことを誰にも伝えないコードは、全て「握りつぶし」です。

### 兆候2: 型が過度に緩い

- Python: `Any`, 型ヒントの欠落
- TypeScript: `any`, `as unknown as T`
- Go: `interface{}` の多用
- Rust: 不要な `Box<dyn Error>`, `dyn Any`

型が緩いコードは「何が入ってくるかわからない」状態です。実行時エラーの温床になります。

### 兆候3: エラー時にデフォルト値を返す

```python
except:
    return {}  # 空のdict
```

```typescript
catch (e) {
  return DEFAULT_CONFIG;  // デフォルト設定
}
```

```go
if err != nil {
    return &Config{}  // ゼロ値
}
```

```rust
.unwrap_or_default()
```

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

各言語には、エラーの握りつぶしを機械的に検出するルールがあります。

| 言語 | ツール | エラーハンドリング検出の主要ルール |
|------|--------|----------------------------------|
| Python | ruff | `B`（bare except検出）、`B904`（raise without from）、`ANN`（型ヒント欠落） |
| TypeScript | ESLint | `no-empty`（空catchブロック）、`no-explicit-any`、`strict-boolean-expressions` |
| Go | golangci-lint | `errcheck`（未チェックのエラー検出）、`check-blank: true`（`_ = err`の検出） |
| Rust | clippy | `unwrap_used = "deny"`、`expect_used = "warn"`、`panic = "deny"` |

これらのルールを有効にすると、この記事で挙げた21件のパターンの大半が書いた瞬間にエラーとして検出されます。lint設定の全体的な構成（除外ディレクトリの指定方法、CI組み込みのワークフロー）については、バグ分析の元記事で詳しく解説しています。

→ **Art.1「78バグの全分類」**（Qiita、無料）: 4言語のコピペ可能なlint設定ファイルとCIワークフローあり

**言語を超えた教訓**: エラーハンドリングの問題は「気をつける」では防げない。lintとCIで機械的にブロックする仕組みを入れることが唯一の確実な解決策である。

---

## Day 0に品質基盤を整える

78件のバグのうち、35件はlint strictの設定で防げました。

- print残留23件 → `T20`（Python）/ `no-console`（TypeScript）でブロック
- bare except 12件 → `B001`（Python）/ `errcheck`（Go）/ `clippy::unwrap_used`（Rust）でブロック

「後から入れればいい」と思っていましたが、それが間違いでした。後からlintを厳しくすると、既存コードにエラーが大量に出ます。修正コストが跳ね上がります。

エラーハンドリングの観点から初日に入れるべき設定の詳細（pyproject.toml、.eslintrc.json、.golangci.yml、Cargo.toml）は、バグ78件を全分類した記事にまとめています。段階的に既存コードへ適用する方法も含めてコピペ可能な形で公開しているので、設定ファイルが手元にない場合はそちらを参照してください。

→ **Art.1「78バグの全分類」**（Qiita、無料）: 言語別の初日設定ファイルはここ

CIでlintとテストを通さないとマージできない設定にすることで、AIが書いたコードは最初から品質基盤の上に乗ります。

**言語を超えた教訓**: 品質基盤は「後から入れる」のではなく「初日に入れる」もの。コードが1行もない状態で設定するのが最もコストが低い。

---

## noteでしか書けない話: AIを「信頼する」と「検証する」の間

あの金曜日の夜以来、AIが書いたコードとの向き合い方が変わりました。

以前は「AIすごい、こんなに速くコードが書ける」と素直に感動していました。でも21件の時限爆弾を見つけた後は、AIが書いたコードの `try-catch` ブロックを見るたびに身構えるようになりました。

これは正直なところ、あまり健全な状態ではありませんでした。

AIを使うメリットは開発速度です。でも、AIが書いたコードを一行一行疑ってチェックしていたら、手で書くのと変わりません。むしろ「AIが書いたコードを読む」という余計なステップが増えて、遅くなることすらあります。

私が辿り着いた答えは「信頼するが検証する」でした。AIのコード生成能力を信頼しつつ、エラーハンドリングのような「壊れたとき何が起きるか」に関わる部分だけは仕組みで検証する。

lint strictとCIは、その「仕組みによる検証」です。人間がコードを一行一行読まなくても、危険なパターンは機械的にブロックされる。AIが `except: pass` を書いても、CIが赤になって止まる。人間の注意力ではなく、システムの力で品質を担保する。

これが「AI時代のコードレビュー」の本質だと、今は考えています。全部を読む必要はない。でも「壊れ方」だけは仕組みで守る。

---

## おわりに

21件の時限爆弾を全部処理し終えたとき、不思議な達成感がありました。同時に、「これはAIが悪いのか？」という疑問が残りました。

AIは「止まらないコード」を書く。それはユーザーの指示がない限り、エラーで止まるよりも処理を続行するほうが「親切」だと判断しているからです。AIの立場から見れば、合理的な選択をしているだけです。

問題は、本番環境では「静かに壊れる」ほうが「うるさく止まる」よりもはるかに危険だということを、AIがまだ十分に理解していないこと。そして、それを教えるのは人間の仕事だということ。

lint設定とCIパイプラインは、AIに「ここでは止まってほしい」と伝える手段です。言葉ではなく、仕組みで伝える。それが、あの金曜日の夜から学んだ最も大事なことでした。

次回は、仕様書がない認証機能のコードをAIに読ませて仕様を逆算した話（仕様考古学）を紹介します。

---

この記事は、AI開発で78件のバグから生まれた設計手法 SFAD（Spec-First AI Development）シリーズの一部です。

4言語のコピペ可能なlint設定ファイルとコードレビューチェックリストは、Qiita版でまとめています。
