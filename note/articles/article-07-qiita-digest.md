---
title: 78バグから導いた7つの設計原則 ― AI時代のコード品質ガイドライン（ダイジェスト版）
tags:
  - AI駆動開発
  - 設計原則
  - ClaudeCode
  - TDD
  - コード品質
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---

# 78バグから導いた7つの設計原則 ― AI時代のコード品質ガイドライン（ダイジェスト版）

## TL;DR

- 78件のバグの根本原因は3つ: 品質基盤の欠如(59%)、仕様の不在(19%)、テスト基盤の不在(14%)
- 7つの設計原則のうち**最初の3つ**を詳細解説（Day 0品質基盤、仕様ファースト、テスト駆動）
- 各原則に対応するバグ件数と、具体的な防止策をコード付きで紹介

---

78件のバグを分析し終えたとき、同じ問題が違う形で繰り返されていることに気づきました。問題はバグではなく、判断基準の不在だったのです。

この記事では、78件のバグから導いた7つの設計原則のうち、最初の3つを詳しく紹介します。根本原因の再分類から始めて、各原則がどのバグに対応し、どう実践するかを解説します。

> **この記事はダイジェスト版です。** 原則4〜7の詳細、実装判断フレームワーク、チーム導入ロードマップ、原則が矛盾するときの解決手順については[noteの完全版](https://note.com/because_and_so)で公開しています。

---

## バグ分析から見えた共通構造

78件を最初にカテゴリ分けしたとき、6つに分類しました。print残留23件、仕様齟齬15件、bare except 12件、テスト不足11件、型安全9件、その他8件。

しかし、もう一段深い分析をしました。「そもそもなぜこのバグが生まれたのか」を根本原因で再分類したのです。

```
===== 根本原因による再分類（78件） =====

品質基盤の欠如       46件  ████████████████████████████████░░ 59%
  print残留(23) + bare except(12) + 型安全(9) + その他(2)

仕様の不在           15件  ██████████░░░░░░░░░░░░░░░░░░░░░░░░ 19%
  仕様齟齬(15)

テスト基盤の不在     11件  ███████░░░░░░░░░░░░░░░░░░░░░░░░░░░ 14%
  デグレ(11)

その他                6件  ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  8%
  ハードコード(3) + N+1(2) + race condition(1)

合計: 78件
```

この再分類で見えたのは、78件のバグのうち59%、つまり46件が「品質基盤がDay 0にあれば防げた」という事実です。lint、型チェック、CIの3つだけで、半分以上のバグが生まれなかったのです。

---

## 原則1: Day 0に品質基盤を置く

### バグとの対応

46件の内訳を改めて整理します。

- print残留: 23件 --- `ruff T201` / `eslint no-console` / `forbidigo` で機械的に防止可能
- bare except: 12件 --- `ruff E722` / `eslint no-empty` / `errcheck` で機械的に防止可能
- 型安全: 9件 --- `mypy --strict` / `tsc --strict` / `go vet` で防止可能
- その他: 2件 --- 未使用import(2件)、lint設定で防止可能

46件全てが「lintと型チェックを最初から入れていれば防げた」バグです。

### 言語別の品質基盤

Python・TypeScript・Go・Rustの4言語の設定例を紹介します。

**Python**

```toml
# pyproject.toml
[tool.ruff]
target-version = "py312"

[tool.ruff.lint]
select = [
    "E",      # pycodestyle
    "F",      # pyflakes
    "T20",    # print検出（T201: print, T203: pprint）
    "B",      # flake8-bugbear（B001: bare except）
    "BLE001", # blind except検出
    "ANN",    # 型アノテーション強制
    "S",      # bandit（セキュリティ）
    "F841",   # 未使用変数
]

[tool.ruff.lint.per-file-ignores]
"tests/*" = ["ANN", "S101"]

[tool.mypy]
strict = true
disallow_any_explicit = true
disallow_any_generics = true
warn_return_any = true
```

**TypeScript**

```json
// .eslintrc.json
{
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/strict-type-checked"
  ],
  "rules": {
    "no-console": "error",
    "no-empty": ["error", { "allowEmptyCatch": false }],
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-unused-vars": "error"
  }
}
```

**Go**

```yaml
# .golangci.yml
linters:
  enable:
    - errcheck       # 未処理のerrorを検出
    - govet          # 標準的なバグ検出
    - forbidigo      # fmt.Print系を禁止
    - unused         # 未使用変数/関数
    - gosec          # セキュリティ

linters-settings:
  forbidigo:
    forbid:
      - pattern: "fmt\\.Print.*"
        msg: "fmt.Print系は禁止です。slogを使ってください"
```

### 投資回収期間の計算

品質基盤は「いつ元が取れるか」を計算できます。

- 品質基盤の初期構築コスト: 約4時間（CI + lint + 型チェック + pre-commit）
- 1件のlint違反バグの修正コスト: 約30分
- 1件の型安全バグの修正コスト: 約1時間

```
lint系の場合:
  4時間 / 0.5時間 = 8件
  → 8件のlint違反バグを防いだ時点で元が取れる

私のプロジェクトでは:
  lint系: 35件 x 0.5時間 = 17.5時間
  型安全: 9件 x 1時間 = 9時間
  合計: 26.5時間の節約

  初期投資: 4時間
  投資回収率: 26.5 / 4 = 662%
```

4時間の投資で26.5時間のリターン。これが「Day 0に入れる」理由です。

---

## 原則2: Discoveryが先、コードが後

### バグとの対応

15件の仕様齟齬を再分析しました。

- 暗黙の前提条件が伝わっていなかった: 8件
- 具体的な条件が未定義だった: 4件
- エラー時の挙動が未定義だった: 3件

全てに共通するのは「具体例（Example）がなかった」ことです。

### Example Mappingの3つのレベル

私が実際に使い分けている3つのレベルを紹介します。

**Level 1: Question List（5分）**

最もシンプルな形式です。機能名だけ書いて、「まだ決まっていないこと」をリストアップするだけです。

```
機能: お問い合わせ一覧

Questions:
- ページネーションは必要か？
- 1ページ何件？
- ソートは？
- 0件のときの表示は？
- 検索スコープは？
- 削除済みデータの扱いは？
```

**Level 2: Rule + Example（30分）**

BDDの文脈でMatt Wynneが提唱した標準的なExample Mappingです。

```
Story: 管理者として、お問い合わせ一覧を見たい

Rule 1: 一覧はページネーションされる
  Example A: 20件以下 → ページネーションなし
  Example B: 21件以上 → ページネーション表示
  Example C: 0件 → 「お問い合わせはありません」と表示

Rule 2: 各行をクリックすると詳細に遷移する
  Example A: ID "c-1" をクリック → /contacts/c-1 に遷移

Questions:
  - ソート機能は必要か？ → v1では不要
  - ページあたり件数は変更可能か？ → 20件固定
```

**Level 3: Given-When-Then + Test List（2時間）**

最も詳細な形式です。Level 2をさらに構造化し、テスト可能な形にします。

```
UC-1: ページネーション
  Given: 管理者がログイン済みで、お問い合わせが21件以上存在する
  When: お問い合わせ一覧ページにアクセスする
  Then: 20件が表示され、ページネーションが表示される
```

---

## 原則3: テストは仕様の表現として書く

### テスト名の品質

テスト名を読んだだけで「何の仕様か」がわかるかどうか。これが判断基準です。

**Python**

```python
# 悪い例: 実装の検証
def test_function_returns_true():
    assert is_valid(data) is True

# 良い例: 振る舞いの定義
def test_admin_can_view_all_contacts():
    admin = create_user(role="admin")
    contacts = get_contacts(user=admin)
    assert len(contacts) == total_count
```

**TypeScript**

```typescript
// 悪い例
it('works', () => {
  render(<ContactList />);
  expect(screen.getByText('お問い合わせ')).toBeInTheDocument();
});

// 良い例
it('displays error message when API returns 500', () => {
  mockApi.get('/contacts').reply(500);
  render(<ContactList />);
  expect(screen.getByText('データの取得に失敗しました')).toBeInTheDocument();
});
```

**Go**

```go
// 悪い例
func TestLogin(t *testing.T) {
    err := Login("user@example.com", "password123")
    assert.NoError(t, err)
}

// 良い例
func TestLogin_LocksAccount_After5FailedAttempts(t *testing.T) {
    for i := 0; i < 5; i++ {
        Login("user@example.com", "wrong-password")
    }
    err := Login("user@example.com", "correct-password")
    assert.ErrorIs(t, err, ErrAccountLocked)
}
```

### テスト名のテンプレート

```
Python: test_{主語}_{動作}_{条件}()
  例: test_admin_can_view_all_contacts()
  例: test_order_fails_when_stock_is_zero()

TypeScript: it('{条件}のとき、{結果}')
  例: it('displays error message when API returns 500')

Go: Test{主語}_{動作}_{条件}(t *testing.T)
  例: TestLogin_LocksAccount_After5FailedAttempts
```

---

## 原則4〜7: 見出しだけ紹介

ここから先の4原則は、noteの完全版で詳しく解説しています。

### 原則4: Test Listを育てる

Kent Beckが2023年に整理したCanon TDDの「Test List」概念。実装前にテストすべきシナリオを書き出し、実装中に発見したシナリオは `[ADDED]` マークで追加していく。

### 原則5: Double-Loopで安全網を作る

外側ループ（受け入れテスト）と内側ループ（ユニットテスト）。London School vs Chicago Schoolの使い分け判断。

### 原則6: 仕組みで防ぐ、人の規律に頼らない

「コードレビューで見つける」は再現性がない。人が2回以上同じ指摘をしたらlintルールにする。各言語のカスタムlintルールの作り方。

### 原則7: 複利を意識する

「とりあえず」の判断が6ヶ月後に223箇所の修正になった実例。技術的負債の複利効果の計算方法。

---

## noteの完全版で公開している内容

この記事の完全版では、残り4原則の詳細に加えて以下を公開しています。

- **判断フレームワーク**: 全7原則について「もし〜なら〜する」形式の判断基準
- **7原則の相互関係図**: 縦の流れ（基盤→仕組み→複利）と横の流れ（Discovery→テスト→実装）
- **チーム導入ロードマップ**: Week 1からMonth 3までの段階的導入計画
- **原則が矛盾するときの優先順位**: 3つのケーススタディ（スピード vs 品質、プロトタイプ vs 本番、Discovery vs フィードバック待ち）
- **効果測定**: バグ密度、CI成功率、リリース後バグ数の目標推移

この記事の完全版（判断フレームワーク/チーム導入ロードマップ/効果測定の全体）はnoteで公開しています → [noteの完全版はこちら](https://note.com/because_and_so)

---

この記事はSFAD（Spec-First AI Development）シリーズの一部です。

- [記事一覧・シリーズまとめはこちら](https://note.com/because_and_so)
