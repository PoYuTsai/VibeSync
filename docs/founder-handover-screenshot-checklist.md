# VibeSync 交接手冊截圖清單

Last updated: 2026-05-27

這份文件是給 Eric、Bruce、以及緊急接手者使用的「截圖採集清單」。照著這份逐張截圖，再用紅框標出重點，就能把 `docs/founder-handover-runbook.md` 變成一份真的看得懂、找得到入口、知道下一步怎麼做的交接手冊。

## 先講最重要的安全規則

可以放進 repo 的截圖，一定要先遮掉敏感資料。

截圖時可以保留：

- 網站名稱、專案名稱、App 名稱。
- 帳號擁有者名稱、角色、權限。
- key 的名稱、前幾碼、最後使用日期、用途。
- 信用卡品牌與末四碼。
- 銀行名稱、國家、幣別、狀態、帳號末四碼。
- DNS record 的 host/type/value。

截圖時必須遮掉：

- 完整 API key、secret key、service role key。
- 完整密碼、2FA QR code、recovery code。
- 完整信用卡號、CVV、完整銀行帳號。
- 身分證、護照、稅籍編號、完整住址。
- Apple / App Store Connect private key 內容。
- `.env`、`.p8`、憑證、私鑰。

建議把截圖分成兩份：

- repo-safe 截圖：已紅框、已遮敏，可放在 `docs/handover-screenshots/`。
- private 截圖：含銀行、稅務、帳密、付款細節，放密碼管理器或離線交接包，不要 commit。

建議命名：

```text
01-apple-app-overview.png
02-apple-ios-version-build.png
03-supabase-project-overview.png
```

## 截圖放哪裡

repo-safe 圖片建議放：

```text
docs/handover-screenshots/
```

貼到 Markdown 時使用：

```md
![Apple App Overview](handover-screenshots/01-apple-app-overview.png)
```

如果圖片含敏感資料，不要貼進 repo。只在手冊中寫：

```md
敏感截圖位置：密碼管理器 VibeSync / Apple Developer / Banking
```

## 最小必截清單

如果時間不多，先截這 13 張：

1. Apple App 版本與 build：確認目前送審版本。
2. Apple Agreements, Tax, and Banking：確認收款帳戶與稅表狀態。
3. Supabase Project Overview：確認正在用哪個 Supabase 專案。
4. Supabase Auth URL Configuration：確認 admin Google login callback。
5. Supabase Edge Functions：確認後端 Functions。
6. Supabase Edge Function Secrets：確認有哪些 secrets，但遮掉值。
7. Claude Billing Overview：確認 Claude billing、花費、信用額度。
8. Claude API Keys：確認 VibeSync 使用哪把 key。
9. RevenueCat Entitlements：確認付費權限設定。
10. RevenueCat Offerings / Packages：確認四個訂閱方案。
11. RevenueCat Webhook：確認 RevenueCat 到 Supabase webhook。
12. Vercel Admin Dashboard Domains：確認 `admin.vibesyncai.app`。
13. Namecheap Advanced DNS：確認 `admin` CNAME 與官網 DNS。

## 1. Apple Developer / App Store Connect

網站：

```text
https://appstoreconnect.apple.com/
```

### 01 Apple App 總覽

路徑：

```text
App Store Connect > Apps > VibeSync
```

截圖要看到：

- VibeSync app icon 與 app name。
- 上方分頁：Distribution、Analytics、TestFlight、Xcode Cloud。
- 如果畫面上看得到 Bundle ID，也一起保留。

紅框標：

- `VibeSync` app 名稱。
- `Distribution`。
- `TestFlight`。

檔名：

```text
01-apple-app-overview.png
```

### 02 iOS 版本與送審 Build

路徑：

```text
Distribution > iOS App > 版本頁
```

截圖要看到：

- 目前版本，例如 `1.0`。
- 目前 build，例如 `1.0 (211)`。
- Review status / submission status。
- Submit / Resubmit / Update Review button 附近。

紅框標：

- build number。
- review status。
- 送審按鈕區。

檔名：

```text
02-apple-ios-version-build.png
```

### 03 App Review 訊息

路徑：

```text
Distribution > App Review / Resolution Center / iOS Submission Messages
```

截圖要看到：

- Apple rejection 或 review message。
- Eric 回覆 Apple 的訊息。
- 如果有附件或 screenshot，也截到檔名。

紅框標：

- Apple 指出的 guideline。
- Eric 的 reply。
- `Reply to App Review` 或 `Update Review` 入口。

遮掉：

- 私人聯絡資訊。

檔名：

```text
03-apple-review-messages.png
```

### 04 In-App Purchase / Subscription 商品

路徑：

```text
Distribution > Monetization > Subscriptions
```

截圖要看到：

- Subscription group。
- Starter 月繳。
- Starter 季繳。
- Essential 月繳。
- Essential 季繳。

紅框標：

- product ID。
- price。
- status。

檔名：

```text
04-apple-iap-products.png
```

### 05 Agreements, Tax, and Banking

路徑：

```text
Business > Agreements, Tax, and Banking
```

截圖要看到：

- Paid Apps Agreement status。
- Bank Accounts。
- Tax Forms。

紅框標：

- 目前 Active 的收款帳戶。
- Bank country / region。
- Bank currency。
- Royalty currencies。
- Status。

遮掉：

- 完整銀行帳號。
- 完整稅籍資料。
- 不必要的住址。

檔名：

```text
05-apple-agreements-tax-banking.png
```

### 06 Users and Access

路徑：

```text
Users and Access
```

截圖要看到：

- Eric。
- Bruce，如果已加入。
- 每個人的 role。
- App Store Connect API key 區域，如果有用到 CI 自動上傳。

紅框標：

- Eric / Bruce 權限。
- API key 名稱與權限。

遮掉：

- private key 內容。

檔名：

```text
06-apple-users-access.png
```

## 2. Supabase

網站：

```text
https://supabase.com/dashboard/project/fcmwrmwdoqiqdnbisdpg
```

### 07 Supabase 專案總覽

路徑：

```text
Supabase Dashboard > vibesync-sandbox
```

截圖要看到：

- project name：`vibesync-sandbox`。
- project ref：`fcmwrmwdoqiqdnbisdpg`。
- organization。

紅框標：

- project selector。
- project ref。

檔名：

```text
07-supabase-project-overview.png
```

### 08 Auth Users

路徑：

```text
Authentication > Users
```

截圖要看到：

- Eric admin user。
- Bruce admin user。
- provider type，例如 Google / Apple / Email。
- created at。

紅框標：

- Eric email。
- Bruce email。
- Provider type。

遮掉：

- User UID 可遮可不遮；如果要公開給家人看，建議遮掉。

檔名：

```text
08-supabase-auth-users.png
```

### 09 Auth URL Configuration

路徑：

```text
Authentication > URL Configuration
```

截圖要看到：

- Site URL。
- Redirect URLs。

紅框標：

- `https://admin.vibesyncai.app/auth/callback`
- `https://admin-dashboard-olive-phi-634niau2ml.vercel.app/auth/callback`
- iOS app deep link callback，如果有。

檔名：

```text
09-supabase-auth-url-config.png
```

### 10 Edge Functions

路徑：

```text
Edge Functions
```

截圖要看到：

- function list。
- deploy status。
- last deployed。

紅框標：

- `analyze-chat`
- `coach-chat`
- `coach-follow-up`
- `sync-subscription`
- `revenuecat-webhook`
- `delete-account`

檔名：

```text
10-supabase-edge-functions.png
```

### 11 Edge Function Secrets

路徑：

```text
Project Settings > Edge Functions > Secrets
```

截圖要看到：

- secret names。
- updated date。

紅框標：

- `CLAUDE_API_KEY`
- `REVENUECAT_IOS_API_KEY`
- `REVENUECAT_WEBHOOK_SECRET`
- `SUPABASE_SERVICE_ROLE_KEY`

遮掉：

- 所有 secret value。

檔名：

```text
11-supabase-edge-secrets.png
```

### 12 Database Table List

路徑：

```text
Table Editor
```

截圖要看到：

- 重要 table 列表。

紅框標：

- `admin_users`
- `subscriptions`
- `revenue_events`
- `token_usage`
- `monthly_revenue`
- `monthly_profit`
- `finance_entries`
- `finance_settlements`
- `admin_articles`

檔名：

```text
12-supabase-table-list.png
```

### 13 admin_users 白名單

路徑：

```text
Table Editor > admin_users
```

截圖要看到：

- Eric row。
- Bruce row。
- active / role 欄位，如果存在。

紅框標：

- email。
- role / active status。

檔名：

```text
13-supabase-admin-users.png
```

## 3. Anthropic Claude Console

網站：

```text
https://console.anthropic.com/
```

### 14 Claude Organization

路徑：

```text
Organization settings > Organization
```

截圖要看到：

- organization name。
- Eric account。
- Eric role。
- 如果 Bruce 加入，也截 Bruce role。

紅框標：

- organization name。
- Eric role。
- Bruce role，如果有。

檔名：

```text
14-claude-organization.png
```

### 15 Claude Billing

路徑：

```text
Organization settings > Billing
```

截圖要看到：

- Credit balance。
- Auto reload on/off。
- Current monthly spend。
- Monthly spend limit。
- Invoice history。
- Payment method 的品牌與末四碼，如果可見。

紅框標：

- credit balance。
- 本月已用金額。
- monthly spend limit。
- auto reload。
- invoice history。

遮掉：

- 完整卡號。
- billing address。

檔名：

```text
15-claude-billing-overview.png
```

### 16 Claude API Keys

路徑：

```text
Organization settings > API keys
```

截圖要看到：

- key name，例如 `vibesync-sandbox`。
- workspace。
- created by。
- created at。
- last used at。
- cost。

紅框標：

- `vibesync-sandbox`。
- last used at。
- cost。

遮掉：

- 完整 API key。Console 顯示的短 prefix 通常可以保留。

檔名：

```text
16-claude-api-keys.png
```

### 17 Claude Limits

路徑：

```text
Organization settings > Limits
```

截圖要看到：

- rate limit。
- spend limit。
- model availability。

紅框標：

- monthly spend limit。
- 任何會影響 production 的 limit。

檔名：

```text
17-claude-limits.png
```

## 4. RevenueCat

網站：

```text
https://app.revenuecat.com/
```

### 18 RevenueCat Project Overview

路徑：

```text
RevenueCat > VibeSync project
```

截圖要看到：

- project name。
- iOS app。
- app bundle ID，如果可見。

紅框標：

- VibeSync project。
- iOS app。

檔名：

```text
18-revenuecat-project-overview.png
```

### 19 RevenueCat API Keys

路徑：

```text
Project settings > API keys
```

截圖要看到：

- public app SDK key。
- server / secret key name。

紅框標：

- iOS public SDK key prefix，例如 `appl_...`。
- server key name。

遮掉：

- 完整 secret key。

檔名：

```text
19-revenuecat-api-keys.png
```

### 20 Entitlements

路徑：

```text
Entitlements
```

截圖要看到：

- entitlement name。
- linked products。

紅框標：

- `premium` 或實際 entitlement 名稱。
- 四個 subscription products。

檔名：

```text
20-revenuecat-entitlements.png
```

### 21 Offerings / Packages

路徑：

```text
Offerings
```

截圖要看到：

- current offering。
- packages。

紅框標：

- current offering。
- Starter 月繳 / 季繳。
- Essential 月繳 / 季繳。

檔名：

```text
21-revenuecat-offerings.png
```

### 22 Products

路徑：

```text
Products
```

截圖要看到：

- product list。
- store status。

紅框標：

- Starter monthly product。
- Starter quarterly product。
- Essential monthly product。
- Essential quarterly product。

檔名：

```text
22-revenuecat-products.png
```

### 23 RevenueCat Webhook

路徑：

```text
Integrations > Webhooks
```

截圖要看到：

- webhook URL。
- authorization / secret status。
- recent delivery status，如果有。

紅框標：

- Supabase `revenuecat-webhook` URL。
- delivery status。

遮掉：

- webhook secret。

檔名：

```text
23-revenuecat-webhook.png
```

## 5. Vercel Admin Dashboard

網站：

```text
https://vercel.com/
```

### 24 Vercel Project Overview

路徑：

```text
Vercel > admin-dashboard > Overview
```

截圖要看到：

- project name：`admin-dashboard`。
- production deployment。
- connected GitHub repo。

紅框標：

- `admin-dashboard`。
- production domain。
- GitHub repo：`PoYuTsai/VibeSync`。

檔名：

```text
24-vercel-admin-project-overview.png
```

### 25 Build and Deployment

路徑：

```text
Project Settings > Build and Deployment
```

截圖要看到：

- Framework Preset。
- Build Command。
- Install Command。
- Root Directory。
- Node.js version。

紅框標：

- `Next.js`。
- `npm run build`。
- `npm install`。
- `admin-dashboard`。

檔名：

```text
25-vercel-build-settings.png
```

### 26 Environment Variables

路徑：

```text
Project Settings > Environment Variables
```

截圖要看到：

- env var names。
- scope：Production / Preview。

紅框標：

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

遮掉：

- env var values。

檔名：

```text
26-vercel-env-vars.png
```

### 27 Domains

路徑：

```text
Project Settings > Domains
```

截圖要看到：

- `admin.vibesyncai.app`。
- fallback vercel.app URL。
- valid configuration。

紅框標：

- `admin.vibesyncai.app`。
- `Valid Configuration`。

檔名：

```text
27-vercel-domains.png
```

### 28 Deployments

路徑：

```text
Deployments
```

截圖要看到：

- latest production deployment。
- status。
- commit hash。

紅框標：

- latest production。
- status。
- commit。

檔名：

```text
28-vercel-deployments.png
```

## 6. GitHub

### 29 Main App Repo

網站：

```text
https://github.com/PoYuTsai/VibeSync
```

截圖要看到：

- repo name。
- branch。
- latest commit。

紅框標：

- `PoYuTsai/VibeSync`。
- `main`。
- latest commit。

檔名：

```text
29-github-main-repo.png
```

### 30 GitHub Actions Secrets

路徑：

```text
Settings > Secrets and variables > Actions
```

截圖要看到：

- secret names。
- updated date。

紅框標：

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROD_URL`
- `SUPABASE_PROD_ANON_KEY`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY`

遮掉：

- GitHub normally hides secret values. Do not reveal them.

檔名：

```text
30-github-actions-secrets.png
```

### 31 GitHub Collaborators

路徑：

```text
Settings > Collaborators
```

截圖要看到：

- Bruce collaborator access。
- Eric owner access。

紅框標：

- collaborator name。
- permission level。

檔名：

```text
31-github-main-collaborators.png
```

### 32 Official Website Repo

網站：

```text
https://github.com/chiang53610-droid/vibesync-web
```

截圖要看到：

- repo owner。
- repo name。
- GitHub Pages status，如果可見。

紅框標：

- `chiang53610-droid/vibesync-web`。
- GitHub Pages / deployment 設定。

檔名：

```text
32-github-website-repo.png
```

## 7. Namecheap DNS

網站：

```text
https://www.namecheap.com/
```

### 33 Domain List

路徑：

```text
Domain List
```

截圖要看到：

- `vibesyncai.app`。
- expiration date。
- auto-renew status。

紅框標：

- domain name。
- 到期日。
- auto-renew。

遮掉：

- billing/payment details。

檔名：

```text
33-namecheap-domain-list.png
```

### 34 Advanced DNS

路徑：

```text
Domain List > vibesyncai.app > Manage > Advanced DNS
```

截圖要看到：

- host records。

紅框標：

- `admin` CNAME。
- root / `@` record。
- `www` record。
- GitHub Pages 或 Vercel 相關 records。

檔名：

```text
34-namecheap-advanced-dns.png
```

## 8. VibeSync Admin Dashboard

網站：

```text
https://admin.vibesyncai.app/login
```

### 35 Admin Login

截圖要看到：

- login page。
- Google login button。

紅框標：

- Google login button。

檔名：

```text
35-admin-login.png
```

### 36 Admin Overview

路徑：

```text
https://admin.vibesyncai.app/
```

截圖要看到：

- main dashboard。
- official website link block。
- key metrics。

紅框標：

- 左側導覽。
- VibeSync 官方展示頁入口。
- key metrics。

檔名：

```text
36-admin-overview.png
```

### 37 Admin Users

路徑：

```text
https://admin.vibesyncai.app/users
```

截圖要看到：

- user table。
- tier / subscription status。
- user segment。
- registration date。

紅框標：

- plan。
- status。
- user segment。

遮掉：

- 不想公開的使用者 email。

檔名：

```text
37-admin-users.png
```

### 38 Finance Dashboard

路徑：

```text
https://admin.vibesyncai.app/finance
```

截圖要看到：

- income。
- cost。
- split mode。
- payer。
- exchange rate / TWD amount。
- settlement status。

紅框標：

- 本月收入。
- 成本。
- 分潤模式。
- 誰支付。
- 匯率欄位。
- 儲存月結設定。

檔名：

```text
38-admin-finance.png
```

### 39 Articles

路徑：

```text
https://admin.vibesyncai.app/articles
```

截圖要看到：

- 已上架文章。
- 待上架文章。
- 分類與標籤。
- upload / paste content area。

紅框標：

- 新增文章入口。
- status。
- category / tags。

檔名：

```text
39-admin-articles.png
```

## 9. Local Machine / Developer Setup

### 40 Local Project Folder

路徑：

```text
C:\Users\eric1\OneDrive\Desktop\VibeSync
```

截圖要看到：

- `lib/`
- `supabase/`
- `admin-dashboard/`
- `docs/`

紅框標：

- 以上四個資料夾。

遮掉：

- `.env` 檔案內容。
- private key 或 certificate。

檔名：

```text
40-local-project-folder.png
```

### 41 Git Status / Latest Commit

指令：

```bash
git status
git log --oneline -5
```

截圖要看到：

- current branch。
- working tree 是否乾淨。
- latest commits。

紅框標：

- branch。
- latest commit。

檔名：

```text
41-local-git-status.png
```

## 貼到交接手冊的建議格式

每一張圖可以用這種格式放入手冊：

```md
### Apple 收款與稅務設定

用途：確認 App Store proceeds 會匯到哪個帳戶，以及 Paid Apps Agreement / Tax Forms 是否正常。

![Apple Agreements Tax Banking](handover-screenshots/05-apple-agreements-tax-banking.png)

接手者要看：

- Bank Accounts 是否 Active。
- Tax Forms 是否 Active。
- 若要更換收款帳戶，先確認 Apple 帳戶與法務/稅務規則。
```

## 截圖完成後的檢查

每張圖進 repo 前，確認：

- 沒有完整 key。
- 沒有完整信用卡、銀行帳號、身分證、護照、稅號。
- 沒有 2FA QR code 或 recovery code。
- 紅框有標出接手者要找的地方。
- 檔名符合清單。
- 手冊中的圖片路徑能正常顯示。
