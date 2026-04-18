# SFADの全6コマンド設計思想 ― なぜこの順番で、なぜこのコマンドなのか。Claude Code Skillの作り方を完全公開

`review` コマンドを削除するのが、一番つらかった。

12個のコマンドを最初に書き出したとき、一番ワクワクしていたのが `review` でした。「AIがコードレビューしてくれるなんて最高じゃないか」。でも使ってみると、Claude Code自体がすでにコードレビューを得意としていた。Skillとして切り出す意味がなかったのです。

12個を6個に絞る過程で、私は「作りたいもの」と「必要なもの」の違いを学びました。自分が愛着を持っているコマンドほど、冷静に評価するのが難しい。`review` を消した瞬間、肩の荷が降りたような感覚がありました。

---

## この記事でしか読めないこと

- **Skillファイルの全ソースコード**: 実際に動いている `.md` ファイルの中身をそのまま公開
- **12→6の削減プロセス**: 各コマンドを「本当に必要か？」と問い詰めた判断記録
- **AIに「何を伝えないか」の設計**: 指示しすぎると逆効果になった実例
- **ゲート設計の思想**: 手順を飛ばせない仕組みをどう作ったか
- **失敗した設計パターン3選**: 最初のバージョンで何が動かなかったか

---

無料記事ではSFADの6コマンドの概要と使い分けを紹介しました。この有料記事では、Skillファイルの中身を実際に見せながら「なぜこの構造にしたのか」「AIに何を伝え、何を伝えなかったのか」を解説します。Claude Code Skillを自分で作りたい方に向けて、設計の裏側を全て公開します。

---

## 12個を6個に絞った話

### 初期案の12コマンド

SFADを作り始めたとき、思いつくコマンドを全て書き出しました。

```
初期案（12個）:
  1. setup       ← プロジェクト初期設定
  2. bootstrap   ← 環境構築
  3. discover    ← 要件の発見（BDD Discovery）
  4. map         ← Example Mapping
  5. formulate   ← Given-When-Then変換
  6. define      ← 仕様書生成
  7. generate-tests  ← テスト自動生成
  8. implement   ← TDD実装
  9. refactor    ← リファクタリング
  10. review     ← コードレビュー支援
  11. verify     ← 検証・テスト実行
  12. extract    ← 既存コードから仕様抽出
```

12個。覚えられません。

### 削除した6個とその理由

1つずつ、「本当に必要か？他のコマンドで代替できないか？」を問いました。

**setup + bootstrap → initに統合**

setupとbootstrapの違いが曖昧でした。「プロジェクトの初期設定」と「環境構築」は、実際には同じタイミングで行います。分ける理由がありませんでした。1つの`init`に統合しました。

**discover + map + formulate → specに統合**

BDDの3つのステップ（Discovery、Example Mapping、Formulation）を別々のコマンドにしていましたが、実際に使ってみると面倒でした。「discover → map → formulate」と3回コマンドを打つのは、ユーザーの認知負荷が高すぎます。

BDDの理論ではこの3つは分かれていますが、AIが実行する場合は1つのコマンドの中でPhaseとして分けた方が自然です。`spec`というコマンドの中で、Phase 0がDiscovery、Phase 1がExample Mapping、Phase 2がFormulationになりました。

**define → specに吸収**

「仕様書生成」は「仕様定義」の最終ステップです。specの出力として自然に含まれるので、独立したコマンドにする必要がありませんでした。

**refactor → implに吸収**

Canon TDDのサイクルは「Red → Green → Refactor」です。リファクタリングはGreenの後に必ず行うステップなので、`impl`の中に含めました。独立したコマンドにすると「Greenの後にRefactorを忘れる」というリスクが逆に増えます。

**review → 削除**

コードレビュー支援は魅力的な機能でしたが、SFADの本質ではありませんでした。SFADは「仕様→テスト→実装」の流れを自動化する手法です。レビューは別のSkillとして作るべきものです。

**verify → implに吸収**

テストの実行と検証は、実装のフィードバックループの一部です。「テストを実行する」だけの独立コマンドは不要でした。`impl`が自動的にテストを実行し、結果を報告します。

### 「コマンドは少ないほうが使われる」原則

この削減プロセスで学んだのは、「コマンドが多い = 使いやすい」ではないという事実です。

12個のコマンドがあると「どれを使えばいいかわからない」が発生します。「discoverとmapの違いは？」「defineとformuateはどう使い分ける？」という質問が毎回出てきました。

6個にしたら、迷いがなくなりました。

```
最終版（6個）:
  init     ← Day 0の品質基盤構築
  cycle    ← 仕様定義→テスト→実装の全自動サイクル
  spec     ← 仕様定義のみ（cycleの部分実行）
  test     ← テスト生成のみ（cycleの部分実行）
  impl     ← 実装のみ（cycleの部分実行）
  reverse  ← 既存コードから仕様を抽出
```

使い方の判断は単純です。

- 新規プロジェクトを始めるなら → `init`
- 新しい機能を作るなら → `cycle`
- 部分的に実行したいなら → `spec` / `test` / `impl`
- 既存コードを分析するなら → `reverse`

---

## 設計の出発点: 78バグの「逆算」

6コマンドは「こういうコマンドがあったら便利だろう」という発想では作っていません。78件のバグを1件ずつ並べて、「このバグは、いつ、どんな行為をしていれば防げたか？」を逆算して作りました。

### 防止マッピング

```
init が防ぐバグ: 46件
  print残留(23) + bare except(12) + 型安全(9) + その他(2)
  → Day 0にlint + 型チェック + CIがあれば発生しなかった

spec / cycle が防ぐバグ: 15件
  仕様齟齬(15)
  → 実装前にExample Mappingで仕様を具体化していれば発生しなかった

test / impl が防ぐバグ: 11件
  テスト不足によるデグレ(11)
  → テストを先に書いていれば、変更時に壊れたことに気づけた

reverse が防ぐバグ: 保守案件全般
  → 仕様書がない既存コードを触るときの安全網
```

この逆算で、各コマンドの「存在理由」が明確になりました。initは46件のバグを防ぐために存在します。specは15件のバグを防ぐために存在します。「あったら便利」ではなく「なかったらバグが生まれる」から存在するのです。

ここからは、各コマンドの設計意図を掘り下げます。「なぜこの構造にしたのか」「AIに何を伝え、何を伝えなかったのか」── Skillファイルの実際のソースコードとともに、設計判断の裏側を全て公開します。

<!-- ▼ ここにnoteの有料エリア境界線を設定 ▼ -->

---

## /sfad init の設計意図

### 「後でやる = 4倍のコストでやる」

無料記事でも書きましたが、この数字は私の実体験です。

```
Day 0にlintを入れる場合:
  設定ファイルを書く: 30分
  CIに組み込む: 30分
  pre-commitフック: 30分
  合計: 約1.5時間

Day 30にlintを入れる場合:
  設定ファイルを書く: 30分
  CIに組み込む: 30分
  既存コードのlintエラー修正: 4-6時間
  テストの修正: 1-2時間
  合計: 約6-9時間（4-6倍）
```

### 11項目を選んだ理由

initが設定する11項目は、78件のバグから逆算して決めました。

```
 1. CI設定            → 全ての自動チェックの基盤。これがなければ何も機械的に防げない
 2. lint設定          → 35件（print 23 + bare except 12）を機械的にブロック
 3. フォーマッター    → コードの見た目の議論を排除。レビューの品質を上げる
 4. 型チェック        → 9件の型安全バグを防止
 5. pre-commit       → CIより前、コミット時点でフィードバック
 6. テスト基盤       → 11件のデグレを防止するための土台
 7. カバレッジ       → テストの量を客観的に測定
 8. ログ基盤         → print 23件の根本原因（loggerがなかった）を解決
 9. .gitignore       → セキュリティの最低限
10. テンプレート     → Issue/PRの品質を標準化
11. Dependabot       → 依存関係の脆弱性を自動検知
```

11項目全てに「なぜ必要か」の根拠があります。「あると便利だから」で入れた項目は1つもありません。

### Skillファイルに入れた情報

`init.md`には以下の情報を入れました。実際のファイルから抜粋します。

**10スタック対応のStack Detection Matrix**

```
init.md に定義されている検出ロジック:

検出シグナル            → スタック          → パッケージマネージャ
pyproject.toml          → Python            → pip / poetry
go.mod                  → Go                → go mod
Cargo.toml              → Rust              → cargo
pom.xml                 → Java              → maven
build.gradle            → Java / Kotlin     → gradle
Gemfile                 → Ruby              → bundler
package.json + next.*   → Next.js           → npm / yarn / pnpm
package.json + vite.*   → React (Vite)      → npm / yarn / pnpm
package.json + nuxt.*   → Nuxt (Vue)        → npm / yarn / pnpm
angular.json            → Angular           → npm / yarn
svelte.config.*         → SvelteKit         → npm / yarn / pnpm
pubspec.yaml            → Flutter           → pub
```

AIがプロジェクトディレクトリのファイルを見て、自動でスタックを判定します。「あなたのプロジェクトは何で書かれていますか？」と聞く必要がありません。

**各スタックのlintツール/テストランナー/CI設定**

init.mdには、10スタックそれぞれについて以下を定義しました。

```
各スタックに定義されている情報:

Python:
  - Lint: ruff check .
  - 型チェック: mypy .
  - テスト: pytest --cov --cov-fail-under=70
  - ビルド: なし
  - pre-commit: ruff-pre-commit

Go:
  - Lint: golangci-lint run
  - 型チェック: コンパイル時
  - テスト: go test -cover ./...
  - ビルド: go build ./...
  - pre-commit: golangci-lint (git hook)

Rust:
  - Lint: cargo clippy -- -D warnings
  - 型チェック: コンパイル時
  - テスト: cargo test
  - ビルド: cargo build --release
  - pre-commit: cargo-husky

Next.js:
  - Lint: eslint .
  - 型チェック: tsc --noEmit
  - テスト: jest --coverage --ci
  - ビルド: next build
  - pre-commit: husky + lint-staged

（他6スタックも同様に定義）
```

これらの情報をSkillファイルに入れた理由は「AIが毎回調べなくて済むようにする」ためです。AIがlintツールを選ぶとき、プロジェクトに応じた最適なツールを即座に判断できます。

**init.mdの構造**

```
init.md の構造:

Phase 1:  検出と確認
  → スタック検出 → 既存設定確認 → 差分リストアップ → ユーザー確認

Phase 2:  CI/CDパイプライン
Phase 3:  Pre-commitフック
Phase 4:  Lint Strict設定
Phase 5:  テスト基盤
Phase 6:  ログ・エラー基盤
Phase 7:  セキュリティ基本設定
Phase 8:  ヘルスチェック（BEのみ）
Phase 9:  Docker開発環境
Phase 10: テンプレート + ADR
Phase 11: Dependabot
Phase 12: 検証と完了
```

12のPhaseに分かれています。各Phaseには「達成要件」が定義されていて、AIは要件を満たすまでPhaseを完了しません。

---

## /sfad cycle の設計意図

### メインコマンド: 8 PhaseでBDD + Double-Loop TDDを自動実行

cycleはSFADの中核です。BDDの3 Practices（Discovery → Formulation → Automation）とDouble-Loop TDD（外側=受け入れテスト、内側=UCテスト）を、1つのコマンドで全自動実行します。

```
cycle.md に定義されている 8 Phase:

Phase 1: Discovery（Example Mapping）
  → BDDの「発見」フェーズ。3つの視点（PO/Dev/QA）でExample Mapを作る
  → 【ゲート】ユーザーの質問回答を待つ

Phase 2: Spec生成 + Test List
  → Example Map → Given-When-Then変換 + Test List作成
  → 【ゲート】ユーザーの仕様承認を待つ

Phase 3: 受け入れテスト生成（外側ループ Red）
  → 機能全体の受け入れテストを生成。当然Redになる

Phase 4: UC単位TDDサイクル（内側ループ）
  → 各UCについて Red → Green → Refactor を繰り返す

Phase 5: 状態パターンTDDサイクル
  → S-1〜S-4（Loading/Error/Empty/Data）のTDDサイクル

Phase 6: エッジケース検出
  → カバレッジギャップをリストアップ
  → 【ゲート】追加テスト生成の承認を待つ

Phase 7: 受け入れテスト確認（外側ループ Green）
  → 全UCがGreenになったので、受け入れテストもGreenになるはず

Phase 8: サマリー出力
  → 生成ファイル一覧、Test Listの完了率、次のステップを表示
```

### 3つのゲートの設計意図

cycle.mdには3つの「ゲート」が定義されています。ゲートとは「AIが自動で先に進まない、人間の判断を求めるポイント」です。

**ゲート1: Phase 1 → Phase 2（Discovery回答）**

```
cycle.md のゲート1定義:

Phase 1完了後、ユーザーに以下を提示する:
  - Example Mapのドラフト（Story + Rules + Examples + Questions）
  - Questionsへの回答を求める

Questions（赤カード）が0になるまで繰り返す。
Questionが残っている状態でPhase 2に進んではならない。

意図: 曖昧な仕様でコードを書くと仕様齟齬が起きる。
      78件のうち15件がこれで生まれた。
```

このゲートがなかったら、AIは推測で仕様を決めてコードを書きます。それは78件のバグの再現です。

**ゲート2: Phase 2 → Phase 3（仕様承認）**

```
cycle.md のゲート2定義:

Phase 2完了後、ユーザーに以下を提示する:
  - 確定した仕様（Example Map + Given-When-Then + Test List）
  - 仕様を承認するかどうかを問う

承認なしではPhase 3に進まない。

意図: AIが作った仕様をユーザーが確認する最後の機会。
      テストを生成した後に仕様を変えるとコストが跳ね上がる。
```

**ゲート3: Phase 6（エッジケース承認）**

```
cycle.md のゲート3定義:

Phase 5完了後、実装中に発見したエッジケースをリストアップする:
  - 境界値の未定義
  - null/空文字の未処理
  - 並行処理の未検証

ユーザーに「追加テストを生成しますか？」と問う。
承認されたエッジケースのみ、追加のRed → Greenサイクルを回す。

意図: 全てのエッジケースをテストする必要はない。
      コストとリスクのバランスをユーザーが判断する。
```

### 「承認なしでは先に進まない」設計の意図

この設計には明確な理由があります。**AIに仕様を決めさせない**ということです。

AIは優秀なコード生成器ですが、「何を作るべきか」の判断は人間がすべきです。私の78件のバグのうち15件は、AIが仕様を推測して実装した結果でした。推測が当たることもありますが、外れたときのコストは大きいです。

ゲートは「止める」ためではなく「気づかせる」ためにあります。

### Skillファイルに入れた情報の詳細

**BDD 3 Practicesとcycle Phaseの対応表**

```
cycle.md に定義されている理論との対応:

BDD Practice          SFAD Cycle Phase         TDD概念
Discovery          → Phase 1: Example Mapping
Formulation        → Phase 2: Spec生成          Canon TDD Step 1: Test List
Automation(outer)  → Phase 3: 受け入れテスト     Outer Loop: Red
Automation(inner)  → Phase 4: UC単位TDD          Inner Loop: Red→Green→Refactor
                   → Phase 5: 状態パターン       Inner Loop: Red→Green→Refactor
                   → Phase 6: エッジケース       Canon TDD Step 3: リスト追加
Acceptance Green   → Phase 7: 受け入れテスト確認  Outer Loop: Green
                   → Phase 8: サマリー
```

この対応表をSkillファイルに入れた理由は、AIが「今自分が何をしているのか」を理解するためです。Phase 3で受け入れテストを生成するとき、AIは「これはBDDのAutomationステップで、Double-Loop TDDの外側ループのRedフェーズだ」と認識しています。この認識があるから、受け入れテストをRedのままにしておくべきだと判断できます。

**エラー時のリトライ戦略**

```
cycle.md に定義されているエラー処理:

Red → Green 失敗の場合:
  1. エラーメッセージを分析する
  2. 修正を試みる（最大3回リトライ）
  3. 3回失敗したら停止して、何が問題かをユーザーに報告する

テスト実行エラーの場合:
  1. テスト基盤の問題（import漏れ、設定ミス）を切り分ける
  2. 修正を提案する

受け入れテストが Green にならない場合:
  1. 不足している内側ループを特定する
  2. 追加の内側ループを自動実行する

仕様の不整合が見つかった場合:
  1. Phase 2のレビューゲートに戻る
  2. ユーザーに仕様の修正を求める
```

このエラー処理をSkillファイルに入れた理由は「AIが行き詰まったときに何をすべきかを定義する」ためです。定義がなければ、AIは行き詰まったときに「すみません、できませんでした」と返すか、無限にリトライし続けます。3回でリトライを止めてユーザーに報告する、という振る舞いを明示的に定義しています。

---

## /sfad spec, test, impl の設計意図

### cycleの手動分解版: なぜ分けたか

cycleは8 Phase全てを自動実行します。しかし実際の開発では、全フェーズを一気に回せない場面があります。

```
/sfad spec を単独で使う場面:
  - 仕様だけ先に合意したい
  - エンジニアではない人に仕様を確認してもらいたい
  - チーム内で仕様レビューのタイミングを作りたい
  - 実装の前に「何を作るか」を明確にしたい

/sfad test を単独で使う場面:
  - specで確定した仕様からテストだけ生成したい
  - TDDのRedフェーズだけ先に用意したい
  - テストを先に書いて、実装は別の人に任せたい

/sfad impl を単独で使う場面:
  - テストは既にある。実装だけをGreenにしたい
  - バグ修正のためにRed→Greenのサイクルを回したい
  - 既存テストに対してCanon TDDで進めたい
```

### Skillファイルに入れた情報

**spec.md のExample Map構造定義**

```
spec.md に定義されているExample Mapの構造:

Story（黄色）: ユーザーストーリー
  ├── Rule（青色）: ビジネスルール
  │     ├── Example（緑色）: 具体例1
  │     ├── Example（緑色）: 具体例2
  │     └── Example（緑色）: 具体例3
  ├── Rule（青色）: ビジネスルール
  │     └── Example（緑色）: 具体例1
  └── Question（赤色）: 未解決の質問

AIのDiscovery進め方:
  PO視点: 「この機能の主な利用者は？」「ビジネスルールは？」
  Dev視点: 「既存の類似機能は？」「外部依存は？」「パフォーマンス要件は？」
  QA視点: 「0件のときは？」「同時編集は？」「不正入力は？」
```

Matt WynneのExample Mappingを忠実に再現しつつ、「AIが3役を担う」という適応を加えました。通常のExample MappingはPO（プロダクトオーナー）、Dev（開発者）、QA（テスター）の3人で行いますが、SFADではAIが3つの視点を順番に提示します。

**test.md のDouble-Loop構造**

```
test.md に定義されているDouble-Loop構造:

外側ループ: 受け入れテスト
  目的: 「ユーザーの要求を満たすか」
  粒度: 機能全体
  モック: 最小限（統合テストに近い）
  タイミング: 最初に書いて最後にGreenになる

内側ループ: UCテスト
  目的: 「この振る舞いは正しいか」
  粒度: 1ユースケース
  モック: 外部依存をモック
  タイミング: 1つずつRed → Green

構造マッピング:
  UC-1 → テストグループ 'UC-1: {名前}'
    Given → セットアップ/モック設定
    When  → 操作実行
    Then  → アサーション

テスト流派の使い分け:
  FE ページ/コンポーネント → London School（モック多め）
  BE エンドポイント → London School（Service層をモック）
  BE サービス層 → Chicago School（状態検証）
  BE ドメインモデル → Chicago School（モック不要）
```

**impl.md のCanon TDDサイクル定義**

```
impl.md に定義されているCanon TDDサイクル:

各UCについて以下を繰り返す:

  1. [Red] テストが失敗することを確認する
     → テストのアサーションから「何を実装すべきか」が明確

  2. [Green] テストを通す最小コードを書く
     → YAGNI: アサーションを満たすだけの実装
     → 計算結果をコピペしない（Kent Beckのダブルチェック原則）

  3. [Refactor] Greenのままコード改善
     → 重複除去、命名改善、構造整理
     → テストがRedになったらRefactor前に戻す

  4. [Test List更新] 新発見のシナリオがあれば追加
     → [ADDED] マークで追記

  5. [Next] Test Listの次の項目へ

Uncle Bobの三法則:
  1. 失敗テストなしにプロダクションコードを書かない
  2. 失敗するのに十分な量以上のテストを書かない
  3. テストを通すのに十分な量以上のプロダクションコードを書かない

Outside-In実装順序:
  FE: ページスケルトン → 型定義 → データ取得層 → UIコンポーネント → 統合
  BE: エンドポイント → リクエスト/レスポンス型 → サービス層 → データアクセス層
```

---

## /sfad reverse の設計意図

### specの逆方向

specは「要件 → 仕様」の方向です。reverseは「コード → 仕様」の逆方向です。

```
通常の方向（spec / cycle）:
  ユーザーの要件 → Example Mapping → Given-When-Then → テスト → 実装

逆方向（reverse）:
  既存コード → 振る舞い抽出 → Example Map → 不明点検出 → ユーザー承認 → 仕様確定 → テスト生成
```

### 7 Phaseの設計

```
reverse.md の7 Phase:

Phase 1: 対象コードの特定と読み込み
  → 機能名 or ファイルパスから関連コードを自動探索
  → 【ゲート】対象範囲のユーザー承認

Phase 2: 振る舞い抽出（AI分析）
  → エンドポイント、条件分岐、エラー処理、状態管理、型定義、定数を分析

Phase 3: Example Map生成
  → 抽出した振る舞いをExample Map形式に構造化
  → 各Ruleに確信度を付与

Phase 4: 不明点・矛盾の検出
  → Dead Code、未テストの振る舞い、コードとテストの矛盾、エッジケース漏れ

Phase 5: ユーザーバリデーション（最重要ゲート）
  → 全Ruleの承認 + 全Questionへの回答
  → 【ゲート】承認なしでは先に進まない

Phase 6: 仕様ファイル生成
  → /sfad specと同一フォーマットで出力

Phase 7: テスト生成（オプション）
  → --with-tests フラグ指定時のみ
```

### Skillファイルに入れた情報

**振る舞い抽出マトリクス**

```
reverse.md に定義されている分析対象:

エンドポイント/ページ → 機能の境界とAPI契約
  手がかり: ルーティング定義、コンポーネントexport、デコレータ

条件分岐 → ビジネスルール
  手がかり: if/switch/match、バリデーション、ガード節

エラーハンドリング → 異常系パターン
  手がかり: try/catch、HTTPException、エラーレスポンス

状態管理 → 状態遷移
  手がかり: useState、Redux、DBステータス更新

型定義 → データ構造
  手がかり: Pydantic model、TypeScript interface、struct

定数/設定値 → ビジネス制約
  手がかり: マジックナンバー、設定値、閾値、enum

コメント/docstring → 開発者の意図
  手がかり: 既存ドキュメント、TODO、FIXME

既存テスト → テスト済みの振る舞い
  手がかり: test/describe/itのアサーション
```

このマトリクスがあることで、AIは体系的にコードを分析できます。「条件分岐からビジネスルールを読み取る」「定数からビジネス制約を読み取る」という分析の視点をAIに与えています。

**確信度判定基準**

```
reverse.md に定義されている確信度:

高: コードとテストの両方で確認できる
  → ほぼ確実にこの振る舞いが正しい

中: コードにはあるがテストが不十分、またはコメントのみ
  → 振る舞いは読み取れるが意図は推測

低: コードの意図が不明確、使われていない可能性、矛盾がある
  → ユーザー確認が必須
```

**6つの問題カテゴリ定義**

```
reverse.md に定義されている問題カテゴリ:

[DEAD CODE]      到達不能なコードパス
  検出方法: 呼び出し元がない関数、到達不能なelseブランチ

[UNDOCUMENTED]   テストもコメントもない振る舞い
  検出方法: テストカバレッジのギャップ、マジックナンバー

[INCONSISTENT]   コードとテストの矛盾
  検出方法: テストの期待値とコードの実装値の不一致

[MISSING]        未処理の境界条件
  検出方法: nullチェック不足、0件/空文字/最大値の未処理

[SECURITY]       セキュリティ上の懸念
  検出方法: 入力サニタイズ不足、認証チェック漏れ

[IMPLICIT]       暗黙の業務ルール
  検出方法: コメントなしの条件分岐、ハードコード値
```

無料記事で紹介した認証機能のreverse実行結果で、これらのタグが実際に使われていました。Critical 3件、High 1件、Medium 3件、Low 4件を検出しました。

---

## Claude Code Skillの仕組み

### 2層構造: skills/ と commands/

```
~/.claude/skills/   ← ロジック（AIが参照する詳細手順）
~/.claude/commands/ ← インターフェース（ユーザーが呼び出すエントリポイント）
```

**skills/ はAIが読むもの**。手順、判断基準、チェックリスト、エラー処理ルール。長くなっても構いません。AIはこのファイルを全て読んで、書かれた通りに動作します。

**commands/ はユーザーが触るもの**。短い説明文と、どのskillに従うかの指示だけです。

### SFADの実際のファイル構成

```
~/.claude/skills/sfad/
  ├── SKILL.md       ← 理論的基盤、サブスキル一覧、テスト流派テーブル
  ├── init.md        ← 11項目 x 10スタック（12 Phase）
  ├── cycle.md       ← 8 Phase（BDD + Double-Loop TDD）
  ├── spec.md        ← Example Mapping + Given-When-Then
  ├── test.md        ← Double-Loop テスト生成
  ├── impl.md        ← Canon TDD サイクル
  └── reverse.md     ← 7 Phase 仕様抽出

~/.claude/commands/sfad/
  ├── init.md        ← /sfad init のエントリポイント
  ├── cycle.md       ← /sfad cycle のエントリポイント
  ├── spec.md        ← /sfad spec のエントリポイント
  ├── test.md        ← /sfad test のエントリポイント
  ├── impl.md        ← /sfad impl のエントリポイント
  └── reverse.md     ← /sfad reverse のエントリポイント
```

commands/ の各ファイルは非常に短いです。実際のcycle.mdコマンド定義の例を見てみましょう。

```markdown
---
description: "SFAD Cycle: BDD Discovery + Double-Loop TDD 全自動サイクル"
---

$ARGUMENTS を受け取り、/sfad:cycle スキルに従って実行してください。

## Arguments
- 第1引数: 機能名（例: "お問い合わせ一覧"）
- @<path>: 既存コードのパス
- --be: バックエンドのみ
- --fe: フロントエンドのみ
```

これだけです。ロジックは全てskills/sfad/cycle.mdに書かれています。

---

## Skillファイルに「何を入れたか」の完全公開

### SKILL.md に入れた情報

SKILL.mdはSFAD全体の「脳」です。以下の情報を入れました。

**理論的基盤と出典**

```
SKILL.md に定義されている理論的基盤:

Canon TDD (Kent Beck, 2023):
  → SFADでの適応: 5ステップ（Test List → 選択 → Green → Refactor → 繰り返し）

BDD 3 Practices (Dan North / Cucumber):
  → SFADでの適応: Discovery → Formulation → Automation

Example Mapping (Matt Wynne):
  → SFADでの適応: ルール/具体例/質問の構造化Discovery

Double-Loop TDD (Freeman & Pryce, GOOS):
  → SFADでの適応: 外側=受け入れテスト、内側=UCテスト

Given-When-Then (North & Matts, 2004):
  → SFADでの適応: シナリオの構造化記法

London School TDD (GOOS):
  → SFADでの適応: FE/BE エンドポイントのテスト

Chicago School TDD (Kent Beck):
  → SFADでの適応: BE サービス/ドメインのテスト
```

**テスト流派の使い分けテーブル**

```
SKILL.md に定義されている使い分け:

FE ページ/テンプレート → London School（モック多め）
  理由: hooks/APIは外部依存 → モックで分離し、UIの振る舞いに集中

FE コンポーネント → London School
  理由: props/eventsの検証。内部実装に依存しない

BE エンドポイント → London School
  理由: Service層をモックし、API契約を検証

BE サービス層 → Chicago School（状態検証）
  理由: ビジネスロジックの結果を検証。モック最小限

BE ドメインモデル → Chicago School
  理由: 純粋な状態変換。モック不要
```

**7つの設計原則**

SKILL.mdのPrinciplesセクションに7原則を簡潔にまとめています。AIがcycleやimplを実行するとき、この原則を参照して判断を行います。

**ライフサイクル図**

```
SKILL.md に定義されているライフサイクル:

新規プロジェクト              既存プロジェクト（仕様書なし）
      │                             │
  /sfad init                   /sfad reverse [feature]
      │                             │
      ├─────────────┐               │
      │             │               │
  /sfad cycle   /sfad spec    docs/specs/{f}.md
      │             │               │
      │         /sfad test     /sfad test（ギャップ分のみ）
      │             │               │
      │         /sfad impl     全Green確認
      │             │               │
      └─────────────┘               │
                                    │
              以後の変更: /sfad cycle [feature変更]
```

### cycle.md に入れた情報

前述の8 Phase + 3ゲート + エラー処理に加えて、以下の情報も入れました。

**進捗表示フォーマット**

```
cycle.md に定義されている進捗表示:

[UC-1/5] ページタイトル表示
  Red: 1 test failing (ContactsListTemplate not found)
  Green: 1 test passing
  Test List: +0 新規発見
  → Next: UC-2

[UC-2/5] データ表示
  Red: 1 test failing (useContacts not implemented)
  Green: 1 test passing
  Test List: +1 新規発見 [ADDED] "日付フォーマット"
  → Next: UC-3 (+ 追加テスト処理)
```

この進捗表示をSkillに定義した理由は、AIが実行中に「今どこにいるか」をユーザーに伝えるためです。定義がなければ、AIはだまって実装を進めます。進捗が見えないと、ユーザーは不安になります。

**他コマンドとの関係**

```
cycle.md に定義されている関係:

/sfad cycle = Phase 1-8 の全自動実行

手動で個別実行する場合:
  /sfad spec   = Phase 1 + 2（Discovery + Formulation）
  /sfad test   = Phase 3 + 4 のテスト生成部分
  /sfad impl   = Phase 4 + 5 + 6 + 7 の実装部分
```

### なぜこれらの情報が必要だったか

各カテゴリの情報がなぜ必要だったかをまとめます。

**理論的基盤を入れた理由**: AIが「なぜこうするのか」を理解して、ユーザーに説明できるようにするためです。ユーザーが「なぜテストを先に書くの？」と聞いたとき、AIは「Canon TDD（Kent Beck, 2023）のTest Listプラクティスに基づいています」と答えられます。

**Stack Detection Matrixを入れた理由**: 言語/フレームワークに応じて適切なツールを選ぶためです。Pythonプロジェクトでは`pytest`、Next.jsプロジェクトでは`vitest`を自動で選びます。

**ゲート定義を入れた理由**: AIが暴走せず、人間の判断を仰ぐポイントを制御するためです。ゲートがなければ、AIは仕様を推測して勝手に実装を進めます。78件のバグの再現です。

**エラー処理を入れた理由**: AIが行き詰まったときに「何をすべきか」を定義するためです。定義がなければ、AIは無限ループするか、あるいは何も言わずに止まります。「3回リトライして失敗したらユーザーに報告する」という明確なルールがあることで、予測可能な振る舞いになります。

**進捗表示フォーマットを入れた理由**: ユーザーが「今何が起きているか」を把握できるようにするためです。AIが黙って作業するのは不安です。

---

## 「あなたが自分のSkillを作るなら」セクション

SFADの設計思想を読んだ上で、「自分もSkillを作りたい」と思った方向けに、具体的な手順を書きます。

### Step 1: 自分のワークフローを言語化する

まず、普段の開発フローを手順書として書き出します。「頭の中にあること」を「文章」にするだけです。

```
例: コードレビューの手順

1. PRの差分を全部読む
2. セキュリティの問題がないか確認する
   - SQLインジェクション
   - XSS
   - 認証チェック漏れ
3. パフォーマンスの問題がないか確認する
   - N+1クエリ
   - 不要な再レンダリング
4. テストが書かれているか確認する
5. コードの品質を確認する
   - 命名が適切か
   - 重複がないか
   - 複雑すぎないか
6. コメントを残す
```

完璧でなくていいです。「自分はこうやっている」を書き出すだけです。

### Step 2: 手順をPhaseに分割する

書き出した手順を、独立した工程として区切ります。

```
Phase 1: セキュリティチェック
Phase 2: パフォーマンスチェック
Phase 3: テストカバレッジチェック
Phase 4: コード品質チェック
Phase 5: サマリー出力
```

分割のコツは「各Phaseが独立して完了判定できるか」です。「セキュリティチェックは完了したが、パフォーマンスチェックはまだ」と言える単位に分けます。

### Step 3: ゲートを設定する

「人間の判断が必要な箇所」を探します。AIが自動で判断してはいけない箇所です。

```
Phase 1: セキュリティチェック
  → AIがセキュリティの問題を検出した場合
  → 【ゲート】ユーザーに報告して対応方針を確認する
    （AIが「問題ないです」と自動判断するのは危険）

Phase 4: コード品質チェック
  → AIがリファクタリングを提案する場合
  → 【ゲート】ユーザーに提案を提示して承認を求める
    （AIが勝手にコードを変更するのは望ましくない）
```

### Step 4: 各Phaseの「AIがやること」を定義する

各Phaseで、AIが具体的に何を見て、何を判断して、何を出力するかを書きます。

```
Phase 1: セキュリティチェック

AIがやること:
  1. PRの差分ファイルを全て読み込む
  2. 以下のパターンを検索する:
     - SQLクエリの文字列連結
     - innerHTML / dangerouslySetInnerHTML の使用
     - 認証デコレータの欠如
     - 外部入力のサニタイズ未実施
  3. 検出した問題を [SECURITY] タグ付きでリストアップする
  4. 問題がなければ「セキュリティ問題: なし」と報告する
```

### Step 5: エラーケースを定義する

AIが行き詰まったとき、何をすべきかを定義します。

```
エラーケース:

ファイルが大きすぎて読み込めない場合:
  → ユーザーに「このファイルは手動レビューが必要です」と報告する

判断に迷う場合:
  → 確信度を付けて報告する。「[SECURITY] 確信度: 中 — SQLインジェクションの可能性がありますが、ORMを使用しているため安全かもしれません」

PRの差分が0の場合:
  → 「変更がありません」と報告して終了する
```

### Step 6: commands/にエントリポイントを書く

```markdown
---
description: "Code Review: セキュリティ・パフォーマンス・品質チェック"
---

$ARGUMENTS を受け取り、/review スキルに従って実行してください。

## Arguments
- 第1引数: PRのパスまたはURL
- --security-only: セキュリティチェックのみ
- --quick: 簡易チェック
```

### Step 7: テストする

実際に使って改善します。

```bash
# 実際にPRに対して実行してみる
/review @path/to/pr-diff

# 出力を確認して、不足している観点を追加する
# 過剰な検出があれば、条件を調整する
# ゲートの位置が不適切なら移動する
```

最初から完璧なSkillは作れません。使いながら「ここが足りない」「ここは過剰」を調整していきます。

### 具体例: コードレビューSkillを作るなら

```
~/.claude/skills/review/
  ├── SKILL.md     ← レビュー基準、チェック観点の一覧
  └── review.md    ← Phase定義
                      Phase 1: セキュリティチェック
                      Phase 2: パフォーマンスチェック
                      Phase 3: テストカバレッジチェック
                      Phase 4: コード品質チェック
                      Phase 5: サマリー出力

~/.claude/commands/review/
  └── review.md    ← /review コマンド定義
```

---

## BDD, Canon TDD, Double-Loop TDDとの対応関係

### SFADは「組み合わせ + AI適応」であり、新しい理論ではない

SFADは既存の確立された手法を組み合わせ、AI支援開発に適応させたものです。新しい理論を発明したわけではありません。

```
各概念の出典:

Canon TDD
  出典: Kent Beck (2023)
  SFADでの適応: Test Listを「実装前に書く → 実装中に育てる」として運用

BDD 3 Practices
  出典: Dan North / Cucumber
  SFADでの適応: Discovery → Formulation → Automationをcycleの8 Phaseに展開

Example Mapping
  出典: Matt Wynne
  SFADでの適応: Three Amigosの3役をAIが担う

Double-Loop TDD
  出典: Freeman & Pryce (GOOS: Growing Object-Oriented Software, Guided by Tests)
  SFADでの適応: 外側=受け入れテスト、内側=UCテスト

Given-When-Then
  出典: Dan North & Chris Matts (2004)
  SFADでの適応: specのFormulationフェーズで使用

London School TDD
  出典: GOOS (Freeman & Pryce)
  SFADでの適応: FE/BEエンドポイントのテスト

Chicago School TDD
  出典: Kent Beck
  SFADでの適応: BEサービス/ドメインのテスト
```

### 「巨人の肩に乗る」

SFADが独自にやったことは2つだけです。

**1. 既存手法の組み合わせを1つのワークフローにした**

BDDとTDDは別々に語られることが多いです。でも実際の開発では、BDDで仕様を決めた後にTDDで実装します。この「繋ぎ目」が自動化されていないと、「仕様は決めたけどTDDを飛ばしてしまった」が起きます。

SFADのcycleは、BDDのDiscovery → Formulation → AutomationとTDDのRed → Green → Refactorを1つの連続したフローにしています。繋ぎ目が存在しないので、「飛ばす」ことが構造的にできません。

**2. AI支援に適応した**

人間だけでExample Mappingをするときは、付箋を使って壁に貼ります。AIと一緒にやるときは、Markdownで構造化します。

人間だけでThree Amigosをするときは、3人の人間が必要です。AIと一緒にやるときは、AIがPO/Dev/QAの3つの視点を提供します。

Canon TDDでTest Listを書くとき、人間は紙やホワイトボードを使います。SFADではTest Listをspecファイルの中に構造化して書き、実装中の追加も [ADDED] マークで追跡できるようにしました。

これらの「AI適応」がSFADの独自部分です。理論的基盤は全て既存の手法から取っています。Kent Beck、Dan North、Freeman & Pryce、Matt Wynneの仕事の上に乗っています。

---

## おわりに

12個のコマンドを6個に絞る過程で学んだ最大の教訓は、「シンプルさは機能の削除ではなく、本質の抽出である」ということです。

12個のコマンドは、BDDとTDDの理論を忠実にコマンドに分解したものでした。でも「理論的に正しい分割」と「使いやすい分割」は違います。ユーザーが「どのコマンドを使えばいいか」で迷う時点で、設計が間違っています。

6個のコマンドは、78件のバグから逆算して導いたものです。「このバグを防ぐために何が必要か」を問い続けた結果、削れないものだけが残りました。

Skillファイルの設計で最も重要なのは「AIに何を伝えるか」ではなく「AIにどこで止まらせるか」です。ゲートの設計が、SkillとただのドキュメントのCoの違いです。

---

次回は、Claude Code Skillを0から作る手順を、実際のファイルとともに公開します。SFADのようなドメイン特化型Skillではなく、もっと汎用的な「自分の開発フローをSkill化する」方法を解説する予定です。
