#!/bin/bash
# VibeSync Supabase 沙盒測試設定腳本
# Usage: ./scripts/setup-supabase.sh

set -e

echo "🚀 VibeSync Supabase 設定腳本"
echo "========================================="
echo ""

# Check if supabase CLI is installed
if ! command -v supabase &> /dev/null && ! npx supabase --version &> /dev/null; then
    echo "❌ Supabase CLI 未安裝"
    echo "   安裝方式: npm install -g supabase"
    exit 1
fi

echo "✅ Supabase CLI 已安裝"
echo ""

# Check if we're linked to a project
if [ ! -f "supabase/.temp/project-ref" ]; then
    echo "📋 請先完成以下步驟："
    echo ""
    echo "1. 前往 https://supabase.com 建立新專案"
    echo "2. 執行: supabase login"
    echo "3. 執行: supabase link --project-ref YOUR_PROJECT_REF"
    echo ""
    echo "   (Project ref 可從 Supabase Dashboard URL 取得)"
    echo "   例如: https://supabase.com/dashboard/project/abcdefghijkl"
    echo "   Project ref 就是 'abcdefghijkl'"
    echo ""
    read -p "是否已完成連結？(y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "📦 推送資料庫 schema..."
supabase db push

echo ""
echo "🔧 部署 Edge Function..."
supabase functions deploy analyze-chat

echo ""
echo "🔑 設定 Claude API Key..."
echo "   請到 Supabase Dashboard > Project Settings > Edge Functions"
echo "   新增 Secret: CLAUDE_API_KEY = your-claude-api-key"
echo ""
read -p "是否已設定 CLAUDE_API_KEY? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "✅ 設定完成！"
    echo ""
    echo "========================================="
    echo "📋 下一步：更新 Flutter 環境變數"
    echo "========================================="
    echo ""
    echo "執行以下命令啟動 staging 環境："
    echo ""
    echo "  flutter run -d chrome \\"
    echo "    --dart-define=ENV=staging \\"
    echo "    --dart-define=SUPABASE_STAGING_URL=https://YOUR_PROJECT.supabase.co \\"
    echo "    --dart-define=SUPABASE_STAGING_ANON_KEY=your-anon-key"
    echo ""
else
    echo ""
    echo "⚠️  請設定 CLAUDE_API_KEY 後再繼續"
fi
