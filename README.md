# Qiita 予約投稿

SFAD（Spec-First AI Development）シリーズの Qiita 記事を予約投稿で自動公開するリポジトリ。

## 仕組み

1. `schedule.json` に公開日とファイル名を定義
2. GitHub Actions が毎朝 JST 7:00 に `schedule.json` をチェック
3. 当日分の記事の `private: true` → `private: false` に変更して `npx qiita publish`
4. 変更を自動コミット

## セットアップ

1. GitHub Settings → Secrets → `QIITA_TOKEN` を設定
2. `schedule.json` の日付を調整
3. 記事は `public/` に `private: true` で配置

## 手動公開

```bash
# 特定の記事を手動で公開
sed -i 's/^private: true$/private: false/' public/article-04-qiita.md
npx qiita publish article-04-qiita
```

## スケジュール

| 公開日 | 記事 |
|---|---|
| 2026-03-02 | テスト不足でデグレ11回。Double-Loop TDD |
| 2026-03-09 | AI生成コードを「読む技術」 |
| 2026-03-16 | 仕様書がないコードをAIに読ませたら |
| 2026-03-23 | 引き継ぎ地獄エンジニアのためのSFAD |
| 2026-03-30 | AIに伝わる仕様書の書き方 ― Example Mapping |
| 2026-04-06 | エラーを「握りつぶす」コードの見抜き方 |
| 2026-04-13 | AIと開発して78個のバグを踏んだので全部分類した |
| 2026-04-20 | Claude CodeとTDDを組み合わせたら |
| 2026-04-27 | 品質基盤ゼロのチームを引き受けた新任TLへ |
| 2026-05-04 | 78バグから導いた7つの設計原則（ダイジェスト版） |
| 2026-05-11 | SFADの全6コマンド設計思想（ダイジェスト版） |
| 2026-05-18 | Claude Code Skillの作り方（ダイジェスト版） |
| 2026-05-25 | AI導入提案が通らない理由と |
| 2026-06-01 | AI時代の開発ワークフロー実践ロードマップ |
