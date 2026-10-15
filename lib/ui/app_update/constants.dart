import 'dart:io';

abstract class Constants {
  // fork 仓库的发布源：应用内「检查更新」只认这里的 Release（不再指向上游 wanghongenpin/proxypin）
  static const githubUrl = "https://github.com/1196013153/proxypin";
  static const githubReleasesApiUrl =
      "https://api.github.com/repos/1196013153/proxypin/releases";
  static const githubLatestReleaseUrl =
      "https://github.com/1196013153/proxypin/releases/latest";

  static const String ignoreReleaseVersionKey = "ignored_release_version";

  /// 本机构建号(versionCode)，由 CI 构建时通过 --dart-define=PROXYPIN_BUILD_NUMBER 注入；
  /// 未注入（本地开发构建）时为 0，此时只按 versionName 比较，行为与改动前一致。
  static const int buildNumber = int.fromEnvironment('PROXYPIN_BUILD_NUMBER', defaultValue: 0);

  /// GitHub 下载镜像前缀，仅中文环境使用。
  /// 设为空字符串可关闭镜像。
  static const githubMirror = "https://ghproxy.top/";

  /// 返回主 URL 和镜像 URL（仅中文环境有镜像）。
  /// 主 URL 在前，镜像在后，下载时优先直连。
  static List<String> mirrorUrls(String url) {
    final urls = <String>[url];
    if (githubMirror.isEmpty) return urls;
    if (!Platform.localeName.startsWith('zh')) return urls;
    final uri = Uri.tryParse(url);
    if (uri == null) return urls;
    if (uri.host == 'github.com' || uri.host == 'api.github.com') {
      urls.add('$githubMirror$url');
    }
    return urls;
  }
}

const kAnimationDuration = Duration(milliseconds: 250);