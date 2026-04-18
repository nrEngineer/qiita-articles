# SFAD コンテンツ 6ヶ月計画

## ブランド定義

**SFAD = 「AIと開発するときの品質の守り方」**
テーマ: エンジニア × AI の品質・コードの書き方

---

## Season 1: 78バグから学んだ基礎（3月〜6月）

### Qiita（毎週月曜 7:00 自動公開）

| W | 公開日 | ファイル | タイトル |
|---|---|---|---|
| 1 | 3/2 | article-04-qiita | テスト不足でデグレ11回。Double-Loop TDD |
| 2 | 3/9 | article-02-qiita | AI生成コードを「読む技術」 |
| 3 | 3/16 | article-06-qiita | 仕様書がないコードをAIに読ませたら |
| 4 | 3/23 | article-entry-handoff-qiita | 引き継ぎ地獄エンジニアのためのSFAD |
| 5 | 3/30 | article-03-qiita | AIに伝わる仕様書の書き方 ― Example Mapping |
| 6 | 4/6 | article-05-qiita | エラーを「握りつぶす」コードの見抜き方 |
| 7 | 4/13 | article-01-qiita | AIと開発して78個のバグを踏んだので全部分類した |
| 8 | 4/20 | article-entry-solo-qiita | Claude CodeとTDDを組み合わせたら |
| 9 | 4/27 | article-entry-zero-quality-qiita | 品質基盤ゼロのチームを引き受けた新任TLへ |
| 10 | 5/4 | article-07-qiita-digest | 78バグから導いた7つの設計原則（ダイジェスト版） |
| 11 | 5/11 | article-08-qiita-digest | SFADの全6コマンド設計思想（ダイジェスト版） |
| 12 | 5/18 | article-09-qiita-digest | Claude Code Skillの作り方（ダイジェスト版） |
| 13 | 5/25 | article-entry-ai-proposal-qiita | AI導入提案が通らない理由と、データで語って通す方法 |
| 14 | 6/1 | article-10-qiita | AI時代の開発ワークフロー実践ロードマップ |

### note（毎週木曜 手動投稿）

| W | 公開日 | ファイル | タイトル | 無料/有料 |
|---|---|---|---|---|
| 1 | 3/5 | article-03-note | 15件の仕様バグを分析して辿り着いた… | 無料 |
| 2 | 3/12 | article-05-note | 金曜日の夜、ログが「空っぽ」だった | 無料 |
| 3 | 3/19 | article-07-note-paid | 78バグから導いた7つの設計原則 | ¥500 |
| 4 | 3/26 | article-08-note-paid | SFADの全6コマンド設計思想 | ¥500 |
| 5 | 4/2 | article-09-note-paid | Claude Code Skillの作り方 完全ガイド | ¥500 |
| 6 | 4/9 | article-10-note | 10本書いて見えた景色 | 無料 |
| - | 4月中旬 | - | S1マガジン化（有料3本まとめ ¥1,200） | マガジン |

---

## Season 2: SFAD実践編（7月〜9月）

テーマ: 現場の「これどうするの？」をSFADで解く

### Qiita（無料）

| # | タイトル案 | ターゲット |
|---|---|---|
| S2-1 | AIが書いたコードをリファクタリングする技術 ― 安全に構造を変える手順 | リファクタリング層 |
| S2-2 | AI×型安全 ― TypeScript/Go/Rustの型システムでAIの暴走を防ぐ | 型安全層 |
| S2-3 | AIに書かせたコードのセキュリティ監査 ― OWASP Top 10をSFADで防ぐ | セキュリティ層 |
| S2-4 | CIパイプラインに品質ゲートを組む ― AIコードを自動で検査する仕組み | DevOps層 |

### note（有料/無料ミックス）

| # | タイトル案 | 無料/有料 |
|---|---|---|
| S2-5 | SFADをチームに導入した1ヶ月の記録 | ¥500 |
| S2-6 | AIとペアプロする技術 ― プロンプト設計とコンテキスト管理 | ¥500〜¥800 |
| S2-7 | マイクロサービスの仕様をExample Mapで書く | ¥500〜¥800 |
| S2-8 | SFAD導入の効果測定 ― 3ヶ月後のバグ数・工数・チーム満足度 | 無料（締め） |

---

## Season 3: 言語別 Deep Dive（10月〜12月）

| # | タイトル案 | 言語 | プラットフォーム |
|---|---|---|---|
| S3-1 | PythonでSFAD ― pytest + ruff + Example Map | Python | Qiita |
| S3-2 | TypeScriptでSFAD ― Vitest + ESLint strict + BDD | TypeScript | Qiita |
| S3-3 | GoでSFAD ― testing + golangci-lint + テーブル駆動テスト | Go | Qiita |
| S3-4 | RustでSFAD ― cargo test + clippy deny + 型駆動設計 | Rust | Qiita |
| S3-5 | Next.js/ReactでSFAD ― フロントエンドBDD + Testing Library | React | Qiita |
| S3-6 | Laravel/RailsでSFAD ― バックエンドフレームワーク適用ガイド | PHP/Ruby | Qiita |

---

## 通年: SFAD Tips（Qiita、週1、短尺500-1000字）

Phase 2（5月）から開始。メイン記事の間に挟む。

ストック案:
- AIが書く `any` を型安全にする3行の設定
- Example Map を5分で書くテンプレート
- CI に1行追加するだけで bare except をブロックする方法
- Claude Code に仕様を渡すときの3つのコツ
- AIにテストを書かせると何が起きるか
- .cursorrulesとClaude Code Skillの違い
- Go の errcheck を1分で有効化する方法
- Rust の unwrap を全部禁止する clippy 設定
- AIが生成するN+1クエリを見つける方法
- pytest の fixture でAI生成コードをテストする

---

## 収益目標

| 期間 | 収益源 | 目標 |
|---|---|---|
| 3-4月 | - | ¥0（種まき） |
| 5-6月 | S1有料×3本 | ¥15,000〜¥45,000 |
| 6月 | S1マガジン | ¥12,000〜¥36,000 |
| 7-9月 | S2有料×3本 + S1継続 | ¥30,000〜¥90,000 |
| 10-12月 | S3 + S2マガジン + 全部セット | ¥50,000〜¥150,000 |

## KPI

| 指標 | Phase 1 目標 | Phase 2 目標 | Phase 3 目標 |
|---|---|---|---|
| Qiita LIKE/記事 | 10+ | 20+ | 30+ |
| Qiita フォロワー | 50 | 200 | 500 |
| note PV/記事 | 100+ | 300+ | 500+ |
| note フォロワー | 30 | 100 | 300 |
| note 売上/月 | - | ¥10,000+ | ¥30,000+ |
