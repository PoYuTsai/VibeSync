// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/config/environment.dart';
import 'core/services/storage_service.dart';
import 'core/services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Log environment info
  if (kDebugMode) {
    debugPrint('🚀 Running in ${AppConfig.environmentName} mode');
    debugPrint('📡 Supabase URL: ${AppConfig.supabaseUrl}');
  }

  // Initialize local storage
  await StorageService.initialize();

  // Initialize Supabase using environment config
  await SupabaseService.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
