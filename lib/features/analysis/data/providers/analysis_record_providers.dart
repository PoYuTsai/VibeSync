import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../repositories/analysis_record_store.dart';

/// Lazy settings-box access is deliberate: many AnalysisScreen widget tests
/// do not initialize Hive. Constructing or reading this provider is safe; the
/// store's synchronous reads fail closed to null/empty until the box exists.
final analysisRecordStoreProvider = Provider<AnalysisRecordStore>(
  (_) => HiveAnalysisRecordStore(() => StorageService.settingsBox),
);

/// Explicit seam keeps owner isolation testable without weakening production
/// reads to whatever owner happens to be stored on a local Conversation row.
final analysisRecordOwnerProvider = Provider<String?>(
  (ref) =>
      ref.watch(authConversationScopeProvider).valueOrNull ??
      SupabaseService.currentUser?.id,
);
