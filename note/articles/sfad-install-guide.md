# SFAD スキル インストールガイド

Claude Code に SFAD（Spec-First AI Development）スキルをグローバルインストールする手順書です。

---

## 前提条件

- Claude Code がインストール済みであること
- ターミナル（bash / zsh / PowerShell）が使えること
- `~/.claude/` ディレクトリが存在すること（Claude Code 初回起動時に自動作成される）

確認方法:

```bash
# Claude Code がインストールされているか確認
claude --version

# ~/.claude/ ディレクトリが存在するか確認
ls ~/.claude/
```

もし `~/.claude/` がなければ、Claude Code を一度起動してください:

```bash
claude
```

起動後に `exit` で終了すれば、`~/.claude/` が自動生成されます。

---

## Step 1: ディレクトリを作成する

SFAD スキルには2つのディレクトリが必要です。

```bash
# スキル本体（ロジック）
mkdir -p ~/.claude/skills/sfad

# コマンド定義（インターフェース）
mkdir -p ~/.claude/commands/sfad
```

### 2層構造の役割

```
~/.claude/
  ├── skills/sfad/       ← 「どう実行するか」（詳細な手順書）
  │   ├── SKILL.md       ← スキルのメタ情報・理論基盤
  │   ├── cycle.md       ← cycle の詳細実行手順
  │   ├── spec.md        ← spec の詳細実行手順
  │   ├── test.md        ← test の詳細実行手順
  │   ├── impl.md        ← impl の詳細実行手順
  │   ├── reverse.md     ← reverse の詳細実行手順
  │   └── init.md        ← init の詳細実行手順
  │
  └── commands/sfad/     ← 「何ができるか」（コマンドAPI定義）
      ├── cycle.md       ← /sfad cycle の引数・使用例
      ├── spec.md        ← /sfad spec の引数・使用例
      ├── test.md        ← /sfad test の引数・使用例
      ├── impl.md        ← /sfad impl の引数・使用例
      ├── reverse.md     ← /sfad reverse の引数・使用例
      └── init.md        ← /sfad init の引数・使用例
```

- **skills/** = AI が「どうやるか」を読む詳細手順書（100行〜300行）
- **commands/** = ユーザーが `/sfad xxx` と打ったときの入口定義（20〜40行）

---

## Step 2: スキルファイルを配置する

SFAD のスキルファイル一式を入手し、以下の通り配置してください。

### 配置するファイル一覧

#### skills/sfad/（7ファイル）

| ファイル | サイズ | 内容 |
|---------|-------|------|
| `SKILL.md` | 8KB | スキルのメタ情報、理論基盤、サブスキル一覧、7原則 |
| `cycle.md` | 7KB | BDD Discovery + Double-Loop TDD の8フェーズ全自動サイクル |
| `spec.md` | 9KB | Example Mapping + Given-When-Then による仕様定義 |
| `test.md` | 9KB | 受け入れテスト + UCテスト生成（Double-Loop構造） |
| `impl.md` | 9KB | Canon TDD サイクルによるテスト駆動実装 |
| `reverse.md` | 18KB | 既存コードから仕様を抽出する7フェーズ（保守案件用） |
| `init.md` | 18KB | Day 0 品質基盤構築（11項目 × 12スタック対応） |

#### commands/sfad/（6ファイル）

| ファイル | サイズ | 内容 |
|---------|-------|------|
| `cycle.md` | 2KB | `/sfad cycle` コマンドの引数・使用例・フェーズ要約 |
| `spec.md` | 2KB | `/sfad spec` コマンドの引数・使用例 |
| `test.md` | 2KB | `/sfad test` コマンドの引数・使用例 |
| `impl.md` | 2KB | `/sfad impl` コマンドの引数・使用例 |
| `reverse.md` | 3KB | `/sfad reverse` コマンドの引数・使用例 |
| `init.md` | 2KB | `/sfad init` コマンドの引数・使用例 |

### 配置コマンド（ファイルを入手済みの場合）

```bash
# skills ファイルをコピー
cp SKILL.md cycle.md spec.md test.md impl.md reverse.md init.md ~/.claude/skills/sfad/

# commands ファイルをコピー（ファイル名が同じなので別ディレクトリから）
cp commands/cycle.md commands/spec.md commands/test.md commands/impl.md commands/reverse.md commands/init.md ~/.claude/commands/sfad/
```

---

## Step 3: インストールを確認する

### 3-1. ファイルが正しく配置されているか確認

```bash
# skills ディレクトリの確認
ls -la ~/.claude/skills/sfad/
# → SKILL.md, cycle.md, spec.md, test.md, impl.md, reverse.md, init.md の7ファイル

# commands ディレクトリの確認
ls -la ~/.claude/commands/sfad/
# → cycle.md, spec.md, test.md, impl.md, reverse.md, init.md の6ファイル
```

### 3-2. SKILL.md のフロントマターを確認

```bash
head -5 ~/.claude/skills/sfad/SKILL.md
```

以下のように表示されればOK:

```yaml
---
name: sfad
description: "Spec-First AI Development (SFAD) - BDD Discovery + Double-Loop TDD を AI 支援ワークフローに適応させた開発手法。..."
---
```

### 3-3. Claude Code で動作確認

```bash
# 任意のプロジェクトディレクトリで Claude Code を起動
cd ~/your-project
claude
```

Claude Code 内で以下を入力:

```
/sfad
```

`cycle`, `spec`, `test`, `impl`, `reverse`, `init` のサブコマンド候補が表示されれば、インストール成功です。

---

## Step 4: 使ってみる

### 最初の一歩: /sfad init（品質基盤構築）

新規プロジェクトまたは既存プロジェクトで:

```
/sfad init
```

プロジェクトのスタック（Python, TypeScript, Go 等）を自動検出し、11項目の品質基盤（CI, lint, テスト基盤等）を構築します。

### メインコマンド: /sfad cycle（全自動サイクル）

```
/sfad cycle お問い合わせ一覧
/sfad cycle --be "ユーザー登録API"
/sfad cycle --fe "ダッシュボード画面"
```

Discovery → 仕様定義 → テスト生成 → テスト駆動実装 まで全自動で実行します。3箇所でユーザーの承認を求めます。

### 保守案件: /sfad reverse（仕様抽出）

```
/sfad reverse "認証機能"
/sfad reverse @app/api/v1/auth.py
```

既存コードから仕様を抽出し、仕様書を生成します。

---

## 6つのコマンド早見表

| コマンド | 用途 | いつ使う |
|---------|------|---------|
| `/sfad init` | 品質基盤構築 | プロジェクト開始時（Day 0） |
| `/sfad cycle` | 全自動サイクル | 新機能の実装（推奨） |
| `/sfad spec` | 仕様定義のみ | 仕様だけ先に決めたいとき |
| `/sfad test` | テスト生成のみ | 仕様書からテストだけ作りたいとき |
| `/sfad impl` | テスト駆動実装のみ | テストがあり、実装だけ進めたいとき |
| `/sfad reverse` | 仕様抽出 | 仕様書がない既存コードの保守 |

---

## ファイル構造の詳細解説

### SKILL.md の役割

SKILL.md はスキル全体の「マニフェスト」です。以下を含みます:

```yaml
---
name: sfad                    # スキルの識別子（ディレクトリ名と一致させる）
description: "説明文..."       # AIがスキルを発見するためのキーワードを含める
---
```

`description` に含めるキーワードが重要です。ユーザーが関連する話題（TDD, BDD, テスト駆動等）を話したとき、AI がこのスキルを自動的に認識します。

### commands/*.md の書き方

コマンドファイルは「ユーザー向けAPI定義」です。最小構成:

```markdown
---
description: "コマンドの簡潔な説明"
---

# /スキル名 サブコマンド $ARGUMENTS

1行の概要説明。

## 引数
- `[引数1]` : 説明

## 使用例
```
/スキル名 サブコマンド 引数の例
```

## 実行内容

詳細手順は `~/.claude/skills/スキル名/サブコマンド.md` を参照して実行すること。
```

ポイント:
- `## 実行内容` セクションに `~/.claude/skills/...` への参照を必ず入れる
- これにより AI は skills/ 配下の詳細手順を読みに行く

### skills/*.md の書き方

スキルファイルは「AI 向け実行手順書」です。AI がこの手順に従って作業します。

- Phase ごとに何をすべきかを具体的に記述
- 出力フォーマットを明示（テンプレートや例を含める）
- ユーザー介入ポイント（承認ゲート）を明記
- エラー時のリカバリー手順を含める

---

## トラブルシューティング

### `/sfad` と打ってもコマンドが出ない

1. ファイルの配置場所を確認:
   ```bash
   ls ~/.claude/commands/sfad/
   ```
   `commands/sfad/` にファイルがなければ、配置し直してください。

2. SKILL.md のフロントマターを確認:
   ```bash
   head -5 ~/.claude/skills/sfad/SKILL.md
   ```
   `name: sfad` が正しいか確認。

3. Claude Code を再起動:
   ```bash
   # 一度終了して再起動
   exit
   claude
   ```

### コマンドは出るが実行時にエラー

1. skills/ 配下のファイルが揃っているか確認:
   ```bash
   ls ~/.claude/skills/sfad/
   ```
   7ファイル（SKILL.md + 6コマンド分）が必要です。

2. commands/ 内の参照パスが正しいか確認:
   ```bash
   grep "skills/sfad" ~/.claude/commands/sfad/cycle.md
   ```
   `~/.claude/skills/sfad/cycle.md` のようなパスが記載されているべき。

### Windows 環境での注意

Windows（Git Bash / MINGW64）の場合、`~` は `C:\Users\ユーザー名` に展開されます:

```bash
# Windows での実際のパス
ls /c/Users/$USERNAME/.claude/skills/sfad/
ls /c/Users/$USERNAME/.claude/commands/sfad/
```

PowerShell の場合:

```powershell
ls $env:USERPROFILE\.claude\skills\sfad\
ls $env:USERPROFILE\.claude\commands\sfad\
```

---

## チームでの共有方法

### 方法1: リポジトリに含める（推奨）

プロジェクトリポジトリに SFAD ファイルを含め、セットアップスクリプトを用意:

```bash
# setup-sfad.sh
#!/bin/bash
echo "SFAD スキルをインストールしています..."

mkdir -p ~/.claude/skills/sfad
mkdir -p ~/.claude/commands/sfad

cp .sfad/skills/* ~/.claude/skills/sfad/
cp .sfad/commands/* ~/.claude/commands/sfad/

echo "完了。Claude Code を起動して /sfad を試してください。"
```

### 方法2: 共有ドライブ / Google Drive

ファイル一式を共有フォルダに置き、各メンバーが手動でコピー。

### 方法3: Git リポジトリ（専用）

SFAD ファイルだけの Git リポジトリを作り、clone → コピー:

```bash
git clone https://github.com/your-org/sfad-skill.git /tmp/sfad-skill
cp /tmp/sfad-skill/skills/* ~/.claude/skills/sfad/
cp /tmp/sfad-skill/commands/* ~/.claude/commands/sfad/
rm -rf /tmp/sfad-skill
```

---

## 更新方法

スキルファイルを更新した場合:

```bash
# 新しいファイルで上書きコピー
cp 新しいファイル ~/.claude/skills/sfad/
cp 新しいコマンドファイル ~/.claude/commands/sfad/

# Claude Code を再起動（または新しいセッションを開始）
```

Claude Code は起動時にスキルファイルを読み込むため、ファイルを更新したら新しいセッションを開始してください。

---

## まとめ

```
1. mkdir -p ~/.claude/skills/sfad ~/.claude/commands/sfad
2. skills/ に7ファイル、commands/ に6ファイルを配置
3. Claude Code を起動して /sfad で動作確認
4. /sfad init で品質基盤を構築、/sfad cycle で開発開始
```

所要時間: 約5分（ファイルコピーのみ）
