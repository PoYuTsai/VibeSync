// lib/features/partner/presentation/screens/partner_detail_screen.dart
//
// STUB — Task 6 placeholder so lib/app/routes.dart compiles.
// Task 9 replaces this with the real detail screen (header / traits /
// radar / conversation list / "+ 新增對話").
import 'package:flutter/material.dart';

class PartnerDetailScreen extends StatelessWidget {
  final String partnerId;
  const PartnerDetailScreen({super.key, required this.partnerId});

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('partner $partnerId')));
}
