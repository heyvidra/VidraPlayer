import 'package:flutter/material.dart';
import 'package:vidra_player/vidra_player.dart';
import 'package:vidra_player_kit/vidra_player_kit.dart';

// 创建视频元数据
final video = VideoMetadata(
  id: '12345',
  title: '示例视频',
  coverUrl:
      'https://olevod.com/upload/vod/20251222-1/31bb85702f7131dbe6a503b7656a871d.jpg',
);

// 创建剧集列表
final episodes = [
  VideoEpisode(
    index: 0,
    title: '第一集',
    qualities: [
      VideoQuality(
        label: '480p',
        source: VideoSource.network(
          'https://europe.olemovienews.com/ts4/20251222/QcUU3Azl/mp4/QcUU3Azl.mp4/master.m3u8',
        ),
      ),
    ],
  ),
  VideoEpisode(
    index: 1,
    title: '第二集',
    qualities: [
      VideoQuality(
        label: '720p',
        source: VideoSource.network(
          'https://europe.olemovienews.com/ts4/20251222/QcUU3Azl/mp4/QcUU3Azl.mp4/master.m3u8',
        ),
      ),
    ],
  ),
  VideoEpisode(
    index: 2,
    title: '第三集',
    qualities: [
      VideoQuality(
        label: '720p',
        source: VideoSource.network(
          'https://europe.olemovienews.com/ts4/20251222/QcUU3Azl/mp4/QcUU3Azl.mp4/master.m3u8',
        ),
      ),
    ],
  ),
  VideoEpisode(
    index: 3,
    title: '第四集',
    qualities: [
      VideoQuality(
        label: '720p',
        source: VideoSource.network(
          'https://europe.olemovienews.com/ts4/20251222/QcUU3Azl/mp4/QcUU3Azl.mp4/master.m3u8',
        ),
      ),
    ],
  ),
  VideoEpisode(
    index: 4,
    title: '第五集',
    qualities: [
      VideoQuality(
        label: '720p',
        source: VideoSource.network(
          'https://europe.olemovienews.com/ts4/20251222/QcUU3Azl/mp4/QcUU3Azl.mp4/master.m3u8',
        ),
      ),
    ],
    badge: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B00),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        "新",
        style: TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  ),
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  VidraPlayerKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Player SDK',
      theme: ThemeData.dark(),
      home: const VideoPlayerExample(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VideoPlayerExample extends StatefulWidget {
  const VideoPlayerExample({super.key});

  @override
  State<VideoPlayerExample> createState() => _VideoPlayerExampleState();
}

class _VideoPlayerExampleState extends State<VideoPlayerExample> {
  late PlayerController _controller;

  // Currently selected theme
  PlayerUITheme _currentTheme = const PlayerUITheme.cinema();
  String _currentThemeName = 'Cinema';

  // Currently selected language
  VidraLocale _currentLocale = VidraLocale.zhCN;
  String _currentLocaleName = '简体中文';

  // Whether to show the settings panel
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _controller = PlayerController(
      config: PlayerConfig(
        initialEpisodeIndex: 0,
        episodesSort: false,
        theme: _currentTheme,
        locale: _currentLocale,
        features: const PlayerFeatures.all(),
        behavior: PlayerBehavior(
          autoHideDelay: const Duration(seconds: 3),
          mouseHideDelay: const Duration(seconds: 2),
          hoverShowDelay: const Duration(milliseconds: 300),
          autoPlay: true,
          hideMouseWhenIdle: true,
          muteOnStart: false,
        ),
        leading: IconButton(
          padding: EdgeInsets.zero, // 移除内边距
          constraints: BoxConstraints(),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.settings),
          tooltip: 'Theme and Language Settings',
          onPressed: () {
            setState(() {
              _showSettings = !_showSettings;
            });
          },
        ),
      ),
      video: video,
      episodes: episodes,
      windowDelegate: const StandardWindowDelegate(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ViewModeState>(
      stream: _controller.viewStream,
      initialData: _controller.view,
      builder: (context, snapshot) {
        final viewState = snapshot.data ?? _controller.view;

        if (viewState.isFullscreen) {
          // In fullscreen, show ONLY the player to avoid any layout constraints
          return Scaffold(
            backgroundColor: Colors.black,
            body: VideoPlayerWidget(controller: _controller),
          );
        }

        // Standard layout
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 300,
                  child: Stack(
                    children: [
                      VideoPlayerWidget(controller: _controller),
                      if (_showSettings)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: _buildSettingsPanel(),
                        ),
                    ],
                  ),
                ),
                const Expanded(
                  child: Center(child: Text('Extra Content Area')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _currentTheme.primaryColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '主题和语言设置',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _currentTheme.primaryColor,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    _showSettings = false;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 主题选择
          const Text(
            '主题:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildThemeChip('Dark', const PlayerUITheme.dark()),
              _buildThemeChip('Light', const PlayerUITheme.light()),
              _buildThemeChip('Netflix', const PlayerUITheme.netflix()),
              _buildThemeChip('Cinema', const PlayerUITheme.cinema()),
              _buildThemeChip('Minimal', const PlayerUITheme.minimal()),
              _buildThemeChip('YouTube', const PlayerUITheme.youtube()),
            ],
          ),
          const SizedBox(height: 16),

          // 语言选择
          const Text(
            '语言:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildLocaleChip('English', VidraLocale.en),
              _buildLocaleChip('简体中文', VidraLocale.zhCN),
              _buildLocaleChip('繁體中文', VidraLocale.zhTW),
            ],
          ),
          const SizedBox(height: 12),

          // 当前配置
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '当前: $_currentThemeName + $_currentLocaleName',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeChip(String name, PlayerUITheme theme) {
    final isSelected = _currentThemeName == name;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentThemeName = name;
          _currentTheme = theme;
        });
        _controller.setTheme(theme);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primaryColor.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.primaryColor
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? theme.primaryColor : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildLocaleChip(String name, VidraLocale locale) {
    final isSelected = _currentLocaleName == name;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentLocaleName = name;
          _currentLocale = locale;
        });
        _controller.setLocale(locale);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? _currentTheme.primaryColor.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? _currentTheme.primaryColor
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? _currentTheme.primaryColor : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
