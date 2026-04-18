---
title: PRが大きすぎるとCodeRabbitもAIも諦める ― 差分サイズと検出率の関係
tags:
  - コードレビュー
  - CodeRabbit
  - AI駆動開発
  - GitHub
  - PR
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---

## TL;DR

- 6000 行の PR を CodeRabbit に投げたら、サマリしか返ってこず **致命的な認可漏れを 1 件も検出しなかった**
- 人間レビュアーも 6000 行を全部読むのは無理。注意力が均等に分散できず、critical な箇所が statistical noise に埋もれる
- 経験則: 差分 5000 行を超えると、人間も AI も検出率が **5% 以下** に落ちる
- 防ぐには **PR を 300〜500 行に分割する文化** が必要
- CodeRabbit の `path_instructions` で「endpoint には認可必須」と教えると、検出率が大幅に上がる

## この記事でできること

| やりたいこと | この記事で得られるもの |
|---|---|
| AI レビュアーを過信しないようにしたい | 差分サイズと検出率の経験則 |
| 大きい PR を物理的に防ぎたい | PR サイズの CI ゲート設定例 |
| 機能を縦に切る方法を知りたい | 17 PR 分割の実例 |
| CodeRabbit を本気で使いたい | `.coderabbit.yaml` のチューニング例 |

---

ある PR のレビュー依頼が来ました。スペックは以下の通り。

- **+3278 / -29 行**
- **60 ファイル超**
- マイグレーション 4 本
- 新規 API エンドポイント 9 本
- 新規モデル 3 個
- 外部 AI サービス連携追加
- 外部チャット連携追加
- バックグラウンドジョブ 2 個追加

CI は緑。CodeRabbit は「リリースノートを生成しました」とサマリだけ出して終了。一見「レビューも済んでマージ寸前」の PR でした。

実際に人間が読んだら、致命的問題が **4 件**、ロジックバグが **10 件**、設計問題が **7 件** ありました。CodeRabbit が見つけたのはゼロです。

なぜこうなるのか、何が起きているのかを書きます。

---

## 差分サイズと検出率の経験則

| 差分行数 | 人間レビュアーの検出率 | AI レビュアーの検出率 |
|---|---|---|
| < 200 行 | 80-90% | 70-80% |
| 200-500 行 | 60-70% | 50-60% |
| 500-1000 行 | 40-50% | 30-40% |
| 1000-2000 行 | 20-30% | 20-25% |
| 2000-5000 行 | 10-20% | 10-15% |
| **5000+ 行** | **5-10%** | **5%以下** |

これは経験則の数字ですが、肌感で合っていると思います。**5000 行を超えた時点で、人間も AI も「読んだフリ」になる**。critical な箇所が statistical noise に埋もれる。これは個人の能力差ではなく、人間と LLM の認知の限界です。

---

## CodeRabbit が今回見逃した理由

CodeRabbit (および類似の AI コードレビュアー) は内部的に:

1. 差分をファイル単位 or hunk 単位でチャンクに分割
2. 各チャンクを LLM に渡して指摘を生成
3. サマリを集約

この構造上、**ファイル横断の問題はほぼ検出できない**:

### 苦手 1: 「他と比べて抜けている」相対比較

```python
# 既存ファイル: 全エンドポイントに認可あり
@router.get("/items")
async def get_items(
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(deps.get_current_active_user),  # ← あり
):
    ...

# 新規ファイル: 認可なし
@router.post("/new-resource")
async def create_resource(
    db: AsyncSession = Depends(deps.get_db),  # ← user 依存なし
):
    ...
```

新規ファイルだけを見たら「認可がない」と指摘するのは難しい。**「他のエンドポイントには認可があるのに、ここにだけない」** という相対比較が AI レビュアーは苦手です。

### 苦手 2: 重複検出（同じロジックが 2 ファイルにある）

別ファイルにコピペされた計算ロジックは、チャンク分割後は別文脈になるので検出されません。

### 苦手 3: アーキテクチャレベルの判断

「Service 層が無い」「ロジックがハンドラに直書き」のような構造的な指摘は、差分の中だけ見たら無理。ベースラインのアーキテクチャ理解が必要。

### 苦手 4: 設定ファイル変更の影響範囲

```diff
- --disable=C0111,E1102,...
+ --disable=C0111,E1102,...,W0212,R0915,W1203
```

`.pre-commit-config.yaml` の diff は AI 的には「設定変更」程度の扱いで、影響範囲を推論しません。「lint 警告 20 個を黙らせた」という意味的な大事故であることに気付きません。

### 苦手 5: バイナリファイルの混入

```
new file: static/result_images/aaa.png
new file: static/result_images/bbb.png
... (18 枚)
```

バイナリは中身を見ないし、「なぜ画像がコミットされてるのか」を疑問視しません。

### 苦手 6: 数行の意味的な誤りが大量の他コードに埋もれる

```python
points=int(game_points)  # ← float を int に切り捨て
```

数行を見て「これは丸めだな」で終わります。「kill_multiplier=1.5 のとき 4.5pt が 4pt になる」までは推論しない（できる LLM もいるが、6000 行の中の数行に注意を向けるのが難しい）。

---

## 大きい PR を物理的に分割する

### 今回の PR を分割するなら 17 本

```
| #  | PR タイトル                                    | 行数 | 依存 |
| 1  | feat: domain types and pure functions        | 200 | -    |
| 2  | feat: migration for new tables (1 本に統合)   | 250 | -    |
| 3  | feat: SQLAlchemy repositories                 | 200 | 1,2  |
| 4  | feat: UseCase: assign team numbers            | 250 | 3    |
| 5  | feat: external AI client (image analysis)     | 200 | 1    |
| 6  | feat: API endpoints (read)                    | 250 | 4    |
| 7  | feat: API endpoints (write) + auth tests      | 300 | 6    |
| 8  | feat: image upload + AI analysis integration  | 300 | 5,7  |
| 9  | feat: scheduler integration                   | 200 | 4    |
| 10 | feat: scheduled jobs (with idempotency)       | 300 | 4    |
| 11 | feat: notification templates                  | 100 | -    |
| 12 | feat: notification integration                | 200 | 10,11|
| 13 | feat: ranking endpoint                        | 200 | 1    |
| 14 | feat: regression tests for existing flow      | 150 | 12   |
| 15 | feat: admin endpoints                         | 150 | 7    |
| 16 | docs: feature flow documentation              | 200 | -    |
| 17 | feat: dashboard integration                   | 200 | 13   |

合計 17 PR / 約 3650 行（平均 ~215 行）
```

このサイズなら **1 PR あたり 30 分でレビュー終了**。今の 6000 行は 1 週間かけても全部見切れません。

### 分割するメリット

各 PR が小さくなると:

1. **#7 (API write 系) は単独で「認可あるか？」が一目で分かる** → 認可漏れが必ず指摘される
2. **#1 (純粋関数) は単独で domain 層として独立して見える** → 「テストが import してない」が即バレ
3. **#10 (採番ジョブ) は単独で冪等性の議論ができる** → 「2 回走ったらどうなる？」と必ず問われる
4. **#5 (外部 AI 連携) は単独で「base64 不要」「タイムアウト長すぎ」が見える** → SDK 誤用が指摘される
5. **CodeRabbit も各 PR で別々に動く** → 集中力が分散しない → 検出率が上がる

---

## ハードガード: PR サイズで CI を落とす

人の規律に頼らず、**仕組みで防ぐ** のが現実解です。

### GitHub Actions の例

```yaml
name: PR Size Check

on:
  pull_request:
    branches: [main]

jobs:
  size-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - name: Calculate diff size
        id: diff
        run: |
          BASE=${{ github.event.pull_request.base.sha }}
          HEAD=${{ github.event.pull_request.head.sha }}
          ADDED=$(git diff --shortstat $BASE..$HEAD | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
          DELETED=$(git diff --shortstat $BASE..$HEAD | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0)
          TOTAL=$((ADDED + DELETED))
          echo "total=$TOTAL" >> $GITHUB_OUTPUT
          echo "PR diff: +$ADDED -$DELETED (total $TOTAL)"
      
      - name: Warn if over 1500 lines
        if: steps.diff.outputs.total > 1500
        run: |
          echo "::warning::PR diff is ${{ steps.diff.outputs.total }} lines. Consider splitting (target: <500)."
      
      - name: Fail if over 3000 lines
        if: steps.diff.outputs.total > 3000
        run: |
          echo "::error::PR diff is ${{ steps.diff.outputs.total }} lines. Hard limit is 3000. Please split."
          exit 1
```

これで:
- **1500 行超え** → 警告（注意喚起）
- **3000 行超え** → CI 失敗（マージ不可）

例外を許す場合は `[skip-size-check]` ラベルを使えるようにすると現実的です。

---

## CodeRabbit を本気で使うチューニング

CodeRabbit はデフォルト設定だと指摘が浅いです。`.coderabbit.yaml` でガイドラインを与えると検出率が大幅に上がります。

```yaml
reviews:
  profile: assertive  # デフォルトは chill、これで指摘が増える
  request_changes_workflow: true  # 重大指摘を Request Changes に
  high_level_summary: true
  poem: false  # 不要
  review_status: true
  collapse_walkthrough: false
  auto_review:
    enabled: true
  
  path_filters:
    - "!**/*.md"
    - "!**/static/**"
    - "!**/*.lock"
  
  path_instructions:
    - path: "app/api/**"
      instructions: |
        全てのエンドポイントに認証・認可があるか必ず確認すること。
        Depends(deps.get_current_active_user) または
        Depends(deps.get_current_active_superuser) が無い endpoint は
        セキュリティリスクとして必ず指摘すること。
        
        以下も確認:
        - リクエストボディに id, role, owner_id 等の内部フィールドを含めていないか (Mass Assignment)
        - PUT/DELETE のリソースが current_user のものか確認しているか (IDOR)
    
    - path: "app/services/**"
      instructions: |
        外部 API 呼び出しのタイムアウト・リトライ・エラーハンドリングを必ず確認。
        - 60 秒以上のタイムアウトは警告
        - try/except で例外を握りつぶしていないか
        - 外部ライブラリの private 属性 (`_xxx`) を使っていないか
    
    - path: "app/jobs/**"
      instructions: |
        ジョブの冪等性を必ず確認。
        - 二重実行されたら何が起きるか
        - DB unique 制約が設定されているか
        - エラー時に他のループ要素への影響が無いか
    
    - path: "alembic/versions/**"
      instructions: |
        マイグレーションの安全性を確認。
        - downgrade が正しく書かれているか
        - データ損失のリスク（DROP COLUMN, ALTER TYPE）
        - 既存データへの影響（NOT NULL 追加時のデフォルト値）
    
    - path: ".pre-commit-config.yaml"
      instructions: |
        lint ルールの新規 disable が追加されている場合、
        その理由を必ず質問する。「警告が出たから」は不十分。

chat:
  auto_reply: true
```

**ポイント**: `path_instructions` で「endpoint には認可必須」を明示する。これだけで CodeRabbit は次回から確実に「認可がない」と指摘するようになります。デフォルトの CodeRabbit は何もガイドラインを知らないので「これが普通」で流すのです。

**ガイドラインを与えるのはチームの責任**。CodeRabbit に「期待」だけして使うのは過信です。

---

## チームに「小さい PR 文化」を根付かせる

仕組み + 文化の両輪で進めるのが効きます。

### 1. PR テンプレに「分割計画」セクション

```markdown
## このPRのスコープ

- このPRは feature `xxx` の **n / N 番目** です
- 依存PR: #yyy
- 次のPR予定: #zzz
- 単独でリバート可能: yes / no
```

「単独でリバート可能じゃない」と書く時点で、それは分割が足りていない兆候です。

### 2. Stacked PR を活用

GitHub の「stack」機能 や `git-machete` / `Graphite` を使うと、依存 PR チェーンが楽に管理できます。各 PR は小さいまま、機能全体は段階的に積み上がります。

### 3. 「設計 PR」を最初に出す

大きい機能は **最初に設計だけの PR**（コード無し、ドキュメントだけ）を出して合意を取ってから実装 PR を分けます。設計 PR には:

- アクター × 権限マトリクス（threat.md）
- 失敗モード一覧（resilience.md）
- PR 分割計画（plan.md）

これを最初に出して approve を取ってから実装に入ると、後で揉めません。

### 4. 「1 PR = 30 分で読み切れる量」を規約化

定量基準として「30 分で読めない PR は分割」をチームルールにします。300〜500 行が現実的な上限。

---

## 「大きい PR 文化」が産むもの

逆に大きい PR を放置すると何が起きるか:

- **誰もちゃんと読まない** → 指摘が雑になる → 事故が起きる → 「だからレビューしっかりして」と言われる → でも次もまた大きい PR が来る → 悪循環
- **「approve するしかない雰囲気」** → ジュニアは「これだけ書いたんだから approve してほしい」と思い、シニアは「ここまで来たら direction 変えるのも酷」と思う → セキュリティホールがマージされる
- **CodeRabbit を含む AI レビュアーが諦める** → CI が緑、AI も approve、人間も approve → でもバグだらけ
- **学習機会の喪失** → ジュニアは「6000 行の PR を 1 個書く」より「100 行の PR を 60 個書く」方が、レビュアーから 60 倍のフィードバックを受けられる

---

## まとめ

- **5000 行を超えた PR は、人間も AI レビュアーも検出率が 5% 以下** に落ちる
- AI レビュアーは「他と比べて抜けている」相対比較・コード重複・アーキテクチャ判断・設定ファイル変更の意味づけ・バイナリ混入・数行の意味的誤り が **特に苦手**
- 防ぐには **PR を 300〜500 行に分割する文化** が必要
- 仕組みで強制するなら **GitHub Actions で 1500 行警告 / 3000 行 fail**
- CodeRabbit は `path_instructions` でガイドラインを与えると検出率が大幅に上がる
- 文化として「設計 PR を先に出す」「1 PR = 30 分で読み切れる量」を規約化する

**「CodeRabbit が approve したから安全」は幻想**です。AI レビュアーは、人間が読み切れない PR を読めません。読める粒度に切り分けるのは、コードを書く側の責任です。
