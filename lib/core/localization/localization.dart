import '../model/player_locale.dart';

/// Player localization support
class VidraLocalization {
  final VidraLocale locale;

  const VidraLocalization(this.locale);

  /// Translated text for key, supports argument replacement
  String translate(String key, {Map<String, String>? args}) {
    String text = key;

    // Prefer custom translations
    if (locale.customTranslations != null &&
        locale.customTranslations!.containsKey(key)) {
      text = locale.customTranslations![key]!;
    } else {
      // Use built-in translations
      final translations = _translations[locale.languageCode];
      if (translations != null && translations.containsKey(key)) {
        text = translations[key]!;
      } else {
        // Fallback to English
        final fallback = _translations['en'];
        if (fallback != null && fallback.containsKey(key)) {
          text = fallback[key]!;
        }
      }
    }

    // Argument replacement
    if (args != null && args.isNotEmpty) {
      args.forEach((k, v) {
        text = text.replaceAll('{$k}', v);
      });
    }

    return text;
  }

  /// Built-in translation map
  static const Map<String, Map<String, String>> _translations = {
    'en': {
      // Playback controls
      'play': 'Play',
      'pause': 'Pause',
      'previous_episode': 'Previous Episode',
      'next_episode': 'Next Episode',
      'mute': 'Mute',
      'unmute': 'Unmute',
      'fullscreen': 'Fullscreen',
      'exit_fullscreen': 'Exit Fullscreen',
      'picture_in_picture': 'Picture in Picture',
      'settings': 'Settings',
      'more': 'More',
      'quality': 'Quality',
      'speed': 'Speed',
      'playback_speed': 'Playback Speed',
      'episode_list': 'Episode List',

      // Resume dialog
      'resume_playback': 'Resume Playback',
      'restart': 'Restart',
      'continue_playback': 'Continue',
      'last_watched_at': 'Last watched at',
      'auto_resume_in_seconds': 'seconds until auto resume',
      'watched_complete': 'Watched Complete',
      'you_watched_to': 'You watched to',
      'play_next_episode': 'Play Next Episode',
      'replay': 'Replay',
      'cancel': 'Cancel',
      'dismiss': 'Dismiss',
      'auto_resume_playback': 'Auto Resume Playback',

      // Episode list
      'download_manager': 'Download Manager',
      'ascending': 'Ascending',
      'descending': 'Descending',
      'sort_ascending': 'Sort Ascending',
      'sort_descending': 'Sort Descending',
      'download_options': 'Download Options',
      'download_all_episodes': 'Download All Episodes',
      'batch_selection': 'Batch Selection',
      'download_all': 'Download All',
      'confirm_download_all': 'Download all {count} episodes?',
      'select_quality': 'Select Quality',
      'from': 'From',
      'to': 'To',
      'episode_number': 'Episode {number}',
      'start_download': 'Start Download',
      'batch_select_episodes': 'Batch Select Episodes',

      // Error messages
      'playback_error': 'Playback Error',
      'playback_failed': 'Playback Failed',
      'error': 'Error',
      'details': 'Details',
      'error_code': 'Error Code',
      'timestamp': 'Timestamp',
      'stack_trace': 'Stack Trace',
      'report_issue': 'Report Issue',
      'close': 'Close',
      'retry': 'Retry',
      'try_another_source': 'Try another source',
      'network_error': 'Network Error',
      'video_not_found': 'Video Not Found',
      'access_denied': 'Access Denied',
      'authentication_required': 'Authentication Required',
      'server_error': 'Server Error',
      'request_timeout': 'Request Timeout',
      'connection_error': 'Connection Error',
      'connection_timeout': 'Connection Timeout',
      'unsupported_video_format': 'Unsupported Video Format',
      'unsupported_subtitle_format': 'Unsupported Subtitle Format',
      'format_error': 'Format Error',
      'current_format': 'Current Format',
      'supported_formats': 'Supported Formats',
      'decoding_error': 'Decoding Error',
      'decoder_error': 'Decoder Error',
      'video_decoding_error': 'Video Decoding Error',
      'codec': 'Codec',
      'container_format': 'Container Format',
      'hardware_acceleration_failed': 'Hardware Acceleration Failed',
      'hardware_decoding': 'Hardware Decoding',
      'software_decoding': 'Software Decoding',
      'method': 'Method',
      'timeout_seconds': 'Timeout: {seconds} seconds',

      // Settings
      'auto_skip_opening': 'Auto Skip Opening',
      'skip_opening': 'Skip Opening',
      'skip_ending': 'Skip Ending',

      // Keyboard shortcuts
      'shortcut_fullscreen': 'Fullscreen',
      'shortcut_mute': 'Mute',
      'shortcut_volume_up': 'Volume Up',
      'shortcut_volume_down': 'Volume Down',
      'shortcut_pip': 'Picture in Picture',
      'shortcut_next_episode': 'Next Episode',
      'shortcut_previous_episode': 'Previous Episode',
      'shortcut_search': 'Search',
      'shortcut_screenshot': 'Screenshot',
      'shortcut_download': 'Download',
      'shortcut_unknown': 'Unknown Shortcut',

      // Notifications
      'skipping_intro': 'Skipping intro...',
      'skipping_outro': 'Preparing to skip outro...',

      // Added for cleanup
      'switching_to_quality': 'Switching to {quality}...',
      'please_wait': 'Please wait',
      'loading_video': 'Loading video...',
      'retrying_with_count': 'Retrying... ({attempt}/{total})',
      'source_unavailable': 'This video source is temporarily unavailable.',
      'auto': 'Auto',

      // Misc
      'unknown_episode': 'Unknown Episode',
      'in_pip_mode': 'In PiP Mode',
    },
    'zh_CN': {
      // Playback controls
      'play': '播放',
      'pause': '暂停',
      'previous_episode': '上一集',
      'next_episode': '下一集',
      'mute': '静音',
      'unmute': '取消静音',
      'fullscreen': '全屏',
      'exit_fullscreen': '退出全屏',
      'picture_in_picture': '画中画',
      'settings': '设置',
      'more': '更多',
      'quality': '画质',
      'speed': '速度',
      'playback_speed': '播放速度',
      'episode_list': '剧集列表',

      // Resume dialog
      'resume_playback': '恢复播放',
      'restart': '重新开始',
      'continue_playback': '继续播放',
      'last_watched_at': '上次观看到',
      'auto_resume_in_seconds': '秒后自动继续播放',
      'watched_complete': '已观看完成',
      'you_watched_to': '您已观看到',
      'play_next_episode': '播放下一集',
      'replay': '重新播放',
      'cancel': '取消',
      'dismiss': '取消',
      'auto_resume_playback': '自动恢复播放',

      // Episode list
      'download_manager': '下载管理',
      'ascending': '升序',
      'descending': '降序',
      'sort_ascending': '升序排列',
      'sort_descending': '降序排列',
      'download_options': '下载选项',
      'download_all_episodes': '下载全部剧集',
      'batch_selection': '批量选择',
      'download_all': '下载全部',
      'confirm_download_all': '确定要下载全部 {count} 个剧集吗?',
      'select_quality': '选择画质',
      'from': '从',
      'to': '到',
      'episode_number': '第 {number} 集',
      'start_download': '开始下载',
      'batch_select_episodes': '批量选择剧集',

      // Error messages
      'playback_error': '播放错误',
      'playback_failed': '播放失败',
      'error': '错误',
      'details': '详情',
      'error_code': '错误代码',
      'timestamp': '时间',
      'stack_trace': '堆栈跟踪',
      'report_issue': '报告问题',
      'close': '关闭',
      'retry': '重试',
      'try_another_source': '尝试其他线路',
      'network_error': '网络错误',
      'video_not_found': '视频资源不存在',
      'access_denied': '无权访问此视频',
      'authentication_required': '需要身份验证',
      'server_error': '服务器错误',
      'request_timeout': '请求超时',
      'connection_error': '网络连接错误',
      'connection_timeout': '连接超时',
      'unsupported_video_format': '不支持的视频格式',
      'unsupported_subtitle_format': '不支持的字幕格式',
      'format_error': '格式错误',
      'current_format': '当前格式',
      'supported_formats': '支持格式',
      'decoding_error': '解码错误',
      'decoder_error': '解码器错误',
      'video_decoding_error': '视频解码错误',
      'codec': '编解码器',
      'container_format': '容器格式',
      'hardware_acceleration_failed': '硬件加速失败',
      'hardware_decoding': '硬件解码',
      'software_decoding': '软件解码',
      'method': '方法',
      'timeout_seconds': '超时: {seconds}秒',

      // Settings
      'auto_skip_opening': '跳过片头/片尾',
      'skip_opening': '跳过片头',
      'skip_ending': '跳过片尾',

      // Keyboard shortcuts
      'shortcut_fullscreen': '全屏',
      'shortcut_mute': '静音',
      'shortcut_volume_up': '音量增加',
      'shortcut_volume_down': '音量减少',
      'shortcut_pip': '画中画',
      'shortcut_next_episode': '下一集',
      'shortcut_previous_episode': '上一集',
      'shortcut_search': '搜索',
      'shortcut_screenshot': '截图',
      'shortcut_download': '下载',
      'shortcut_unknown': '未知快捷键',

      // Notifications
      'skipping_intro': '正在跳过开头...',
      'skipping_outro': '正在准备跳过结尾，进入下一集',

      // Added for cleanup
      'switching_to_quality': '正在切换到 {quality}...',
      'please_wait': '请稍候',
      'loading_video': '正在加载视频...',
      'retrying_with_count': '正在重试... ({attempt}/{total})',
      'source_unavailable': '该视频源暂时不可用。',
      'auto': '自动',

      // Misc
      'unknown_episode': '未知剧集',
      'in_pip_mode': '正在画中画播放',
    },
    'zh_TW': {
      // Playback controls
      'play': '播放',
      'pause': '暫停',
      'previous_episode': '上一集',
      'next_episode': '下一集',
      'mute': '靜音',
      'unmute': '取消靜音',
      'fullscreen': '全螢幕',
      'exit_fullscreen': '退出全螢幕',
      'picture_in_picture': '子母畫面',
      'settings': '設定',
      'more': '更多',
      'quality': '畫質',
      'speed': '速度',
      'playback_speed': '播放速度',
      'episode_list': '劇集列表',

      // Resume dialog
      'resume_playback': '恢復播放',
      'restart': '重新開始',
      'continue_playback': '繼續播放',
      'last_watched_at': '上次觀看到',
      'auto_resume_in_seconds': '秒後自動繼續播放',
      'watched_complete': '已觀看完成',
      'you_watched_to': '您已觀看到',
      'play_next_episode': '播放下一集',
      'replay': '重新播放',
      'cancel': '取消',
      'dismiss': '取消',
      'auto_resume_playback': '自動恢復播放',

      // Episode list
      'download_manager': '下載管理',
      'ascending': '升序',
      'descending': '降序',
      'sort_ascending': '升序排列',
      'sort_descending': '降序排列',
      'download_options': '下載選項',
      'download_all_episodes': '下載全部劇集',
      'batch_selection': '批次選擇',
      'download_all': '下載全部',
      'confirm_download_all': '確定要下載全部 {count} 個劇集嗎?',
      'select_quality': '選擇畫質',
      'from': '從',
      'to': '到',
      'episode_number': '第 {number} 集',
      'start_download': '開始下載',
      'batch_select_episodes': '批次選擇劇集',

      // Error messages
      'playback_error': '播放錯誤',
      'playback_failed': '播放失敗',
      'error': '錯誤',
      'details': '詳情',
      'error_code': '錯誤代碼',
      'timestamp': '時間',
      'stack_trace': '堆疊追蹤',
      'report_issue': '報告問題',
      'close': '關閉',
      'retry': '重試',
      'try_another_source': '嘗試其他線路',
      'network_error': '網路錯誤',
      'video_not_found': '影片資源不存在',
      'access_denied': '無權存取此影片',
      'authentication_required': '需要身份驗證',
      'server_error': '伺服器錯誤',
      'request_timeout': '請求逾時',
      'connection_error': '網路連線錯誤',
      'connection_timeout': '連線逾時',
      'unsupported_video_format': '不支援的影片格式',
      'unsupported_subtitle_format': '不支援的字幕格式',
      'format_error': '格式錯誤',
      'current_format': '目前格式',
      'supported_formats': '支援格式',
      'decoding_error': '解碼錯誤',
      'decoder_error': '解碼器錯誤',
      'video_decoding_error': '影片解碼錯誤',
      'codec': '編解碼器',
      'container_format': '容器格式',
      'hardware_acceleration_failed': '硬體加速失敗',
      'hardware_decoding': '硬體解碼',
      'software_decoding': '軟體解碼',
      'method': '方法',
      'timeout_seconds': '逾時: {seconds}秒',

      // Settings
      'auto_skip_opening': '自動跳過片頭',
      'skip_opening': '跳過片頭',
      'skip_ending': '跳過片尾',

      // Keyboard shortcuts
      'shortcut_fullscreen': '全螢幕',
      'shortcut_mute': '靜音',
      'shortcut_volume_up': '音量增加',
      'shortcut_volume_down': '音量減少',
      'shortcut_pip': '子母畫面',
      'shortcut_next_episode': '下一集',
      'shortcut_previous_episode': '上一集',
      'shortcut_search': '搜尋',
      'shortcut_screenshot': '截圖',
      'shortcut_download': '下載',
      'shortcut_unknown': '未知快捷鍵',

      // Notifications
      'skipping_intro': '正在跳過開頭...',
      'skipping_outro': '正在準備跳過結尾，進入下一集',

      // Added for cleanup
      'switching_to_quality': '正在切換到 {quality}...',
      'please_wait': '請稍候',
      'loading_video': '正在載入影片...',
      'retrying_with_count': '正在重試... ({attempt}/{total})',
      'source_unavailable': '該影片來源暫不可用。',
      'auto': '自動',

      // Misc
      'unknown_episode': '未知劇集',
      'in_pip_mode': '正在子母畫面播放',
    },
  };
}
