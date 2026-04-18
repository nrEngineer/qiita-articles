---
title: Threat Modeling をAIと自動化する ― threat.md 入門
tags:
  - Threatモデリング
  - セキュリティ
  - SFAD
  - AI駆動開発
  - ClaudeCode
private: true
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---

## TL;DR

- Threat Modeling は重要なのに根付かないのは、STRIDE や PASTA が **重すぎて実務から浮く** から
- SFAD cycle 第3 Phase の `threat.md` は、**10〜15分で書き切れる最小版の脅威モデル**
- AI に攻撃者を演じさせ、**Authorization Matrix** と **IDOR / Mass Assignment チェック** を自動生成
- STRIDE との対応は保ちつつ、STRIDE 全カテゴリを網羅するのは入門版では目指さない
- threat.md を書くだけで、Art-11 で紹介した認可ゼロ事件の再発を仕様段階で防げる
- 深掘り (STRIDE完全網羅、3プロジェクト適用例、実行ログ全文) は note 有料版 ¥500 で公開

## この記事でできること

| やりたいこと | 対応セクション |
|---|---|
| Threat Modeling が形骸化する理由を理解したい | なぜ根付かないか |
| 10分で書ける threat.md の骨格を知りたい | threat.md の必須3要素 |
| AI と自動化する流れを把握したい | 自動化フロー |
| 最小の threat.md サンプルが欲しい | ログイン機能サンプル |
| STRIDE との対応を知りたい | STRIDE 対応表 |

---

Art-11 (4/23 公開) で紹介した認可ゼロ事件、実はあれ、**自分が過去にまさに同じことをやらかした** 案件でした。

「Threat Modeling が大事」と頭ではわかっていたのに、手が動かなかった理由は単純です ― **重すぎた** のです。STRIDE で全ワークフローを分析し、DFD を書き、各要素にカテゴリを割り当て、対策を列挙する。1機能で半日かかる。そんな余裕は現場にない。

結果、「後でやる」になり、形骸化します。そして本番で認可ゼロが発覚する。

この記事では、SFAD cycle の第3 Phase として **10〜15分で書き切れる最小版の Threat Modeling = threat.md** を紹介します。STRIDE の完全網羅ではなく、**「この機能でまず防ぐべき」** にフォーカスした入門版です。

---

## なぜ Threat Modeling が根付かないか

### STRIDE は教科書としては完璧、実務には重い

STRIDE は Spoofing / Tampering / Repudiation / Information Disclosure / Denial of Service / Elevation of Privilege の 6 カテゴリで脅威を網羅する手法です。歴史も実績もある。

でも実務で適用しようとすると:

- DFD (Data Flow Diagram) を書くコスト
- 各要素に STRIDE カテゴリを割り当てるコスト
- 脅威一つ一つに対策を設計するコスト
- Agile の1スプリントに収まらない

結果、「セキュリティコンサルが入るときだけやる」儀式になり、通常の開発フローに組み込まれません。

### PASTA はさらに重い

PASTA (Process for Attack Simulation and Threat Analysis) は 7 ステージ。企業レベルの脅威分析には良いが、1機能の仕様策定で使うものではない。

### 「軽量 Threat Modeling」が必要

Agile 時代の脅威モデリングとして、Adam Shostack の "Threat Modeling: Designing for Security" でも軽量版が提唱されています。本質は 4 つの質問:

1. What are we building? (何を作るか)
2. What can go wrong? (何が悪用されうるか)
3. What are we going to do about it? (どう対処するか)
4. Did we do a good job? (うまくできたか)

SFAD の `threat.md` はこの 4 質問を markdown テンプレに落とし込んで、AI と一緒に 10〜15 分で埋めます。

---

## threat.md の必須3要素

SFAD cycle で threat.md に最低限含めるのは以下3つです。

### 1. Authorization Matrix

誰が何をできるか、誰ができないか。機能ごとに埋める表。

```markdown
## Authorization Matrix

| 操作 | 未認証 | 一般ユーザー | リソース所有者 | 管理者 |
|---|---|---|---|---|
| GET /posts | ✅ (公開) | ✅ | ✅ | ✅ |
| GET /posts/{id}/drafts | ❌ 401 | ❌ 403 | ✅ | ✅ |
| POST /posts | ❌ 401 | ✅ | - | ✅ |
| PUT /posts/{id} | ❌ 401 | ❌ 403 | ✅ | ✅ |
| DELETE /posts/{id} | ❌ 401 | ❌ 403 | ✅ | ✅ |
```

**埋める時のコツ**: 全セル必須。空欄禁止。「公開」はなぜ公開なのか理由を下に書く。

### 2. IDOR / Mass Assignment チェック

リソース所有権と入力フィールドの境界。

```markdown
## IDOR チェック

### GET /posts/{id}
- path parameter {id} の検証: 存在しない場合 404 (存在情報も隠す)
- 認可: public post なら全員、draft なら owner_id == current_user.id

### PUT /posts/{id}
- path {id} の post.owner_id == current_user.id を DB で確認
- 不一致時: 404 (存在情報も隠す) 

## Mass Assignment

### POST /posts
- クライアント入力: title, body, tags
- サーバー設定: id, owner_id (= current_user.id), created_at, updated_at, status (初期値 'draft')
- 受け取ってはいけない: id, owner_id, view_count, published_at
- 検証: Pydantic `extra: "forbid"`
```

### 3. 認証仕様 (ログイン機能がある場合)

認証メカニズム、セッション管理、レート制限。

```markdown
## 認証仕様

- メカニズム: JWT (access 15min, refresh 30days)
- Cookie: httpOnly, SameSite=Lax, Secure (prod)
- レート制限: ログイン失敗 5回 / 5分でアカウントロック
- エラーレスポンス: ユーザー列挙防止で "invalid credentials" に統一
```

これ以外にも STRIDE 各カテゴリの網羅的な対策は必要ですが、**入門版ではこの3要素で十分に 80% のケースをカバー** します。

---

## AI と自動化する流れ

実際に threat.md を生成するフロー。

### Step 1: functional.md を AI に渡す

```
以下の functional.md を参考に、この機能の threat.md を生成してください。

【生成するファイル構成】
1. Authorization Matrix (全 mutation + GET の認可表)
2. IDOR チェック (path parameter を持つ全エンドポイント)
3. Mass Assignment チェック (body を受け取る全エンドポイント)

【攻撃者ロール】
あなたは以下の機能を攻撃しようとしているペネトレーションテスターです。
1. 未認証で叩けるエンドポイントを探す
2. 他人のリソースにアクセスする方法を探す
3. 入力でサーバー設定フィールドを書き換える方法を探す

# functional.md
[ここに functional.md を貼る]
```

### Step 2: AI の出力をレビュー

AI は以下を出力します:

- Authorization Matrix のドラフト (全セル埋まっている)
- IDOR チェックのリスト
- Mass Assignment チェックのリスト
- **確信度が低い項目は「要確認」としてマーク**

### Step 3: 優先度付けと決定

各項目に Critical / High / Medium / Low を付ける。実装時に Critical と High は絶対に対策、Medium は次スプリントまでに対応、Low は TODO 記録だけ。

### Step 4: threat.md として確定

`docs/specs/{feature}/threat.md` に保存。GitHub に commit して、実装時に参照できる状態にする。

---

## 最小 threat.md サンプル (ログイン機能)

実際にログイン機能で書いた threat.md の短縮版です。

```markdown
# threat.md: ログイン機能

## 1. Authorization Matrix

| 操作 | 未認証 | 認証済 | 管理者 |
|---|---|---|---|
| POST /login | ✅ | - | - |
| POST /logout | ❌ 401 | ✅ | ✅ |
| POST /refresh | ❌ 401 | ✅ | ✅ |
| GET /me | ❌ 401 | ✅ | ✅ |

## 2. IDOR チェック

### GET /me
- 自分の user_id のみアクセス可
- query parameter で user_id を指定しても自分以外は 403

### POST /refresh
- refresh token の owner_user_id が current_user.id と一致必須
- 不一致時は token 無効化 + 403

## 3. Mass Assignment チェック

### POST /login
- クライアント入力: email, password
- サーバー設定: なし (login はレスポンスのみ)
- 受け取ってはいけない: is_admin, user_id, roles
- Pydantic extra: forbid

## 4. 認証仕様

- JWT (access 15min, refresh 30days)
- Cookie: httpOnly, SameSite=Lax, Secure (prod)
- レート制限: ログイン失敗 5回 / 5分 でアカウントロック 15分
- エラーレスポンス: "Invalid credentials" (email 存在有無を出さない)

## 5. 検討済み脅威 (対策済み)

| 脅威 | 対策 | 優先度 |
|---|---|---|
| Credential Stuffing | レート制限 + bcrypt | Critical |
| Session Fixation | ログイン後 session regenerate | Critical |
| ユーザー列挙 | エラーメッセージ統一 | High |
| XSS による token 窃取 | httpOnly Cookie | Critical |
| CSRF | SameSite=Lax | High |

## 6. 未解決 (要調査)

- 2FA 導入の是非 (次スプリント検討)
- Rate limit の IP 単位 vs アカウント単位の使い分け (要ログ分析)
```

このサイズ (120〜180行) が、実務で保守できる threat.md の粒度です。これ以上肥大化すると書き手も読み手もメンテしなくなります。

---

## STRIDE との対応 (概略)

SFAD threat.md は STRIDE を完全網羅しないものの、主要カテゴリは Authorization Matrix と認証仕様でカバーされます。

| STRIDE | 主に対応する threat.md 要素 |
|---|---|
| **S**poofing (なりすまし) | 認証仕様 |
| **T**ampering (改竄) | Mass Assignment チェック |
| **R**epudiation (否認) | 監査ログ仕様 (functional.md or threat.md) |
| **I**nformation Disclosure (情報漏洩) | Authorization Matrix + エラーメッセージ |
| **D**enial of Service | レート制限 (resilience.md と連携) |
| **E**levation of Privilege | Authorization Matrix の垂直・水平権限 |

**STRIDE を完全網羅したい場合は note 有料版 ¥500 で詳しく書いています**。DFD の書き方、STRIDE 各カテゴリの網羅的な対策、3プロジェクトで実際に生成した threat.md 全文を公開しています。

:::note info
この記事は Qiita 無料の入門版です。

- 3プロジェクト実例の threat.md 全文 (1000行超)
- STRIDE 全6カテゴリの詳細対策テンプレ
- AI との対話ログ全文 (計8万字分)

これらは note 有料版「Threat Modeling を AI と自動化する ― 実践完全ガイド」(¥500) でご覧いただけます。
:::

---

## よくある失敗

### 失敗1: Authorization Matrix を書いたのに実装で参照されない

→ `plan.md` で「実装時に threat.md の Authorization Matrix を参照する」と明記。impl コマンドで AI にも threat.md を渡す。

### 失敗2: 「たぶん大丈夫」でセルを埋める

→ 空欄と同義。埋める前に **「未認証で叩いたらどうなる?」** を想像するプロンプトを毎回使う。

### 失敗3: functional.md を更新したのに threat.md を更新しない

→ 4ファイル一式を pull request に含める運用。CI で整合性をチェック (functional に書かれた endpoint が threat の Authorization Matrix に存在するか)。

---

## まとめ

- STRIDE/PASTA は重すぎて実務から浮く。軽量版が必要
- `threat.md` は 10〜15 分で書ける最小版。**Authorization Matrix + IDOR/Mass Assignment + 認証仕様** の3要素で 80% カバー
- AI に攻撃者を演じさせれば自動生成できる。人間はレビューと優先度付けに集中
- 120〜180 行が実務で保守できる粒度。これ以上は肥大化して形骸化
- STRIDE 完全網羅は深掘り版 (note 有料) で扱う
- 4ファイル (functional/threat/resilience/plan) 一式を PR に含める運用で整合性を維持

「後でやる」 Threat Modeling をやめて、**仕様策定に 10分だけ足す** 運用を試してみてください。

---

## 次の記事: Resilience Modeling ― 障害シナリオを仕様に書く (6/4 公開予定)

`threat.md` が「悪意による脅威」をカバーするのに対し、`resilience.md` は「事故による障害」をカバーします。Timeout / Retry / Fallback / Circuit Breaker を仕様段階で設計する入門編を次回書きます。
