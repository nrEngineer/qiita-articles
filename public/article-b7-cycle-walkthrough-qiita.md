---
title: 新SFAD cycle の 8 Phase を一周した記録 ― 認証機能を題材に
tags:
  - SFAD
  - AI駆動開発
  - ClaudeCode
  - BDD
  - TDD
private: true
updated_at: ''
id: null
organization_url_name: null
slide: false
ignorePublish: false
---

## TL;DR

- SFAD `cycle` の 8 Phase を **認証機能 (login/logout/refresh) 一式** で頭から最後まで回した実録
- 全 Phase 合計: **約 2 時間 10 分**。人間の介入は各 Phase のゲート承認のみ
- 出力成果物: 仕様 4 ファイル (約 680 行) + 受け入れテスト 4 本 + UC テスト 14 本 + 実装コード 3 endpoint
- 各 Phase で AI との対話ログ、生成ファイルの抜粋、修正箇所を全公開
- 「Phase が 8 個もあるのに実務で回るの?」→ 回る。Phase 分割で頭が混乱しないほうが早い
- Season 1 の集大成。B1〜B5 で紹介した個別要素が、この記事で統合される

## この記事でできること

| やりたいこと | 対応セクション |
|---|---|
| 8 Phase の全体像を把握したい | 8 Phase 概要 |
| 各 Phase で AI とどう対話するか知りたい | Phase 1〜8 詳細 |
| 各 Phase にかかる時間を知りたい | 時間配分 |
| 出力成果物のボリュームを見たい | 総括 |
| 運用してみた感想を知りたい | 感想 |

---

「SFAD cycle は 8 Phase もあるって、実務で回せるの?」

8 Phase を初めて紹介されたとき、正直そう思いました。4ファイル分割でさえ「増えたな」と感じていたので、Phase が 8 個に増えると聞いて「教科書に載せるだけの机上論では?」と疑ったのです。

結論から書くと、**一周 2 時間 10 分で、壊れない実装がまるごと手に入りました**。

この記事では、認証機能 (login / logout / refresh) を題材に、SFAD cycle の 8 Phase を頭から最後まで回した実録を公開します。各 Phase での AI 対話、生成ファイル、時間配分、全部見せます。

本記事は Season 1 の集大成です。B1 (4ファイル分割) / B2 (攻撃者視点) / B3 (13ルール) / B4 (Threat) / B5 (Resilience) で紹介した要素が、ここで統合されます。

---

## 題材: 認証機能

### 要件

- POST /login: email + password → JWT 発行
- POST /logout: 現行セッション無効化
- POST /refresh: refresh token で新しい access token を発行
- 技術: FastAPI + SQLAlchemy + PostgreSQL + Redis (session store)

### なぜ認証機能を選んだか

- 誰もが実装する機能
- 攻撃対象になりやすい (Credential Stuffing / Session Fixation / IDOR)
- エラーパスが多い (expired token / invalid credentials / rate limit)
- 実装ミスが即本番事故になる

4ファイル × 4 視点の網羅性を確かめるには最適な題材です。

---

## 8 Phase 概要

| Phase | 名前 | 所要 | 出力 |
|---|---|---|---|
| 1 | Example Mapping | 15分 | Rule/Example/Question のドラフト |
| 2 | functional.md 生成 | 15分 | functional.md |
| 3 | threat.md 生成 | 15分 | threat.md |
| 4 | resilience.md 生成 | 10分 | resilience.md |
| 5 | plan.md 生成 | 10分 | plan.md |
| 6 | 受け入れテスト生成 | 15分 | tests/acceptance/* |
| 7 | UC TDD | 60分 | 実装 + UC テスト |
| 8 | 静的解析ゲート | 5分 | lint/type pass |
| **合計** | | **約 2h 25m** | 4 files + tests + impl |

※実測 2h 10m。Phase 間のタスク切り替え時間を含めて 2h 25m 見込んでおくと安全。

---

## Phase 1: Example Mapping (15分)

### 投入プロンプト

```
以下の機能について Example Mapping を作成してください。
機能名: 認証機能 (login/logout/refresh)

Rule/Example/Question の 3 階層で。
- Rule: 必ず守る原則 (3〜7個)
- Example: 各 Rule の具体例 (2〜4個ずつ)
- Question: 決まっていない項目 (3〜5個)

技術スタック: FastAPI + SQLAlchemy + PostgreSQL + Redis
```

### AI の回答 (抜粋)

```markdown
# Example Map: 認証機能

## Rule 1: email + password でログインできる
- Example 1.1: 正しい credentials → 200 + JWT 発行
- Example 1.2: 間違った password → 401 "Invalid credentials"
- Example 1.3: 存在しない email → 401 "Invalid credentials" (ユーザー列挙防止)

## Rule 2: ログイン失敗 5 回で 15 分ロック
- Example 2.1: 5回連続失敗 → 6回目は 429
- Example 2.2: 成功したらカウンターリセット
- Example 2.3: 15分経過で自動解除

## Rule 3: access token は 15 分、refresh token は 30 日
- Example 3.1: 14分59秒で valid
- Example 3.2: 15分01秒で expired → 401

## Rule 4: logout で現行セッションを無効化
- Example 4.1: logout 後に access token で API 叩くと 401
- Example 4.2: logout 後の refresh token も無効

## Rule 5: refresh で新 access token を発行
- Example 5.1: valid refresh token → 新 access + 新 refresh (rotation)
- Example 5.2: expired refresh → 401

## Questions
- Q1: 2FA は今回のスコープ?
- Q2: Session Fixation 対策で session regenerate は必要?
- Q3: Logout 時に全デバイスからログアウトするオプション?
- Q4: Refresh token rotation は強制?
- Q5: Rate limit は IP 単位 or アカウント単位?
```

### 人間の決定

- Q1: 今回スコープ外 (次スプリント)
- Q2: YES (ログイン成功後 session regenerate)
- Q3: YES (`logout?all=true` でサポート)
- Q4: YES (rotation 強制)
- Q5: アカウント単位 (IP は VPN 経由で同じ IP が多数アカウントに)

### Phase 1 の所要: 15分

---

## Phase 2: functional.md 生成 (15分)

### 投入プロンプト

```
Example Mapping の結果を functional.md に落としてください。
Given-When-Then 形式で。
各 Rule に対して 1〜3 の Scenario。
```

### 生成された functional.md (抜粋)

```markdown
# functional.md: 認証機能

## Feature: ログイン

### Rule 1: email + password でログインできる

#### Scenario 1.1: 成功ログイン
Given: email="user@example.com", password="CorrectPassword123!", ユーザーが存在
When: POST /login {email, password}
Then: 
  - 200 OK
  - Response: {access_token, refresh_token, token_type: "Bearer"}
  - Set-Cookie: session_id=xxx; HttpOnly; Secure; SameSite=Lax
  - session_id は login 前と別の値 (session regenerate)

#### Scenario 1.2: 不正なパスワード
Given: email="user@example.com", password="WrongPassword"
When: POST /login {email, password}
Then:
  - 401 Unauthorized
  - Response: {"detail": "Invalid credentials"}
  - ログイン失敗カウンター +1

#### Scenario 1.3: 存在しないメアド
Given: email="nonexistent@example.com"
When: POST /login {email, password="any"}
Then:
  - 401 Unauthorized
  - Response: {"detail": "Invalid credentials"} (1.2 と同じメッセージ)

### Rule 2: ログイン失敗 5 回で 15 分ロック

#### Scenario 2.1: 5 回失敗
Given: email="user@example.com", 既に 4 回失敗済み
When: POST /login (5 回目、間違った password)
Then: 401 + カウンター 5
And: 次のログイン試行 (POST /login) → 429 Too Many Requests
And: lockout_until = now + 15分

## Feature: Logout
...

## Feature: Refresh
...
```

全体で 340 行。

### 修正箇所 (人間)

- Scenario 2.1 の「5 回目の成功時のカウンターリセット」が抜けていた → 追記
- Cookie の `Path=/` 指定を明示

### Phase 2 の所要: 15分

---

## Phase 3: threat.md 生成 (15分)

### 投入プロンプト

```
あなたは以下の functional.md を攻撃しようとしているペネトレーションテスターです。
threat.md を生成してください。

必須セクション:
1. Authorization Matrix
2. IDOR / Mass Assignment チェック
3. 認証仕様 (Cookie flags, レート制限, session 管理)
4. 検討済み脅威テーブル
5. 未解決事項

[functional.md を貼る]
```

### 生成された threat.md (抜粋)

```markdown
## Authorization Matrix

| 操作 | 未認証 | 認証済 (一般) | 管理者 |
|---|---|---|---|
| POST /login | ✅ | - | - |
| POST /logout | ❌ 401 | ✅ | ✅ |
| POST /refresh | ❌ 401 | ✅ | ✅ |
| GET /me | ❌ 401 | ✅ | ✅ |

## IDOR チェック

### POST /logout
- 現在の session を無効化するだけ
- query parameter `all=true` の場合、user_id の全 session を無効化
- 他ユーザーの session_id を指定してもアクセスできない (session_id は cookie 経由のみ)

### POST /refresh
- refresh token の owner_user_id が cookie session と一致することを DB で確認
- 不一致時: token 無効化 + 401

## Mass Assignment

### POST /login
- 入力: email, password
- 受け取ってはいけない: user_id, is_admin, roles, token_expires_at
- Pydantic extra: forbid

## 認証仕様

- JWT: access 15min, refresh 30days
- Cookie: httpOnly, SameSite=Lax, Secure (prod), Path=/
- Session regenerate: ログイン成功後に新 session_id 発行
- レート制限: アカウント単位、ログイン失敗 5 回 / 5 分でロック 15 分
- エラーメッセージ: "Invalid credentials" で統一 (ユーザー列挙防止)

## 検討済み脅威

| 脅威 | 対策 | 優先度 |
|---|---|---|
| Credential Stuffing | レート制限 + bcrypt (cost=12) | Critical |
| Session Fixation | ログイン後 session regenerate | Critical |
| XSS による token 窃取 | httpOnly Cookie | Critical |
| CSRF | SameSite=Lax | High |
| Refresh token 窃取 | Rotation (1回使ったら無効化) | High |
| ユーザー列挙 | エラーメッセージ統一 | High |
| Timing attack | constant-time compare (bcrypt) | Medium |

## 未解決

- 2FA: 次スプリント
- Device fingerprinting: 今回スコープ外
```

### 修正箇所

- 攻撃者 AI は「Refresh token を redis に入れるか DB に入れるか」を問わなかった → 人間が決定 (DB: rotation 監査のため)

### Phase 3 の所要: 15分

---

## Phase 4: resilience.md 生成 (10分)

### 投入プロンプト

```
この機能の resilience.md を生成してください。

必須カテゴリ:
1. 外部依存障害 (DB, Redis)
2. 内部エラー
3. リソース枯渇
4. データ破損

[functional.md + threat.md を貼る]
```

### 生成された resilience.md (抜粋)

```markdown
## 1. 外部依存障害

### PostgreSQL (認証 DB)
- Timeout: query 3s, transaction 10s
- 落ちた場合: 503 Service Unavailable
- Retry: deadlock のみ 1 回再試行

### Redis (session store)
- Timeout: 500ms
- 落ちた場合: session lookup は DB fallback
- Circuit Breaker: 10 req で 50% 失敗で 30s open

## 2. 内部エラー

### bcrypt 検証エラー
- 500 Internal Server Error
- Log: request_id + email_hash (email そのものは log せず)

### JWT デコードエラー
- 401 Unauthorized ("Invalid token")
- Log: request_id + token prefix のみ

## 3. リソース枯渇

### DB 接続プール枯渇
- 503
- アラート: > 80% で警告

### Rate limit storage 枯渇
- 429 を常に返す fail-safe
- アラート: ロックアウト状態が 10 分続く

## 4. データ破損

### Session inconsistency
- Redis と DB の session が不一致 → DB を source of truth
- Inconsistent 検出時は session 無効化

## 5. 監視項目

- login_duration_p99: < 500ms
- login_failure_rate: > 30% で警告
- redis_breaker_state: open 1分以上でアラート
```

### Phase 4 の所要: 10分

---

## Phase 5: plan.md 生成 (10分)

### 投入プロンプト

```
実装計画 plan.md を生成してください。
- 実装順序 (依存関係順)
- 各ステップの Out of Scope
- テスト戦略
```

### 生成された plan.md

```markdown
## 実装順序

1. **User Model** (app/models/user.py)
   - email (unique), password_hash, created_at, failed_login_count, lockout_until
   - Out of Scope: 2FA 関連フィールド

2. **SessionRepository** (app/repositories/session.py)
   - DB (PostgreSQL) 側: session table
   - Redis 側: session cache
   - Out of Scope: session device tracking

3. **AuthService** (app/services/auth.py)
   - login(email, password) → token pair
   - logout(session_id, all=False)
   - refresh(refresh_token) → new token pair
   - bcrypt verify, JWT 発行, rate limit check

4. **エンドポイント** (app/api/v1/auth.py)
   - POST /login
   - POST /logout  
   - POST /refresh

5. **レート制限 middleware** (app/middleware/rate_limit.py)
   - アカウント単位 (email)
   - threat.md の仕様準拠

6. **受け入れテスト** (tests/acceptance/test_auth.py)
   - 4 シナリオ: 成功, 失敗, ロック, refresh

## Out of Scope (今回やらないこと)

- 2FA
- Device fingerprinting
- 全デバイスログアウト以外の session 管理 (管理画面等)
- Password reset (別機能)

## テスト戦略

- 受け入れテスト: 4 シナリオ (機能全体)
- UC テスト: 14 ユースケース (1 UC 1 テスト)
- 統合テスト: bcrypt の実際の hash 検証
```

### Phase 5 の所要: 10分

---

## Phase 6: 受け入れテスト生成 (15分)

### 投入プロンプト

```
functional.md と threat.md に基づき、受け入れテスト (外側ループ) を pytest で生成してください。
Red 状態で構いません。
```

### 生成された tests/acceptance/test_auth.py (抜粋)

```python
import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_login_success(client: AsyncClient, seed_user):
    """Scenario 1.1: 成功ログイン"""
    response = await client.post("/login", json={
        "email": "user@example.com",
        "password": "CorrectPassword123!",
    })
    assert response.status_code == 200
    assert "access_token" in response.json()
    assert "refresh_token" in response.json()
    cookies = response.cookies
    assert cookies.get("session_id") is not None
    # session regenerate 確認
    assert cookies.get("session_id") != seed_user.session_id

@pytest.mark.asyncio
async def test_login_wrong_password(client: AsyncClient, seed_user):
    """Scenario 1.2: 不正なパスワード"""
    response = await client.post("/login", json={
        "email": "user@example.com",
        "password": "WrongPassword",
    })
    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid credentials"}

@pytest.mark.asyncio
async def test_account_lockout(client: AsyncClient, seed_user):
    """Scenario 2.1: 5 回失敗でロック"""
    for _ in range(5):
        await client.post("/login", json={"email": "user@example.com", "password": "wrong"})
    
    response = await client.post("/login", json={"email": "user@example.com", "password": "CorrectPassword123!"})
    assert response.status_code == 429
```

初回実行: 全て Red (実装がないので当然)。

### Phase 6 の所要: 15分

---

## Phase 7: UC TDD (60分)

Phase 7 は **各 UC を Red → Green → Refactor** で 1 つずつ実装していきます。Canon TDD の忠実な再現。

### UC 1: "Login success returns JWT" (8分)

**Red**: まず UC テスト

```python
def test_auth_service_login_success():
    service = AuthService(user_repo=FakeUserRepo([user]), jwt=FakeJWT())
    result = service.login("user@example.com", "password")
    assert result.access_token is not None
```

**Green**: 最小実装

```python
class AuthService:
    def __init__(self, user_repo, jwt):
        self.user_repo = user_repo
        self.jwt = jwt
    
    def login(self, email, password):
        user = self.user_repo.find_by_email(email)
        if not user or not verify_password(password, user.password_hash):
            raise InvalidCredentialsError()
        return TokenPair(
            access_token=self.jwt.create_access(user.id),
            refresh_token=self.jwt.create_refresh(user.id),
        )
```

**Refactor**: なし (最小実装で十分シンプル)

### UC 2〜14 (省略、各 3〜5 分)

- UC 2: Login with wrong password raises InvalidCredentialsError
- UC 3: Login with nonexistent email raises InvalidCredentialsError (same error)
- UC 4: Failed login increments counter
- UC 5: 5 failed logins triggers lockout
- UC 6: Successful login resets counter
- UC 7: Lockout expires after 15 minutes
- UC 8: Logout invalidates session
- UC 9: Logout with all=true invalidates all user sessions
- UC 10: Refresh returns new access token
- UC 11: Refresh rotates refresh token
- UC 12: Expired refresh token raises TokenExpiredError
- UC 13: Revoked refresh token raises TokenRevokedError
- UC 14: Rate limiter checks on POST /login

各 UC を 3〜5 分で Red → Green → Refactor。14 UC × 平均 4 分 = 56 分。

### 最後に受け入れテスト全部 Green

Phase 6 で書いた 4 つの acceptance test が全部 pass。これで外側ループも閉じる。

### Phase 7 の所要: 60分

---

## Phase 8: 静的解析ゲート (5分)

```bash
$ ruff check app/
All checks passed!

$ mypy app/ --strict
Success: no issues found in 8 source files

$ bandit -r app/ -ll
No issues identified.

$ pytest
============== 18 passed in 3.24s ==============
```

全て green。コミット OK。

### Phase 8 の所要: 5分

---

## 総括: 実行時間と成果物

### 時間配分 (実測)

| Phase | 所要 |
|---|---|
| 1. Example Mapping | 15分 |
| 2. functional.md | 15分 |
| 3. threat.md | 15分 |
| 4. resilience.md | 10分 |
| 5. plan.md | 10分 |
| 6. 受け入れテスト | 15分 |
| 7. UC TDD | 60分 |
| 8. 静的解析 | 5分 |
| **合計** | **2h 10m** |

### 成果物

- `docs/specs/auth/functional.md`: 340 行
- `docs/specs/auth/threat.md`: 180 行
- `docs/specs/auth/resilience.md`: 100 行
- `docs/specs/auth/plan.md`: 60 行 (計 680 行)
- `tests/acceptance/test_auth.py`: 4 本
- `tests/unit/test_auth_service.py`: 14 本
- `app/services/auth.py`: 180 行
- `app/api/v1/auth.py`: 90 行
- `app/middleware/rate_limit.py`: 60 行

### 人間の介入

各 Phase の **ゲート承認** のみ。AI の出力を読み、「OK」または「修正してほしい」を返すだけ。

- Phase 1: Questions の回答 (5問)
- Phase 2〜5: 生成ファイルのレビュー + 細かい修正 (1〜3箇所/Phase)
- Phase 7: UC ごとの Red テスト確認 → Green 実装レビュー

---

## 感想

### 良かった点

- **Phase 分割で頭が混乱しない**。「今は threat だけ考えればいい」が楽
- **仕様ファイルが 4 つに分かれている** ので、後から「これどこに書く?」で迷わない
- **UC TDD のリズムが気持ちいい**。小さく Red → Green → Refactor を 14 回回すと、実装が自然に保守しやすくなる
- **レビュー一発通過**。仕様 + テスト + 実装が揃っているので、レビュアーが疑問を持ちようがない

### 違和感・難しかった点

- Phase 3 (threat.md) は慣れるまで時間がかかった。攻撃者視点のプロンプトを書くのがコツ要る
- Phase 4 (resilience.md) は、プロジェクトごとに「どこまで書くか」の塩梅が違う。過剰に書くと肥大化
- Phase 7 の UC 14 個は、最初やると「本当にこんなに要る?」と思うが、**後から 1 個ずつ増やすより一気に書いた方が早い**

### 全体の印象

- 「Phase が 8 個もあるのは実務で回らない」は **杞憂だった**
- むしろ **Phase 分割があるから一周 2 時間で終わる**。一人で全体を頭に入れて書こうとしたら、もっと時間がかかる
- AI が各 Phase の出力を自動生成してくれるので、人間は **ゲート承認と判断** に集中できる

---

## まとめ

- SFAD cycle 8 Phase を認証機能で一周: 約 2 時間 10 分
- 成果物: 仕様 4 ファイル (680 行) + テスト 18 本 + 実装 3 endpoint
- 人間の介入は各 Phase のゲート承認のみ
- Phase 分割は **冗長に見えて実は速い**。頭が混乱しないため
- Canon TDD の UC TDD (Red → Green → Refactor × 14) が実装の質を底上げ
- レビュー一発通過の満足度は、一度体験すると戻れない
- B1 (4ファイル分割) / B2 (攻撃者視点) / B3 (13ルール) / B4 (Threat) / B5 (Resilience) が、この 8 Phase の中で統合される

「毎回 2 時間は重い」と感じる方へ ― **手戻り 1 件分のコストで仕様 + テスト + 実装が揃う** と考えれば、むしろ安い投資です。一度試してみてください。

---

## 次の記事: 既存コードから N+1 を仕様化する ― reverse 9タグ活用ガイド (6/11 公開予定)

ここまでの B1〜B7 は **新規開発** の文脈でした。次回は視点を変えて、**保守案件で仕様書のないコードを引き継いだとき** の話。sfad:reverse の 9タグを使って既存コードから仕様を逆抽出しつつ、特に [N+1 QUERY] タグで実案件を 1.2秒 → 80ms に高速化した記録を公開します。
