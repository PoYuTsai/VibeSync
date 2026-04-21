import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/article_read_service.dart';

final articleReadServiceProvider = Provider<ArticleReadService>((ref) {
  return ArticleReadService();
});
