# Meeting_Notes 📝

一款支援長時錄音、自動摘要與 AI 分析的會議筆記工具。

🔗 **快速連結**：
*   🌐 [直接使用 Web 版 (GitHub Pages)](https://sean11231123.github.io/Meeting_Notes/)(無法在背景執行)
*   📦 [下載 Android APK (最新版本)](https://github.com/Sean11231123/Meeting_Notes/releases/latest)[README.md](https://github.com/user-attachments/files/26535757/README.md)

## ✨ 功能特色

- 🎙️ **錄製音訊** — 直接在應用程式內錄音，或上傳現有音訊檔案
- 🧠 **AI 智慧摘要** — 由 Google Gemini 2.5 Flash 驅動
- 📋 **多種模板** — 選擇最符合你會議類型的結構
- 📄 **多格式匯出** — 支援 Markdown、TXT、HTML（相容 Word）、PDF
- 🌐 **跨平台支援** — Android APK 及 iOS／PC 漸進式網頁應用程式（PWA）
- 🔑 **自備 API 金鑰** — 你的資料只在你與 Google 之間流通

---

## 🚀 開始使用

### Android

1. 從 [Releases](https://github.com/Sean11231123/Meeting_Notes/releases) 下載最新 APK
2. 在裝置上開啟「允許安裝未知來源應用程式」
3. 安裝並開啟應用程式
4. 首次啟動時輸入你的 [Gemini API 金鑰](https://aistudio.google.com/app/apikey)

### iOS / PC（PWA）

1. 以瀏覽器開啟 [https://sean11231123.github.io/Meeting_Notes](https://sean11231123.github.io/Meeting_Notes)
2. **iOS Safari**：點選分享按鈕 → 「加入主畫面」
3. **PC Chrome**：點選網址列右側的安裝圖示
4. 依提示輸入你的 Gemini API 金鑰

---

## 🔑 API 金鑰設定

本應用程式使用 [Google Gemini API](https://ai.google.dev)，你需要一組免費的 API 金鑰：

1. 前往 [Google AI Studio](https://aistudio.google.com/app/apikey)
2. 點選 **建立 API 金鑰**
3. 將金鑰貼入應用程式的設定頁面

你的 API 金鑰會安全地儲存在裝置本機，不會對外傳送。

---

## 🛠️ 開發環境設定

### 前置需求

- [Flutter SDK](https://docs.flutter.dev/get-started/install)（3.x）
- Android Studio 或 VS Code（含 Flutter 擴充套件）
- 用於測試的 Gemini API 金鑰

### 本機執行

```bash
git clone https://github.com/Sean11231123/Meeting_Notes.git
cd Meeting_Notes
flutter pub get

# Android
flutter run

# Web（PWA）
flutter run -d chrome
```

### 建置

```bash
# Android APK
flutter build apk --release

# Web
flutter build web --release
```

---

## 📦 技術架構

| 層級 | 技術 |
|---|---|
| 框架 | Flutter (Dart) |
| AI 模型 | Gemini 2.5 Flash (`gemini-2.5-flash`) |
| 檔案 API | Gemini File API（超過 20 MB 自動切換） |
| CORS Proxy | Cloudflare Worker |
| 託管服務 | GitHub Pages |
| CI/CD | GitHub Actions |
| 金鑰儲存 | `flutter_secure_storage`（Android）／`SharedPreferences`（Web） |

### 主要套件

- `record` — 應用程式內錄音
- `file_picker` — 音訊檔案上傳
- `google_generative_ai` — Gemini API 客戶端
- `pdf` + `printing` — PDF 匯出（支援中日韓字體）
- `share_plus` — 原生分享功能
- `flutter_markdown_plus` — Markdown 渲染
- `table_calendar` — 筆記歷史日曆視圖

---

## 📁 專案結構

```
lib/
├── main.dart
├── screens/          # 各頁面 UI（首頁、錄音、結果、設定…）
├── services/         # Gemini API、檔案上傳、金鑰儲存
├── models/           # 資料模型
├── widgets/          # 可重用 UI 元件
└── utils/            # 工具函式（下載、MIME 類型、平台判斷）
```

---

## 🐛 已知限制

- **Android**：麥克風具排他性 — 無法同時錄製其他應用程式（如 Google Meet）的系統音訊，請改為上傳音訊檔案。
- **PC Web**：可擷取麥克風輸入，但無法錄製視訊通話的遠端音訊。
- **iOS Safari**：檔案選擇器使用 `FileType.any` 以允許選取音訊（Safari 平台限制）。

---

## 📝 授權

本專案供個人與學習用途使用，歡迎 Fork 並依需求修改。

---

## 🙏 致謝

本專案的製作使用了 Claude 以及 Gemini 生成的程式碼。

由 [Flutter](https://flutter.dev) 建構，並由 [Google Gemini](https://ai.google.dev) 提供 AI 能力。
