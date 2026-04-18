# 78個のバグから生まれた開発手法 — AI時代の「仕様が先、コードが後」を Claude Code Skill で実装した話

<!-- note 記事: 500円有料ライン付き -->
<!-- ▼▼▼ 無料パート ▼▼▼ -->

---

## 78個のバグが教えてくれたこと

ある業務システムのリリース後、ふりかえりで Issue を全件洗い出した。

**78件。**

分類してみると、ある共通点が浮かんだ。

```
print 残留 → 23箇所
bare except → 12箇所
仕様の認識齟齬 → 15件
テスト不足によるデグレ → 11件
型安全でない箇所 → 9件
その他 → 8件
```

78件中、**70件以上が「仕組み」で防げた問題だった。**

lint strict が入っていれば print と bare except の35件は消える。
仕様書があれば認識齟齬の15件は発生しない。
テスト基盤があればデグレの11件は検出される。

ここで気づいた。

**問題は個々のバグではなく、品質基盤がないことだ。** そして品質基盤の中核にあるのが**仕様書**だ。

---

## 2つの問いが生まれた

78件の Issue を眺めながら、2つの問いが浮かんだ。

### 問い 1: 新しい機能を作るとき、どうすれば「仕様漏れ」を防げるか？

「お問い合わせ一覧画面を作って」と言われて、そのまま実装を始めると何が起きるか。

実装した後にレビューで「ソート機能は？」「0件のとき何を表示する？」「ページネーションは？」と言われる。仕様を後から追加し、テストを後から書き、設計を後からやり直す。

**仕様が先ではなく、コードが先になっている。** これが仕様漏れの構造的原因だ。

### 問い 2: 既にあるコードに仕様書がないとき、どうすればいいか？

冒頭の「5回ロックはバグか仕様か」問題。コードは事実を語るが、意図は語らない。

```python
if failed_count >= 5:
    lock_account(user_id)
```

なぜ5回なのか。誰も知らない。コメントなし、PR説明なし、担当者退職済み。

**コードは「何をしているか」を教えるが、「何をすべきか」は教えない。**

---

## 答え: SFAD — 仕様を先に書く開発手法

この2つの問いに対する答えを体系化したものが **SFAD（Spec-First AI Development）** だ。

名前の通り、**仕様（Spec）が先（First）**。コードを書く前に仕様を確定し、テストを書き、それから実装する。

SFAD は3つの一次ソースに基づいている:

- **BDD** (Dan North / Cucumber) — Example Mapping で「ルール → 具体例 → 質問」を先に洗い出す
- **Canon TDD** (Kent Beck 2023) — Test List → 1つ選ぶ → Red → Green → Refactor → リスト完了まで
- **Double-Loop TDD** (Freeman & Pryce) — 外側ループ=受け入れテスト、内側ループ=ユニットテスト

これを **AI 支援ワークフロー** に適応させた。AI が PO/Dev/QA の3役を担い、Example Map を提案し、テストを生成し、実装をガイドする。

**人間が決めるのは「何が正解か」だけ。残りは AI が実行する。**

---

## 6つのコマンド、1つの思想

SFAD は Claude Code の **Skill** として実装した。6つのサブコマンドで構成される:

```
/sfad init     — Day 0 に品質基盤を構築（CI, lint, test infra, logger 等11項目）
/sfad cycle    — 1コマンドで Discovery → 仕様 → テスト → 実装まで全自動
/sfad spec     — Example Mapping + Given-When-Then で仕様定義
/sfad test     — 受け入れテスト + UCテストを自動生成（全 Red）
/sfad impl     — Double-Loop TDD で Red → Green
/sfad reverse  — 既存コードから仕様を抽出・確定（保守案件用）
```

### なぜ Claude Code Skill なのか

Claude Code（Anthropic 公式 CLI）には「Skill」という拡張機能がある。Markdown ファイルに手順を書いておくと、Claude がその手順に従ってタスクを実行する。

```
~/.claude/skills/sfad/cycle.md    ← 手順の定義
~/.claude/commands/sfad/cycle.md  ← コマンドの定義
```

SFAD の手法を Skill として定義することで、**手法が属人化せず、チーム全員が同じプロセスで開発できる。** 手法をドキュメントに書いても読まれない。Skill にすればコマンド一つで強制される。

---

## SFAD の全体像

```
新規プロジェクト                既存プロジェクト（仕様書なし）
      │                             │
  /sfad init                   /sfad reverse [feature]
      │                             │
      ├─────────────┐               │
      │             │               │
  /sfad cycle   /sfad spec    docs/specs/{f}.md ← 同一フォーマット
      │             │               │
      │         /sfad test     /sfad test（ギャップ分のみ）
      │             │               │
      │         /sfad impl     全 Green 確認
      │             │               │
      └─────────────┘               │
                                    │
              以後の変更: /sfad cycle [feature変更]
              → 仕様を修正 → テスト修正 → 実装修正
```

**新規でも保守でも、最終的に同じ状態に到達する:**
`docs/specs/{feature}.md` が存在し、テストで保護されている。

ここから先は、各コマンドの設計と実践を詳しく解説する。

<!-- ▼▼▼ ここから有料パート（500円）▼▼▼ -->

---

# 1. /sfad init — Day 0 に品質基盤を作る

78個のバグのうち35件は lint strict で、11件はテスト基盤で防げた。つまり **Day 0 に基盤を入れるだけで60%のバグを未然に防げた**。

「後でやる」は「4倍のコストでやる」と同義だ。

## 11項目の品質チェックリスト

`/sfad init` はプロジェクト初日にこの11項目を一括構築する:

```
 1. CI        — PR時に lint + type-check + test + build を自動実行
 2. Pre-commit — コミット前に lint + type-check を強制
 3. Lint       — print禁止、bare except禁止、any型禁止をコードレベルで禁止
 4. テスト基盤  — テストランナー + 共通fixture + カバレッジ閾値70%
 5. ログ基盤    — 構造化ログ（JSON）+ グローバル例外ハンドラー
 6. セキュリティ — CORS + CSP + .env.example + .gitignore検証
 7. ヘルスチェック — /health + /health/ready（BEのみ）
 8. Docker      — docker-compose で開発環境統一
 9. テンプレート  — Issue + PR テンプレートでプロセス標準化
10. ADR        — 技術的意思決定の記録
11. Dependabot — 依存関係の脆弱性自動検知
```

## スタック自動検出

init は `pyproject.toml`、`package.json`、`go.mod` 等からスタックを自動検出し、各項目の「どう実現するか」を決定する。

```
検出シグナル          スタック    lint              テスト        CI
pyproject.toml      Python     ruff              pytest       GitHub Actions
package.json+Next   Next.js    ESLint            Jest/Vitest  GitHub Actions
go.mod              Go         golangci-lint     go test      GitHub Actions
Cargo.toml          Rust       clippy            cargo test   GitHub Actions
```

10スタックに対応（Python, Go, Rust, Java, Kotlin, Ruby, Next.js, React, Vue, Angular, SvelteKit, Flutter）。

## なぜ「仕組み」で防ぐのか

78件の Issue の多くは「人の規律」に依存していた。「print を消してね」と口で言っても忘れる。「テストを書いてね」と頼んでも後回しにされる。

init はこれを「仕組み」に変える。lint strict で print を書いたらコミットできない。CI でテストが落ちたら PR がマージできない。**人間の規律ではなく、機械の強制力に頼る。**

---

# 2. /sfad cycle — 1コマンドで仕様から実装まで

SFAD のメインコマンド。1コマンドで以下を全自動実行する:

```
/sfad cycle お問い合わせ一覧
/sfad cycle --be "ユーザー登録API"
/sfad cycle --fe "ダッシュボード画面"
```

## 8つの Phase

```
BDD 3 Practices             Phase                        TDD
──────────────────────────────────────────────────────────────
Discovery                → Phase 1: Example Mapping
Formulation              → Phase 2: Spec + Test List       Canon TDD Step 1
Automation (outer)       → Phase 3: 受け入れテスト          Outer Loop: Red
Automation (inner)       → Phase 4: UC単位 TDD             Inner Loop: Red→Green
                         → Phase 5: 状態パターン TDD        Inner Loop: Red→Green
                         → Phase 6: エッジケース検出         Canon TDD Step 3
Acceptance test green    → Phase 7: 受け入れテスト確認       Outer Loop: Green
                         → Phase 8: サマリー
```

### Phase 1: Discovery — AI が3つの視点で仕様を発見する

BDD の Example Mapping を AI が実行する。AI が PO/Dev/QA の3役を担う:

- **PO視点**: 「この機能の主な利用者は？ 最も重要なビジネスルールは？」
- **Dev視点**: 「既存の類似機能は？ パフォーマンス要件は？」
- **QA視点**: 「データ0件の時は？ 同時操作は？ 不正入力は？」

AI が Example Map のドラフトを提案する:

```
Story: 管理者として、お問い合わせ一覧を見たい

Rule 1: 一覧はページネーションされる
  - 20件以下 → ページネーションなし
  - 21件以上 → ページネーション表示

Rule 2: 各行クリックで詳細に遷移
  - ID "contact-1" をクリック → /contacts/contact-1

Question: ソート機能は必要か？
```

**ユーザーが Question に回答し、Question が0になるまで繰り返す。**

ここがポイントだ。コードを書く前に「何を作るか」の全貌が見える。実装後に「ソート忘れてた」にはならない。

### Phase 2: Spec — Given-When-Then に変換

Example Map を仕様書に変換する。各 Rule が 1 UC（ユースケース）になる:

```
UC-1: ページネーション
  Given: データが25件存在する
  When: 一覧ページを開く
  Then: 20件が表示され、ページネーションが表示される

UC-2: 行クリック遷移
  Given: 一覧が表示されている
  When: ID "contact-1" の行をクリック
  Then: /contacts/contact-1 に遷移する
```

同時に **Test List** を作成する。これは Kent Beck の Canon TDD の核心で、「実装前にテストシナリオを全て列挙する」もの。

**ゲート: ユーザーが仕様を承認するまで先に進まない。**

### Phase 3-7: Double-Loop TDD

仕様が確定したら、テスト駆動開発に入る。

```
外側ループ: 受け入れテスト（機能全体）= Red で開始
  │
  ├── UC-1: Red → Green → Refactor → Test List更新
  ├── UC-2: Red → Green → Refactor → Test List更新
  ├── ...
  ├── S-1〜S-4: 状態パターン（ローディング/エラー/空/正常）
  ├── エッジケース検出 → ユーザー承認 → 追加テスト
  │
  └── 全 UC Green → 受け入れテストも Green
```

**AI は Uncle Bob の三法則を守る:**
1. 失敗テストなしにプロダクションコードを書かない
2. 失敗するのに十分な量以上のテストを書かない
3. テストを通すのに十分な量以上のプロダクションコードを書かない

### Phase 8: サマリー

```
SFAD Cycle 完了: お問い合わせ一覧

Discovery: 5 Rules, 12 Examples, 0 Questions
仕様: docs/specs/contact-list.md（UC×5, S×4）
Double-Loop: 外側Green, 内側11サイクル完了
Test List: 初期16 + 追加3 = 19/19 完了
テスト: 全 Green
```

**1コマンドで仕様書 + テスト + 実装が揃う。以後は仕様書が「正解」の定義になる。**

### 人間の介入ポイント

cycle は全自動だが、3箇所でユーザーの判断を求める:

- **Phase 1**: Example Map の確認。Question への回答
- **Phase 2**: 仕様 + Test List の承認（**承認なしでは先に進まない**）
- **Phase 6**: エッジケース追加テストの承認

**「何を作るか」を決めるのは人間。「どう作るか」を実行するのは AI。**

---

# 3. /sfad reverse — 既存コードから仕様を復元する

cycle は新規機能用だ。では「既にコードがあるが仕様書がない」場合はどうするか。

**reverse は cycle の逆方向: コード → 仕様。**

```
cycle:    要件 → 仕様 → テスト → 実装（新規）
reverse:  既存コード → 振る舞い抽出 → ユーザー承認 → 仕様確定（保守）
```

## 7つの Phase

### Phase 1: 対象コードの特定

機能名またはファイルパスを指定すると、AI が関連ファイルを自動探索する:

```bash
/sfad reverse "認証機能"              # AI が関連ファイルを探す
/sfad reverse @app/api/v1/auth.py    # パスから依存を辿る
```

### Phase 2-3: 振る舞い抽出 → Example Map 生成

コードから8カテゴリの情報を読み取り、Example Map に構造化する:

- エンドポイント/画面 → 機能の境界
- 条件分岐 → ビジネスルール
- エラーハンドリング → 異常系
- 定数・マジックナンバー → 暗黙のルール
- 型定義 → データ構造
- 既存テスト → 検証済みの振る舞い

各 Rule に **確信度** を付ける:

- **高** — コードとテスト両方で確認
- **中** — コードにあるがテスト不十分
- **低** — 意図不明、矛盾あり

### Phase 4: 問題検出

6カテゴリで自動分類:

- `[DEAD CODE]` — 呼ばれていない関数、no-op エンドポイント
- `[SECURITY]` — レート制限なし、デバッグ情報の露出
- `[INCONSISTENT]` — テストの期待値とコードの不一致
- `[MISSING]` — 未処理の境界条件
- `[IMPLICIT]` — コメントなしのマジックナンバー
- `[UNDOCUMENTED]` — テストもコメントもない振る舞い

### Phase 5: ユーザーバリデーション（最重要ゲート）

抽出結果を提示し、ユーザーが「正解」を決める:

- 「Rule 2 は正しい」→ 仕様として確定
- 「Rule 2 は間違い。3回にすべき」→ バグ発見。仕様を修正
- 「Rule 4 は使ってない」→ Dead Code 確定。安全に削除可能
- 「わからない」→ **最も危険。** 誰も正解を知らない機能がある

### Phase 6-7: 仕様確定 + テスト生成

`docs/specs/{feature}.md` に保存。cycle と同一フォーマット。`--with-tests` で既存テストのギャップ分だけ追加生成。

**reverse で仕様ができたら、以後の変更は cycle で仕様を更新する。**

---

## 実例: ある業務システムの認証機能に reverse を実行した結果

実際に FastAPI + PostgreSQL + Redis 構成の Web サービスで、認証機能に `/sfad reverse` を実行した:

### 抽出結果

- **9つの Rule** を抽出（ログイン、アカウントロック、OTP、パスワードポリシー、ログアウト、サインアップ、パスワードリセット等）
- **4つの Question** を検出
- **11件の問題** を検出:
  - `[SECURITY]` × 3: パスワードリセットのレート制限なし、`ast.literal_eval()` でのトークンパース、本番ログへのトークン露出
  - `[DEAD CODE]` × 2: 重複関数、no-op エンドポイント
  - `[INCONSISTENT]` × 3: テストとコードの引数不一致
  - `[MISSING]` × 1: OTP ブルートフォース対策なし
  - `[IMPLICIT]` × 1: ロック回数5回の根拠不明
  - `[UNDOCUMENTED]` × 1: 指数バックオフ計算式にコメントなし

**11件全てが「仕様書があれば防げた」問題だった。**

---

# 4. テスト流派の使い分け

SFAD はテストの書き方にも設計思想を持っている。London School と Chicago School を層ごとに使い分ける:

- **FE ページ/コンポーネント** → London（モック多め）: hooks/API は外部依存 → モックで分離
- **BE エンドポイント** → London: Service層をモック、API契約を検証
- **BE サービス層** → Chicago（状態検証）: ビジネスロジックの結果を検証
- **BE ドメインモデル** → Chicago: 純粋な状態変換。モック不要

この判断も Skill に定義してあるので、AI が自動的に適切な流派でテストを生成する。

---

# 5. 7つの設計原則

SFAD のすべてのコマンドは、以下の7原則に基づいている:

1. **Day 0 に品質基盤**: CI + lint strict + test infra + logger = 4時間で78 Issue を予防
2. **Discovery が先、コードが後**: Example Mapping でルール/具体例/質問を先に洗い出す
3. **テストは仕様の表現**: 実装の検証ではなく、振る舞いの定義
4. **Test List を育てる**: 実装中に発見したシナリオはリストに追加
5. **Double-Loop で安全網**: 外側=機能が動く、内側=各部品が正しい
6. **仕組みで防ぐ**: 人の規律に頼らない。CI で機械的にブロック
7. **複利を意識**: 「とりあえず」の判断が6ヶ月後に223箇所の修正になる

---

# 6. Claude Code Skill の設計

## なぜ Skill として実装するのか

開発手法をドキュメントに書いても、読まれない。読まれても、守られない。

Skill にすることで:
- **コマンド一つで手法が実行される**: `/sfad cycle` と打てば、BDD Discovery → TDD まで一気通貫
- **手順が属人化しない**: Markdown ファイルに全手順が書いてある
- **AI が手順を守る**: 人間が手順を飛ばしても、AI はゲートを通過させない（Phase 2 で承認がなければ実装に進まない）

## Skill のファイル構成

```
~/.claude/skills/sfad/
  ├── SKILL.md          ← スキル全体の定義（理論的基盤、サブスキル一覧）
  ├── init.md           ← /sfad init の手順（11項目 × 12スタック）
  ├── cycle.md          ← /sfad cycle の手順（8 Phase）
  ├── spec.md           ← /sfad spec の手順（Example Mapping + G-W-T）
  ├── test.md           ← /sfad test の手順（Double-Loop テスト生成）
  ├── impl.md           ← /sfad impl の手順（Canon TDD サイクル）
  └── reverse.md        ← /sfad reverse の手順（7 Phase 仕様抽出）

~/.claude/commands/sfad/
  ├── init.md           ← /sfad init のコマンド定義
  ├── cycle.md          ← /sfad cycle のコマンド定義
  ├── spec.md           ← /sfad spec のコマンド定義
  ├── test.md           ← /sfad test のコマンド定義
  ├── impl.md           ← /sfad impl のコマンド定義
  └── reverse.md        ← /sfad reverse のコマンド定義
```

## 設計の核心: AI と人間の役割分担

**AI が担うこと:**
- コードの読み取り・分析
- Example Map の提案
- テストコードの生成
- 実装コードの生成
- 問題の検出・分類

**人間が担うこと:**
- 「何が正解か」の判断
- Example Map の承認・修正
- テストシナリオの追加承認
- 仕様変更の意思決定
- 問題への対応方針決定

**AI に仕様を決めさせない。AI は材料を揃え、人間が決定する。**

これが SFAD の設計思想であり、各コマンドの Phase にゲートが設けてある理由だ。

---

# まとめ: 「とりあえず動くコード」から「仕様で守られたコード」へ

78個のバグから学んだのは、**問題の根源は個々のバグではなく、品質基盤の不在だった**ということ。

SFAD はこの問題を6つのコマンドで解決する:

- **プロジェクト Day 0** → `/sfad init` → 11項目の品質基盤が整う
- **新機能の実装** → `/sfad cycle` → 仕様書 + テスト + 実装が1コマンドで揃う
- **仕様書がない既存コード** → `/sfad reverse` → コードから仕様を抽出・確定
- **仕様だけ先に決めたい** → `/sfad spec` → Example Map + Given-When-Then
- **テストだけ生成したい** → `/sfad test` → 受け入れテスト + UCテスト
- **実装だけ進めたい** → `/sfad impl` → Double-Loop TDD で Red → Green

**新規でも保守でも、最終的に同じ状態に到達する:**

```
docs/specs/{feature}.md が存在し、テストで保護されている
```

仕様書があるから「バグか仕様か」で迷わない。
テストがあるからリファクタリングが怖くない。
品質基盤があるから「とりあえず」が「後で4倍」にならない。

**あなたの次のプロジェクトが Day 0 なら、`/sfad init` から始めてほしい。**
**既存プロジェクトで仕様がないなら、最も問い合わせが多い機能1つに `/sfad reverse` を試してほしい。**

最初の1機能の仕様書が完成したとき、チーム全員が「なぜもっと早くやらなかったのか」と思うだろう。

---

*この記事の手法は、実際の業務システム開発（FastAPI + PostgreSQL + Redis 構成、24以上のAPIエンドポイント）での78件のバグふりかえりから生まれ、Claude Code Skill として実装・運用されています。*
