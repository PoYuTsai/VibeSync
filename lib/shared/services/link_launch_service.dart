import 'package:url_launcher/url_launcher.dart';

class LinkLaunchService {
  static const Set<String> _externalHosts = {
    't.me',
    'telegram.me',
  };

  static LaunchMode preferredMode(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final isWebPage = scheme == 'http' || scheme == 'https';

    if (isWebPage && !_externalHosts.contains(host)) {
      return LaunchMode.inAppBrowserView;
    }

    return LaunchMode.externalApplication;
  }

  static Future<bool> open(String url) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      return false;
    }

    return launchUrl(uri, mode: preferredMode(uri));
  }
}
