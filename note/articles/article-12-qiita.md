---
title: テストファイルの中で本番ロジックを再実装していた話 ― 偽物テストの見抜き方
tags:
  - テスト
  - AI駆動開発
  - ClaudeCode
  - リファクタリング
  - SFAD
private: false
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---

## TL;DR

- AI に「このロジックをテストして」と頼むと、本番のコードを import できないとき **テストファイルの中に副本実装を作ってそれをテストする**ことがある
- これは **テストカバレッジ ゼロ**。本番ロジックがバグっていても永遠に緑のまま
- 実例: 11 本のテストのうち 5 本が「テスト用実装」をテストしているだけで、本番側の関数は 1 行も叩いていなかった
- 根本原因は **本番コードに切り出すべき純粋関数が存在しない**こと（ロジックがハンドラに直書き）
- 偽物テストを見抜く 5 つのサインと、構造的に防ぐ方法を解説

## この記事でできること

| やりたいこと | この記事で得られるもの |
|---|---|
| 偽物テストを即座に見抜きたい | 5 つの判定サイン |
| AI に正しいテストを書かせたい | プロンプトの注意点 |
| ロジックをテスト可能な構造にしたい | レイヤー分離の最小ステップ |
| テストレビューの観点を増やしたい | カバレッジ表だけでは見えない罠 |

---

ある日 PR のテストファイルを開いて、最初の 50 行で固まりました。

```python
# tests/test_ranking_logic.py

from app.schemas.ranking import DEFAULT_PLACEMENT_POINTS

class StandingsCalculator:
    """順位計算クラス（テスト用実装）"""
    
    def __init__(self, placement_points=None, kill_multiplier=1.0):
        self.placement_points = placement_points or DEFAULT_PLACEMENT_POINTS
        self.kill_multiplier = kill_multiplier
    
    def calculate_game_points(self, placement, kills):
        placement_pt = self.placement_points.get(str(placement), 0)
        kill_pt = kills * self.kill_multiplier
        return placement_pt + kill_pt
    
    def calculate_standings(self, games, participants):
        # ... 100 行近い実装 ...
```

「**テスト用実装**」と書かれたクラスがテストファイルの先頭に丸ごと書かれていて、その下のテストはこの自作クラスを叩いているだけ。本番の `app/services/ranking.py` を import すらしていない。

`DEFAULT_PLACEMENT_POINTS` だけは本番から import されていますが、計算ロジックは **完全に副本**。本番ロジックが壊れていても、このテストは永遠に緑のまま通ります。

CI は緑、カバレッジレポートは「ranking モジュール 80%」と表示。でも実態は **本番カバレッジ ゼロ**。

これがどうやって生まれたのか、どう見抜くのか、どう防ぐのかを書きます。

---

## なぜこれが生まれるのか

AI に「順位計算ロジックをテストして」と依頼したとき、AI が取る選択肢は 2 つあります。

### 選択肢 A: 本番から import してテストする（正解）

```python
from app.services.ranking import calculate_standings

def test_simple_ranking():
    games = [...]
    settings = PointSettings(...)
    result = calculate_standings(games, settings)
    assert result[0].rank == 1
```

### 選択肢 B: テストファイル内に副本を実装してテストする（偽物）

```python
class StandingsCalculator:
    """テスト用実装"""
    def calculate_standings(self, games, participants):
        # 本番と同じロジックを書く
        ...

def test_simple_ranking():
    calc = StandingsCalculator()
    result = calc.calculate_standings([...], {...})
    assert result[0]["rank"] == 1
```

**AI が選択肢 B を取る条件**:

1. **本番側に切り出された純粋関数がない**。ロジックが API ハンドラの中に直書きされていて、import できない
2. **import すると依存（DB セッション、リクエストオブジェクト等）が大量に必要**で、テスト用にモックするのが大変
3. **AI への依頼が「ロジックをテストして」だけ**で、「本番から import せよ」と明示されていない

この 3 つが揃うと、AI は親切心で「テスト用に簡略化した実装を書きました！」と副本を書きます。**動いてるテストっぽいもの**は出てくるので、人間レビュアーがざっと見ると気付きません。

---

## 偽物テストを見抜く 5 つのサイン

### サイン 1: テストファイル冒頭にクラス定義がある

```python
class StandingsCalculator:
    """テスト用実装"""
```

「テスト用」「テスト用ヘルパー」「Reproduction」「再現実装」みたいな単語が docstring にあったら警戒します。本来テストファイルにあるべきは **テスト関数とフィクスチャ**だけ。プロダクションコードを模した「実装っぽいクラス」がテストファイルにある時点で疑う。

### サイン 2: 本番モジュールを import していない

```python
# 良いテスト
from app.services.ranking import calculate_standings

# 偽物テスト（本番を import していない）
from app.schemas.ranking import DEFAULT_PLACEMENT_POINTS  # ← 定数だけ
# import calculate_... が無い
```

`from app.services... import ...` のような **ロジック側 import が存在しないテスト**は、何をテストしているのか怪しいと思った方がいいです。

### サイン 3: 「APIロジックを再現」「Behavior matches」のコメント

```python
def calculate_ranking(matches_data, ...):
    """
    APIのランキング計算ロジックを再現。
    """
```

「再現」「相当する実装」「mirroring」みたいな言葉が出てきたら、それは **本物ではない** という告白です。再現は再現でしかありません。本物が変わってもテストは検知しません。

### サイン 4: テスト名と assert の主張が一致していない

実例:

```python
def test_team_numbers_assigned_in_entry_order(self):
    """チーム番号が entry_at 順に割り当てられること"""
    # ... 3 件のテストデータ作成 ...
    
    # Act
    await jobs.assign_team_numbers(...)
    
    # Assert
    assert len(added_participants) == 3  # ← 順序を一切確認していない！
```

テスト名は「**順番に割り当て**」と主張しているのに、assert は **件数しか見ていない**。順序の検証も、`team_number == 1, 2, 3` の検証もありません。**テスト名詐欺**です。

これを見つけるコツは、テスト名から **期待される検証項目** を頭の中で列挙してから本文を読むこと。

### サイン 5: モック地獄でクエリ内容を文字列マッチしている

```python
async def _execute(stmt, *args, **kwargs):
    stmt_str = str(stmt).lower()
    if "entries" in stmt_str:
        return entries_mock
    elif "discord_guild_organizations" in stmt_str:
        return guild_orgs_mock
    else:
        return []
```

DB セッションのモックを、**実際に発行される SQL 文字列に "entries" が含まれるか** で振り分けている。これは **テストではなくモック芝居**です。リファクタでクエリの形が変わったら即座に壊れるし、別のテーブルが偶然マッチして誤通過することもあります。

これが必要になっている時点で、本番コードが **DB に密結合しすぎ** なシグナル。テスト可能な構造になっていないことを物語っています。

---

## 根本原因: テスト不可能な構造

なぜ AI が副本を書くしかなかったのか。本番側のコードを見ると一目瞭然でした。

```python
@router.get("/scrim-matches/{match_id}/standings")
async def get_standings(
    match_id: UUID,
    db: AsyncSession = Depends(deps.get_db),
):
    # 110 行のハンドラ
    # 1. DB クエリ（30 行）
    # 2. 設定取得（10 行）
    # 3. データ集計（30 行）
    # 4. ポイント計算（20 行）  ← ★ ここをテストしたい
    # 5. ソート＆ランク付与（15 行）
    # 6. レスポンス変換（5 行）
```

110 行のハンドラの中に、**順位計算ロジックがべったり**埋まっていました。これを単体テストするには:

1. FastAPI のリクエストオブジェクトを作る
2. DB セッションを立てる（or モックする）
3. テストデータをシードする
4. ハンドラを呼ぶ

これだけで「テスト 1 件あたり 50 行のセットアップ」になります。AI が「面倒だから副本を書いた方が早い」と判断するのも理解できる規模です。

つまり問題は AI ではなく、**本番コードがテスト可能な形になっていない**こと。

---

## 修正: 純粋関数を切り出す

### Before (テスト不可能)

```python
# app/api/v1/standings.py

@router.get("/scrim-matches/{match_id}/standings")
async def get_standings(match_id: UUID, db: AsyncSession = Depends(...)):
    # DB クエリ
    games = await db.execute(...)
    settings = await db.execute(...)
    
    # ★ 計算ロジック（埋め込み）
    team_stats = {}
    for game in games:
        for result in game.results:
            placement_pt = settings.placement_points.get(str(result.placement), 0)
            kill_pt = result.kills * settings.kill_multiplier
            ...
    standings = []
    for team_id, stats in team_stats.items():
        ...
    standings.sort(key=lambda x: x.total_points, reverse=True)
    # ランク付与
    ...
    
    return StandingsResponse(standings=standings)
```

### After (テスト可能)

```python
# app/domain/standings.py  ← 新規。純粋関数。

from dataclasses import dataclass

@dataclass
class GameResult:
    team_id: str
    placement: int
    kills: int

@dataclass
class PointSettings:
    placement_points: dict[str, int]
    kill_multiplier: float

@dataclass
class TeamStanding:
    rank: int
    team_id: str
    total_points: float
    total_kills: int

def calculate_game_points(placement: int, kills: int, settings: PointSettings) -> float:
    placement_pt = settings.placement_points.get(str(placement), 0)
    kill_pt = kills * settings.kill_multiplier
    return placement_pt + kill_pt

def calculate_standings(
    games: list[list[GameResult]],
    settings: PointSettings,
) -> list[TeamStanding]:
    team_stats = {}
    for game in games:
        for result in game:
            ...
    
    standings = [...]
    standings.sort(key=lambda x: x.total_points, reverse=True)
    
    # ランク付与（同点処理含む）
    current_rank = 1
    for i, s in enumerate(standings):
        if i > 0 and s.total_points == standings[i-1].total_points:
            s.rank = standings[i-1].rank
        else:
            s.rank = current_rank
        current_rank = i + 2
    
    return standings


# app/api/v1/standings.py  ← ペラペラに

from app.domain.standings import calculate_standings, GameResult, PointSettings

@router.get("/scrim-matches/{match_id}/standings")
async def get_standings(match_id: UUID, db: AsyncSession = Depends(...)):
    games_db = await db.execute(...)
    settings_db = await db.execute(...)
    
    # DB モデル → ドメイン値オブジェクトに変換
    games = [
        [GameResult(r.team_id, r.placement, r.kills) for r in game.results]
        for game in games_db
    ]
    settings = PointSettings(
        placement_points=settings_db.placement_points,
        kill_multiplier=settings_db.kill_multiplier,
    )
    
    # ★ 計算は純粋関数に委譲
    standings = calculate_standings(games, settings)
    
    return StandingsResponse(standings=standings)
```

### テストが本物になる

```python
# tests/domain/test_standings.py

from app.domain.standings import calculate_standings, GameResult, PointSettings

def test_simple_ranking():
    games = [
        [
            GameResult("team-a", placement=1, kills=5),
            GameResult("team-b", placement=2, kills=3),
            GameResult("team-c", placement=3, kills=2),
        ]
    ]
    settings = PointSettings(
        placement_points={"1": 12, "2": 9, "3": 7},
        kill_multiplier=1.0,
    )
    
    result = calculate_standings(games, settings)
    
    assert len(result) == 3
    assert result[0].team_id == "team-a"
    assert result[0].rank == 1
    assert result[0].total_points == 17  # 12 + 5
    assert result[1].rank == 2
    assert result[1].total_points == 12  # 9 + 3
```

これは **本物**です:
- 本番の関数を import している
- DB モックも FastAPI モックも要らない
- msec で走る
- 100 ケース書き放題

---

## チェック: あなたのテストは本物か？

```bash
# テストファイルが本番モジュールを import しているかチェック
grep -L "from app.services" tests/test_*.py
grep -L "from app.domain" tests/test_*.py

# テストファイル内に class 定義（テスト用ヘルパー以外）があるかチェック
grep -B1 "class .*:" tests/test_*.py | grep -v "test_"

# 「再現」「テスト用実装」のコメントを探す
grep -rn "テスト用実装\|再現\|mirror" tests/
```

これで偽物の候補が炙り出せます。

---

## AI に「本物のテスト」を書かせるプロンプト

依頼するときに **「本番から import せよ」を明示**します:

```
以下のロジックの単体テストを書いてください。

【厳守ルール】
1. 必ず本番のモジュールから関数を import してテストすること
2. テストファイル内に「テスト用実装」「再現実装」「副本」のクラスを書くことを禁止する
3. もし import できない構造なら、まずリファクタ案を提示してから着手すること
4. テストの assert は「呼ばれた回数」「リストの長さ」だけでなく、必ず「値」を検証すること
5. テスト名で主張している内容（順序・内容・状態）は、必ず assert で検証すること

import 先: app/services/ranking.py
テスト対象: calculate_standings 関数
```

特に重要なのが **3 番目**。AI が「import できない」と言ってきたら、それは本番側がテスト可能な構造になっていない証拠です。先にリファクタする必要があります。

---

## まとめ

- AI が「テスト用実装」をテストファイルに書いていたら、それは **テストカバレッジ ゼロ** の偽物
- 偽物テストの 5 サイン: テストファイル内のクラス定義、本番モジュール非 import、「再現」コメント、テスト名と assert の不一致、文字列マッチのモック芝居
- 根本原因は **本番コードに純粋関数が存在しない**こと。ハンドラに直書きされたロジックは構造的にテスト不可能
- 修正は **ドメイン層に純粋関数を切り出し**、ハンドラはペラペラにする
- AI への依頼で **「本番から import せよ」を明示**するだけで偽物の確率が下がる

テストを書くことを目的化すると、こういう偽物が量産されます。**「テストが何を守っているのか」を常に問う**。それがレビュアーの仕事だし、ジュニアに教えるべき一番の観点だと思います。
