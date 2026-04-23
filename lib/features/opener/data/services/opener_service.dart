import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class OpenerResult {
  final Map<String, dynamic>? profileAnalysis;
  final Map<String, String> openers;
  final String? recommendedPick;
  final String? recommendedReason;
  final int costUsed;

  const OpenerResult({
    this.profileAnalysis,
    required this.openers,
    this.recommendedPick,
    this.recommendedReason,
    this.costUsed = 3,
  });
}

class OpenerService {
  Future<OpenerResult> generateOpeners({
    List<Uint8List>? images,
    String? name,
    String? bio,
    String? interests,
    String? meetingContext,
  }) async {
    // Build image list as base64
    List<String>? imageDataList;
    if (images != null && images.isNotEmpty) {
      imageDataList = images.map((img) => base64Encode(img)).toList();
    }

    // Build profile info
    Map<String, String>? profileInfo;
    if ((name != null && name.trim().isNotEmpty) ||
        (bio != null && bio.trim().isNotEmpty) ||
        (interests != null && interests.trim().isNotEmpty) ||
        (meetingContext != null && meetingContext.trim().isNotEmpty)) {
      profileInfo = {};
      if (name != null && name.trim().isNotEmpty) {
        profileInfo['name'] = name.trim();
      }
      if (bio != null && bio.trim().isNotEmpty) {
        profileInfo['bio'] = bio.trim();
      }
      if (interests != null && interests.trim().isNotEmpty) {
        profileInfo['interests'] = interests.trim();
      }
      if (meetingContext != null && meetingContext.trim().isNotEmpty) {
        profileInfo['meetingContext'] = meetingContext.trim();
      }
    }

    final body = {
      'mode': 'opener',
      if (imageDataList != null) 'images': imageDataList,
      if (profileInfo != null) 'profileInfo': profileInfo,
    };

    final response = await Supabase.instance.client.functions.invoke(
      'analyze-chat',
      body: body,
    );

    if (response.status != 200) {
      final errorData = response.data;
      final errorMsg = errorData is Map
          ? (errorData['error'] as String? ?? 'Unknown error')
          : 'Unknown error';
      throw Exception(errorMsg);
    }

    final data = response.data as Map<String, dynamic>;

    // Parse openers
    final openersRaw = data['openers'] as Map<String, dynamic>? ?? {};
    final openers = openersRaw.map((k, v) => MapEntry(k, v.toString()));

    // Parse recommendation
    final recommendation = data['recommendation'] as Map<String, dynamic>?;

    // Parse profile analysis
    final profileAnalysis = data['profileAnalysis'] as Map<String, dynamic>?;

    // Parse cost
    final usage = data['usage'] as Map<String, dynamic>?;
    final cost = usage?['cost'] as int? ?? 3;

    return OpenerResult(
      profileAnalysis: profileAnalysis,
      openers: openers,
      recommendedPick: recommendation?['pick'] as String?,
      recommendedReason: recommendation?['reason'] as String?,
      costUsed: cost,
    );
  }
}
