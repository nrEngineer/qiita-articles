#!/bin/bash
# Qiita 予約投稿スクリプト
# schedule.json を読み、今日が publish_date の記事を公開する

set -euo pipefail

TODAY=$(date +%Y-%m-%d)
echo "📅 Today: $TODAY"

PUBLISHED=0

# schedule.json から今日公開すべき記事を取得
ARTICLES=$(cat schedule.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
today = '$TODAY'
for a in data['articles']:
    if a['publish_date'] == today:
        print(a['file'])
" 2>/dev/null || cat schedule.json | node -e "
const data = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
const today = '$TODAY';
data.articles.filter(a => a.publish_date === today).forEach(a => console.log(a.file));
")

if [ -z "$ARTICLES" ]; then
    echo "📭 No articles scheduled for today."
    exit 0
fi

for FILE in $ARTICLES; do
    FILEPATH="public/$FILE"

    if [ ! -f "$FILEPATH" ]; then
        echo "⚠️  File not found: $FILEPATH"
        continue
    fi

    echo "🚀 Publishing: $FILE"

    # private: true → private: false
    sed -i 's/^private: true$/private: false/' "$FILEPATH"

    # Qiita CLI で公開
    BASENAME="${FILE%.md}"
    npx qiita publish "$BASENAME"

    echo "✅ Published: $FILE"
    PUBLISHED=$((PUBLISHED + 1))
done

echo ""
echo "📊 Result: $PUBLISHED article(s) published."

# 変更をコミット（GitHub Actions 内で使用）
if [ "$PUBLISHED" -gt 0 ] && [ -n "${GITHUB_ACTIONS:-}" ]; then
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add -A
    git commit -m "📝 Auto-publish: $TODAY ($PUBLISHED article(s))" || true
    git push
fi
