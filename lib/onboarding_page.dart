import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_key_page.dart';
import 'transitions.dart';
import 'package:url_launcher/url_launcher.dart';

class OnboardingPage extends StatefulWidget {
  final int startPage;
  const OnboardingPage({super.key, this.startPage = 0});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late final PageController _controller;
  int _currentPage = 0;

  final List<OnboardingStep> _steps = [
    OnboardingStep(
      emoji: '👋',
      title: '歡迎使用會議筆記',
      description:
          '這個 App 可以幫你錄音，並用 AI 自動整理成結構化的筆記。\n\n在開始之前，你需要申請一個免費的 Gemini API Key。',
    ),
    // --- 8 頁圖片教學 ---
    OnboardingStep(
      title: '第一步',
      description: '進到 aistudio.google.com，點擊左上角的選單',
      imageAsset: 'assets/images/step1.png',
      highlightText: 'aistudio.google.com',
      highlightUrl: 'https://aistudio.google.com',
    ),
    OnboardingStep(
      title: '第二步',
      description: '點擊左下角的 "Get API key"',
      imageAsset: 'assets/images/step2.png',
    ),
    OnboardingStep(
      title: '第三步',
      description: '點擊右上角的 "Create API key"',
      imageAsset: 'assets/images/step3.png',
    ),
    OnboardingStep(
      title: '第四步',
      description: '創建一個 project',
      imageAsset: 'assets/images/step4.png',
    ),
    OnboardingStep(
      title: '第五步',
      description: '點擊 "Create project"',
      imageAsset: 'assets/images/step5.png',
    ),
    OnboardingStep(
      title: '第六步',
      description: '點擊 "Create key"',
      imageAsset: 'assets/images/step6.png',
    ),
    OnboardingStep(
      title: '第七步',
      description: '點擊剛剛創建好的 key',
      imageAsset: 'assets/images/step7.png',
    ),
    OnboardingStep(
      title: '第八步',
      description: '點擊 "Copy key" 就完成了！',
      imageAsset: 'assets/images/step8.png',
    ),
    // --- 圖片教學結束 ---
    OnboardingStep(
      emoji: '💰',
      title: '費用說明',
      description:
          'Gemini API 對個人開發者提供免費額度：\n\n• 每天最多 1,500 次請求\n• 完全免費，不需要綁定信用卡\n\n一般學生日常使用完全足夠！',
    ),
    OnboardingStep(
      emoji: '📱',
      title: '加到主畫面（iOS）',
      description:
          '如果你是 iPhone 用戶：\n1. 用 Safari 開啟本 App 的網址\n2. 點底部的「分享」按鈕 □↑\n3. 向下滑找到「加入主畫面」\n4. 點「新增」\n之後就可以像一般 App 一樣從主畫面開啟！\n\n注意：ios用戶無法在背景執行本服務，可以選擇上傳音檔來獲得較好的體驗',
    ),
    OnboardingStep(
      emoji: '🤖',
      title: '加到主畫面（Android）',
      description:
          '如果你是 Android 用戶：\n方法一（建議）：\n直接安裝 APK 檔案\n\n方法二（網頁版）：\n1. 用 Chrome 開啟本 App 網址\n2. 點右上角選單「⋮」\n3. 選「新增至主畫面」\n4. 點「新增」',
    ),
    OnboardingStep(
      emoji: '✅',
      title: '準備完成！',
      description:
          '把剛才複製的 API Key 貼進下一個畫面的輸入框，就可以開始使用了。\n\n日後可以在主畫面右上角的設定圖示重新更換 Key。',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.startPage);
    _currentPage = widget.startPage;
  }

  void _skipOrFinish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) {
      Navigator.pushReplacement(context, FadeRoute(page: ApiKeyPage()));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _skipOrFinish,
            child: const Text(
              'SKIP',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _steps.length,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) {
                final step = _steps[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 有圖片時顯示圖片，否則顯示 emoji
                      if (step.imageAsset != null) ...[
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height *
                                0.55, // 限制圖片最多佔螢幕高度的 40%
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              step.imageAsset!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else if (step.emoji != null) ...[
                        Text(step.emoji!, style: const TextStyle(fontSize: 80)),
                        const SizedBox(height: 32),
                      ],
                      Text(
                        step.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        step.description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.7,
                          color: Colors.black87,
                        ),
                      ),
                      if (step.highlightText != null) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: step.highlightUrl != null
                              ? () async {
                                  final uri = Uri.parse(step.highlightUrl!);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                }
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.indigo.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  step.highlightText!,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                if (step.highlightUrl != null) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.open_in_new,
                                    size: 16,
                                    color: Colors.indigo,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _steps.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == index ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? Colors.indigo
                            : Colors.indigo.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    if (_currentPage > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _controller.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '上一頁',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    if (_currentPage > 0) const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_currentPage < _steps.length - 1) {
                            _controller.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          } else {
                            _skipOrFinish();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _currentPage < _steps.length - 1 ? '下一步' : '開始使用',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingStep {
  final String? emoji;
  final String title;
  final String description;
  final String? highlightText;
  final String? highlightUrl;
  final String? imageAsset;

  const OnboardingStep({
    this.emoji,
    required this.title,
    required this.description,
    this.highlightText,
    this.highlightUrl,
    this.imageAsset,
  });
}
