# SFAD記事 ギャップ分析

作成日: 2026-04-19
対象スキル版: 2026-04-15 更新 (sfad:cycle 8 Phase 化版)

---

## 背景

SFAD スキル群が 2026-04-15 に大幅アップデートされた。既存記事 (14本: 2/24〜3月頭執筆) は更新前の仕様で書かれているため、最新機能を反映する必要がある。同時に、note 用ドラフトを含む実コンテンツ量が週1投稿 (Qiita) では消化しきれないため、**週2投稿 (月・木) に移行** する。

## 新機能 (記事に未反映)

| # | 新機能 | スキル | 要点 |
|---|---|---|---|
| F1 | **仕様4ファイル分割** | `sfad:cycle` | functional.md / threat.md / resilience.md / plan.md の分離 |
| F2 | **Threat Modeling Phase** | `sfad:cycle` | OWASP 準拠 / 攻撃者視点での脅威分析 |
| F3 | **Resilience Modeling Phase** | `sfad:cycle` | 障害シナリオ・復旧モードを仕様化 |
| F4 | **Three Amigos 4視点** | `sfad:spec` | PO/Dev/QA + **攻撃者** (新規) |
| F5 | **13項目実装ルール** | `sfad:impl` | Mass Assignment / N+1 / SSR安全性 / 認可 等 |
| F6 | **9種類問題検出タグ** | `sfad:reverse` | [DEAD CODE] / [SECURITY] / [N+1 QUERY] / [SESSION HOLD] 等 |

---

## Section A: 既存記事 × 新機能 反映マップ

凡例: ⭐=追記必須 / 💡=脚注推奨 / —=関連薄

### Qiita 予約済み (14本)

| 記事 | 公開日 | F1 4ファイル | F2 Threat | F3 Resilience | F4 攻撃者視点 | F5 13項目 | F6 9タグ |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|
| Art-04 デグレ11回 | 3/2 ✅ | — | — | 💡 | — | 💡 | — |
| Art-02 読む技術 | 3/9 ✅ | — | 💡 | — | 💡 | ⭐ | 💡 |
| Art-06 reverse実行 | 3/16 ✅ | — | 💡 | — | — | — | ⭐ |
| Art-entry-handoff | 3/23 ✅ | 💡 | — | — | — | — | ⭐ |
| Art-03 Example Mapping | 3/30 ✅ | ⭐ | ⭐ | 💡 | ⭐ | — | — |
| Art-05 握りつぶし | 4/6 ✅ | — | 💡 | 💡 | 💡 | ⭐ | — |
| Art-01 78バグ分類 | 4/13 ✅ | — | 💡 | 💡 | 💡 | 💡 | 💡 |
| Art-entry-solo | 4/20 📅 | 💡 | — | — | — | ⭐ | — |
| Art-entry-zero-quality | 4/27 📅 | 💡 | 💡 | — | — | 💡 | — |
| Art-07-digest 7原則 | 5/4 📅 | 💡 | 💡 | 💡 | 💡 | ⭐ | — |
| Art-08-digest 6コマンド | 5/11 📅 | ⭐ | ⭐ | ⭐ | ⭐ | ⭐ | ⭐ |
| Art-09-digest Skill作り | 5/18 📅 | — | — | — | — | — | — |
| Art-entry-ai-proposal | 5/25 📅 | 💡 | ⭐ | 💡 | 💡 | 💡 | — |
| Art-10 総括ロードマップ | 6/1 📅 | ⭐ | ⭐ | ⭐ | ⭐ | ⭐ | ⭐ |

### 優先対応 (公開前に追記すべき記事)

**⭐最重要: Art-08-digest (5/11 公開)** 
「SFADの全6コマンド設計思想」→ `sfad:cycle` が 8 Phase 化した事実を反映しないと記事の骨格が古くなる。**6コマンド→7コマンド** (cycle拡張) or **6コマンド+8 Phase解説** のいずれかで再構成必須。

**⭐重要: Art-10 (6/1 総括)**
ロードマップ記事なので、最新SFAD全体像で締める必要あり。4ファイル分割・Threat/Resilience Phase の位置づけを明記。

**⭐重要: Art-07-digest (5/4)** と **Art-entry-ai-proposal (5/25)**
7原則に 13項目実装ルールとの対応を追記。AI 導入提案には Threat Modeling の訴求力を追加。

### 公開済み記事 (追記不可)
3月公開分 (Art-04, 02, 06, entry-handoff, 03, 05, 01) は Qiita 側が公開済みで追記困難。代わりに **note 拡張版** or **続編記事** で新機能をカバー (Section B参照)。

---

## Section B: 新規記事テーマ提案

### B1. 仕様書を4ファイルに分けたらAIが迷わなくなった (F1)
- **掲載**: Qiita 無料
- **想定**: 5,000〜7,000字
- **骨子**: 単一 spec.md → 4ファイル (functional/threat/resilience/plan) への進化理由。各ファイルの役割分担。AI コンテキストウィンドウへの優しさ
- **関係**: Art-03 (Example Mapping) の続編

### B2. AIに攻撃者視点を持たせる Three Amigos 4視点 (F4)
- **掲載**: Qiita 無料
- **想定**: 6,000〜8,000字
- **骨子**: PO/Dev/QA の3視点に「攻撃者」を加える理由。OWASP Top 10 との接続。プロンプト設計実例
- **関係**: Art-03, Art-05 の発展形

### B3. 13項目の実装ルール - AIが破る罠リスト (F5)
- **掲載**: Qiita 無料
- **想定**: 8,000〜10,000字
- **骨子**: Mass Assignment / N+1 / SSR安全性 / 認可 等の 13項目を事例付きで解説
- **関係**: Art-05 (握りつぶし) の深掘り版

### B4. Threat Modeling をAIと自動化する (F2)
- **掲載**: Qiita 無料 (入門) + note 有料 (¥500, 深掘り)
- **想定**: Qiita 5,000字 / note 15,000字
- **骨子**: threat.md 生成フロー / STRIDE との対応 / 実行ログ全文 (有料のみ)
- **関係**: B2 の続編

### B5. Resilience Modeling - 障害シナリオを仕様に書く (F3)
- **掲載**: Qiita 無料 (入門) + note 有料 (¥500, 深掘り)
- **想定**: Qiita 5,000字 / note 15,000字
- **骨子**: resilience.md の書き方 / 障害シナリオのパターン化 / Retry/Timeout/Fallback 戦略
- **関係**: B4 と対。Art-04 (デグレ) の発展

### B6. 既存コードからN+1を仕様化する - reverse 9タグ活用 (F6)
- **掲載**: note 無料 (ケーススタディ)
- **想定**: 8,000〜10,000字
- **骨子**: reverse コマンドの 9タグ解説 / 実プロジェクトでの適用例 / [N+1 QUERY] タグの読み方
- **関係**: Art-06 の note 版深掘り

### B7. 新 SFAD cycle の 8 Phase を一周した記録
- **掲載**: Qiita 無料
- **想定**: 10,000字+
- **骨子**: Example Mapping → Spec → Threat → Resilience → Plan → 受け入れテスト → UC TDD → 静的解析 の全フェーズを実例1機能で一周
- **関係**: Art-08-digest (5/11) の後続、新規ユーザーのオンボーディング記事

### B8. Art-11 昇格「6000行PR認可ゼロ事件」 (既存ドラフト)
- **掲載**: Qiita 無料
- **現状**: `note/articles/article-11-qiita.md` に完成原稿あり
- **必要作業**: 新機能 F2 (Threat Modeling) への接続を末尾に追記

### B9. Art-12 昇格「テストで本番ロジック再実装」 (既存ドラフト)
- **掲載**: Qiita 無料
- **現状**: `note/articles/article-12-qiita.md` に完成原稿あり
- **必要作業**: 新機能 F5 (13項目実装ルール) への接続を末尾に追記

### B10. Art-15 公開「フローを理解してない実装者」 (既存ドラフト)
- **掲載**: note 有料 ¥500
- **現状**: `note/articles/article-15-note-paid.md` に完成原稿あり
- **必要作業**: そのまま。Qiita 公開済みの関連記事 (Art-11) から導線を張る

---

## Section C: 投稿スケジュール再設計 (週2 / 月・木)

### 基本方針

- **月曜枠**: 既存予約を維持 (GitHub Actions で自動公開中)
- **木曜枠**: 4/23 から新規追加。スピンオフ / 新機能解説 / ケーススタディ中心
- note は引き続き **手動投稿** (schedule.json 管理外)。木曜夜 or 金曜に投稿

### Qiita スケジュール (schedule.json 反映案)

| 日付 | 曜日 | 記事ファイル | タイトル | 状態 |
|---|---|---|---|---|
| 2026-04-20 | 月 | article-entry-solo-qiita.md | Claude Code と TDD を組み合わせたら | 既存 |
| **2026-04-23** | **木** | **article-11-qiita.md** | **AIに6000行のPRを書かせたら認可がゼロだった** | **新規(昇格)** |
| 2026-04-27 | 月 | article-entry-zero-quality-qiita.md | 品質基盤ゼロのチームを引き受けた新任TLへ | 既存 |
| **2026-04-30** | **木** | **article-12-qiita.md** | **テストファイルの中で本番ロジックを再実装** | **新規(昇格)** |
| 2026-05-04 | 月 | article-07-qiita-digest.md | 78バグから導いた7つの設計原則 (ダイジェスト) | 既存 |
| **2026-05-07** | **木** | **article-b1-4files-qiita.md** | **仕様書を4ファイルに分けたらAIが迷わなくなった** | **新規(B1)** |
| 2026-05-11 | 月 | article-08-qiita-digest.md | SFADの全6コマンド設計思想 (ダイジェスト) | 既存★要更新 |
| **2026-05-14** | **木** | **article-b2-attacker-qiita.md** | **AIに攻撃者視点を持たせる Three Amigos** | **新規(B2)** |
| 2026-05-18 | 月 | article-09-qiita-digest.md | Claude Code Skillの作り方 (ダイジェスト) | 既存 |
| **2026-05-21** | **木** | **article-b3-13rules-qiita.md** | **13項目の実装ルール - AIが破る罠リスト** | **新規(B3)** |
| 2026-05-25 | 月 | article-entry-ai-proposal-qiita.md | AI導入提案が通らない理由と、データで語って通す方法 | 既存 |
| **2026-05-28** | **木** | **article-b4-threat-qiita.md** | **Threat Modeling をAIと自動化する (入門)** | **新規(B4)** |
| 2026-06-01 | 月 | article-10-qiita.md | AI時代の開発ワークフロー実践ロードマップ | 既存★要更新 |
| **2026-06-04** | **木** | **article-b5-resilience-qiita.md** | **Resilience Modeling - 障害シナリオを仕様に書く (入門)** | **新規(B5)** |
| **2026-06-08** | **月** | **article-b7-cycle-walkthrough-qiita.md** | **新SFAD cycle 8 Phase を一周した記録** | **新規(B7)** |
| **2026-06-11** | **木** | **article-b6-n1-reverse-qiita.md** | **既存コードからN+1を仕様化する (Qiita版)** | **新規(B6 Qiita版)** |

計 16 記事 (既存 7 + 新規木曜 6 + 新規月曜 2 + 新規木曜 1 = 16)

### note スケジュール (手動投稿、content-schedule.md 管理)

| 日付 | 記事 | 無料/有料 | 備考 |
|---|---|---|---|
| 2026-04-23 (木夜) | article-15-note-paid.md | ¥500 | Art-11 公開と同日、導線強化 |
| 2026-05-07 頃 | article-b4-threat-note-paid.md (新規執筆) | ¥500 | B4 深掘り版 |
| 2026-05-28 頃 | article-b5-resilience-note-paid.md (新規執筆) | ¥500 | B5 深掘り版 |
| 2026-06-11 頃 | article-b6-n1-reverse-note.md (新規執筆) | 無料 | B6 note 版 |

---

## Section D: 役割分担マトリクス

### プラットフォーム方針

| プラットフォーム | 役割 | 目安文字数 | 価格 |
|---|---|---|---|
| Qiita 無料 | 認知・問題提起・全体像 | 5,000〜10,000字 | 無料 |
| note 無料 | 信頼形成・事例ストーリー・ケーススタディ | 8,000〜15,000字 | 無料 |
| note 有料 | 収益・ソース公開・詳細実装手順 | 15,000字+ | ¥500 |

### 同テーマ異プラットフォーム時の切り分け

**例: Threat Modeling (B4)**
- Qiita 無料 = 「Threat Modeling とは何か / なぜ必要か / 入口としての書き方」 (5,000字)
- note 有料 = 「threat.md 生成の実行ログ全文 / STRIDE 対応表 / 実プロジェクト適用例 3 件」 (15,000字+)

**例: N+1 仕様化 (B6)**
- note 無料 = 「reverse コマンドで N+1 を発見した事例ストーリー」
- Qiita 無料 = 「9タグ活用法の実践ガイド」

### シリーズ構造 (更新後)

```
[認知: Qiita]                    [信頼: note無料]              [収益: note有料]
Art-01 78バグ (公開済) ────→    article-10-note (ドラフト) ───→   Art-07-paid 7原則 ¥500 (ドラフト)
Art-03 Example Mapping ──→     article-03-note (ドラフト) ───→   Art-08-paid 6コマンド ¥500 (ドラフト)
Art-06 reverse ──────────→     article-05-note (ドラフト) ───→   Art-09-paid Skill作り ¥500 (ドラフト)
Art-11 6000行PR (新規) ───→    Art-15 フロー理解 ¥500 (ドラフト)
B1 4ファイル分割 ─────────→    B4-note Threat 深掘り ¥500 (新規)
B2 攻撃者視点 ────────────→    B5-note Resilience 深掘り ¥500 (新規)
B3 13ルール ──────────────→    B6-note N+1事例 (新規)
```

---

## アクションアイテム (優先順位順)

### P0 (今週中: 4/20-4/26)

- [ ] schedule.json を Section C の通り更新 (木曜枠追加)
- [ ] `note/articles/article-11-qiita.md` → `public/article-11-qiita.md` へコピー (Qiita 予約対象化)
- [ ] Art-11 末尾に Threat Modeling への導線追記
- [ ] `note/articles/article-12-qiita.md` → `public/article-12-qiita.md` へコピー
- [ ] Art-12 末尾に 13項目実装ルールへの導線追記

### P1 (5月前半: 5/4 までに執筆完了)

- [ ] B1「仕様書を4ファイル分割」執筆 → 5/7 公開
- [ ] Art-08-digest を 8 Phase 対応に更新 (5/11 公開分)

### P2 (5月後半: 5/18 までに執筆完了)

- [ ] B2「攻撃者視点」執筆 → 5/14 公開
- [ ] B3「13項目実装ルール」執筆 → 5/21 公開

### P3 (6月: 順次)

- [ ] B4 Qiita 入門版 + note 有料版 執筆
- [ ] B5 Qiita 入門版 + note 有料版 執筆
- [ ] Art-10 (6/1) を最新 SFAD 構造で締める内容に再編
- [ ] B7「8 Phase 一周」執筆 → 6/8 公開
- [ ] B6 Qiita 版 + note 無料版 執筆 → 6/11 公開

---

## 確認事項

1. **4/20 (月) の Art-entry-solo は予約済みで当初通り公開** → OK
2. **4/23 (木) から週2投稿開始** → Art-11 昇格で開始
3. **Art-15 は note 有料のみ** (schedule.json 管理外) → 手動投稿
4. **Art-11/12 の昇格**: ドラフト → Qiita 公開に格上げ、end-to-end で追記1回のみ
5. **新規記事の執筆順序**: B1 → Art-08更新 → B2 → B3 → B4/B5 並行 → B7 → B6 の順が依存関係的に自然

---

## 参考: 関連ファイル

- `schedule.json` — Qiita 予約投稿スケジュール (更新対象)
- `note/content-plan.md` — 6ヶ月計画 (Section B を反映して更新)
- `note/content-schedule.md` — Month 1 詳細 (週2化を反映)
- `public/*.md` — 予約済み記事本文 (Art-08-digest と Art-10 は本文更新)
- `note/articles/article-11-qiita.md` — 昇格対象ドラフト
- `note/articles/article-12-qiita.md` — 昇格対象ドラフト
- `note/articles/article-15-note-paid.md` — note 投稿対象
