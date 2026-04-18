# 78個のバグから「仕様が先、コードが後」を体系化した話 — Claude Code Skill で BDD + TDD を自動化する

## TL;DR

- 78個のバグを分析したら、70件以上が「仕組み」で防げた問題だった
- 原因は個々のバグではなく、**品質基盤と仕様書の不在**
- BDD Discovery + Double-Loop TDD を AI 支援ワークフローに適応させた **SFAD** という手法を作った
- Claude Code の Skill 機能で実装し、コマンド1つで仕様定義からテスト駆動実装まで自動化した
- 既存コードから仕様を復元する「仕様リバースエンジニアリング」も含む

## きっかけ: 78件の Issue ふりかえり

ある業務システムのリリース後、Issue を全件洗い出した。

**78件。**

```
print 残留 → 23箇所
bare except → 12箇所
仕様の認識齟齬 → 15件
テスト不足によるデグレ → 11件
型安全でない箇所 → 9件
その他 → 8件
```

lint strict が入っていれば35件は消える。仕様書があれば15件は発生しない。テスト基盤があれば11件は検出される。

**問題は個々のバグではなく、品質基盤がないことだった。**

## 2つの問い

この78件から2つの問いが生まれた。

### 問い 1: 新しい機能を作るとき、どうすれば「仕様漏れ」を防げるか？

「お問い合わせ一覧を作って」→ そのまま実装 → レビューで「ソート機能は？」「0件のとき何出す？」「ページネーションは？」

**仕様が先ではなく、コードが先になっている。**

### 問い 2: 既にあるコードに仕様書がないとき、どうすればいいか？

```python
if failed_count >= 5:
    lock_account(user_id)
```

なぜ5回？コミットログ「認証機能実装」。PR説明は空。担当者は退職済み。

**コードは「何をしているか」を教えるが、「何をすべきか」は教えない。**

---

## SFAD — 仕様を先に書く開発手法

この2つの問いに対する答えが **SFAD（Spec-First AI Development）**。

3つの一次ソースに基づいている:

| 出典 | 取り入れたもの |
|------|-------------|
| **BDD** (Dan North / Cucumber) | Example Mapping で「ルール → 具体例 → 質問」を先に洗い出す |
| **Canon TDD** (Kent Beck 2023) | Test List → 1つ選ぶ → Red → Green → Refactor |
| **Double-Loop TDD** (Freeman & Pryce) | 外側=受け入れテスト、内側=ユニットテスト |

これを AI 支援ワークフローに適応させた。**人間が決めるのは「何が正解か」だけ。残りは AI が実行する。**

## 6つのコマンド

SFAD は Claude Code の Skill として実装した。6つのサブコマンドで構成される:

```
/sfad init     — Day 0 に品質基盤を構築（CI, lint, test infra 等11項目）
/sfad cycle    — 1コマンドで Discovery → 仕様 → テスト → 実装まで全自動
/sfad spec     — Example Mapping + Given-When-Then で仕様定義
/sfad test     — 受け入れテスト + UCテストを自動生成（全 Red）
/sfad impl     — Double-Loop TDD で Red → Green
/sfad reverse  — 既存コードから仕様を抽出・確定（保守案件用）
```

### 全体像

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
```

**新規でも保守でも、最終的に同じ状態に到達する:**
`docs/specs/{feature}.md` が存在し、テストで保護されている。

---

## /sfad init — Day 0 に品質基盤を作る

78件中35件は lint strict で、11件はテスト基盤で防げた。**Day 0 に基盤を入れるだけで60%を予防できた。**

init は11項目を一括構築する:

```
 1. CI         — PR時に lint + type-check + test + build を自動実行
 2. Pre-commit — コミット前に lint + type-check を強制
 3. Lint       — print禁止、bare except禁止、any型禁止
 4. テスト基盤  — テストランナー + fixture + カバレッジ閾値70%
 5. ログ基盤    — 構造化ログ（JSON）+ グローバル例外ハンドラー
 6. セキュリティ — CORS + CSP + .env.example + .gitignore検証
 7. ヘルスチェック — /health + /health/ready
 8. Docker      — docker-compose で開発環境統一
 9. テンプレート  — Issue + PR テンプレート
10. ADR         — 技術的意思決定の記録
11. Dependabot  — 依存関係の脆弱性自動検知
```

`pyproject.toml`、`package.json`、`go.mod` 等からスタックを自動検出し、各項目の実装方法を決定する（10スタック対応）。

---

## /sfad cycle — メインコマンド: 仕様から実装まで1コマンド

cycle は BDD 3 Practices + Double-Loop TDD を8 Phaseで実行する:

```
Phase 1: Discovery（Example Mapping）→ AI が PO/Dev/QA 視点で仕様発見
Phase 2: Spec + Test List → ユーザー承認ゲート
Phase 3: 受け入れテスト生成 → Red
Phase 4: UC単位 TDD → Red → Green → Refactor
Phase 5: 状態パターン TDD
Phase 6: エッジケース検出 → ユーザー承認
Phase 7: 受け入れテスト確認 → Green
Phase 8: サマリー
```

### Discovery: 何を作るかを先に決める

AI が Example Map を提案する:

```
Story: 管理者として、お問い合わせ一覧を見たい

Rule 1: 一覧はページネーションされる
  - 20件以下 → ページネーションなし
  - 21件以上 → ページネーション表示

Rule 2: 各行クリックで詳細に遷移

Question: ソート機能は必要か？
```

**Question が0になるまで繰り返す。** コードを書く前に「何を作るか」の全貌が見える。

### 人間の介入ポイント

cycle は全自動だが、3箇所でユーザーの判断を求める:

| Phase | 何を判断するか |
|-------|-------------|
| Phase 1 | Example Map の確認。Question への回答 |
| Phase 2 | 仕様 + Test List の承認（**承認なしでは先に進まない**） |
| Phase 6 | エッジケース追加テストの承認 |

**「何を作るか」を決めるのは人間。「どう作るか」を実行するのは AI。**

---

## /sfad reverse — 既存コードから仕様を復元する

cycle は新規機能用。では「既にコードがあるが仕様書がない」場合は？

**reverse はコード → 仕様の逆方向プロセス。7 Phaseで構成される。**

```bash
/sfad reverse "認証機能"
/sfad reverse @app/api/v1/auth.py
```

### 7 Phase の概要

| Phase | やること | 目的 |
|-------|---------|------|
| 1 | 対象コード特定 | 分析範囲を決める |
| 2 | 振る舞い抽出 | コードから事実を読み取る |
| 3 | Example Map 生成 | 事実を構造化する |
| 4 | 不明点・矛盾検出 | 問題を炙り出す |
| **5** | **ユーザーバリデーション** | **「正解」を決める（最重要）** |
| 6 | 仕様書確定 | 合意を文書化する |
| 7 | テスト生成 | 仕様をテストで保護する |

### 確信度と問題分類

各 Rule に確信度を付与:
- **高**: コードとテスト両方で確認
- **中**: コードにあるがテスト不十分
- **低**: 意図不明、矛盾あり

6カテゴリで問題を自動分類:

| タグ | 例 |
|------|---|
| `[DEAD CODE]` | 呼ばれていない関数 |
| `[SECURITY]` | レート制限なし |
| `[INCONSISTENT]` | テストとコードの不一致 |
| `[MISSING]` | 未処理の境界条件 |
| `[IMPLICIT]` | コメントなしのマジックナンバー |
| `[UNDOCUMENTED]` | テストもコメントもない振る舞い |

### 実例: ある業務システムの認証機能に実行した結果

実際に認証機能に対して `/sfad reverse` を実行した結果:

- **9つの Rule** を抽出（ログイン、アカウントロック、OTP、パスワードポリシー等）
- **4つの Question** を検出（OTP常時有効は一時的？ レート制限は？等）
- **11件の問題** を検出:
  - `[SECURITY]` × 3: パスワードリセットのレート制限なし、`ast.literal_eval()` でのトークンパース、本番ログへのトークン露出
  - `[DEAD CODE]` × 2: 重複関数、no-op エンドポイント
  - `[INCONSISTENT]` × 3: テストとコードの引数不一致
  - `[MISSING]` × 1: OTP ブルートフォース対策なし
  - `[IMPLICIT]` × 1: ロック回数5回の根拠不明
  - `[UNDOCUMENTED]` × 1: 指数バックオフ計算式にコメントなし

**11件全てが「仕様書があれば防げた」問題だった。**

---

## テスト流派の使い分け

SFAD はテスト生成時に London School と Chicago School を層ごとに使い分ける:

| 層 | 流派 | 理由 |
|----|------|------|
| FE ページ/コンポーネント | **London**（モック多め） | hooks/API は外部依存 → モックで分離 |
| BE エンドポイント | **London** | Service層をモック、API契約を検証 |
| BE サービス層 | **Chicago**（状態検証） | ビジネスロジックの結果を検証 |
| BE ドメインモデル | **Chicago** | 純粋な状態変換。モック不要 |

---

## Claude Code Skill として実装する意味

### なぜドキュメントではなく Skill か

開発手法をドキュメントに書いても、読まれない。読まれても、守られない。

Skill にすることで:
- **コマンド1つで手法が強制される**: `/sfad cycle` で BDD → TDD まで自動実行
- **AI がゲートを守る**: Phase 2 で承認がなければ実装に進まない
- **手順が属人化しない**: Markdown に全手順が定義されている

### AI と人間の役割分担

| AI が担うこと | 人間が担うこと |
|-------------|-------------|
| コードの読み取り・分析 | 「何が正解か」の判断 |
| Example Map の提案 | Example Map の承認・修正 |
| テストコードの生成 | テストシナリオの追加承認 |
| 実装コードの生成 | 仕様変更の意思決定 |
| 問題の検出・分類 | 問題への対応方針決定 |

**AI に仕様を決めさせない。AI は材料を揃え、人間が決定する。**

### Skill のファイル構成

```
~/.claude/skills/sfad/
  ├── SKILL.md          ← 理論的基盤、サブスキル一覧
  ├── init.md           ← 11項目 × 10スタック
  ├── cycle.md          ← 8 Phase（BDD + Double-Loop TDD）
  ├── spec.md           ← Example Mapping + Given-When-Then
  ├── test.md           ← Double-Loop テスト生成
  ├── impl.md           ← Canon TDD サイクル
  └── reverse.md        ← 7 Phase 仕様抽出

~/.claude/commands/sfad/
  ├── init.md 〜 reverse.md  ← 各コマンドの定義
```

---

## 7つの設計原則

SFAD のすべてのコマンドは以下の原則に基づいている:

1. **Day 0 に品質基盤**: CI + lint strict + test infra + logger = 4時間で78 Issue を予防
2. **Discovery が先、コードが後**: Example Mapping でルール/具体例/質問を先に洗い出す
3. **テストは仕様の表現**: 実装の検証ではなく、振る舞いの定義
4. **Test List を育てる**: 実装中に発見したシナリオはリストに追加
5. **Double-Loop で安全網**: 外側=機能が動く、内側=各部品が正しい
6. **仕組みで防ぐ**: 人の規律に頼らない。CI で機械的にブロック
7. **複利を意識**: 「とりあえず」の判断が6ヶ月後に223箇所の修正になる

---

## まとめ

78個のバグから学んだのは、**問題の根源は個々のバグではなく、品質基盤の不在だった**ということ。

SFAD はこれを6つのコマンドで解決する:

| 状況 | コマンド | 結果 |
|------|---------|------|
| Day 0 | `/sfad init` | 11項目の品質基盤 |
| 新機能の実装 | `/sfad cycle` | 仕様 + テスト + 実装を1コマンドで |
| 仕様書がない既存コード | `/sfad reverse` | コードから仕様を抽出・確定 |
| 仕様だけ定義したい | `/sfad spec` | Example Map + Given-When-Then |
| テストだけ生成したい | `/sfad test` | 受け入れテスト + UCテスト |
| 実装だけ進めたい | `/sfad impl` | Double-Loop TDD |

各コマンドの設計詳細、実際の認証機能から抽出した Example Map の完全版、Claude Code Skill の設計思想、そしてすぐに使えるファイル構成は note にまとめました。

**[note記事: 78個のバグから生まれた開発手法 — AI時代の「仕様が先、コードが後」を Claude Code Skill で実装した話](https://note.com/xxxxx)**

---

*この記事の手法は、実際の業務システム開発での78件のバグふりかえりから生まれ、Claude Code Skill として実装・運用されています。*
