import 'package:flutter/material.dart';

/// Opener / New Topic entry surfaces. Deliberately local to these two modes.
abstract final class OpenerHomeStyle {
  static const canvas = Color(0xFF171121);
  static const panel = Color(0xFF302638);
  static const panelEnd = Color(0xFF282031);
  static const input = Color(0xFF241D2F);
  static const selected = Color(0xFF3A3048);
  static const secondary = Color(0xFFC6BECE);
  static const disabled = Color(0xFF38313F);
  static const disabledText = Color(0xFFB9B3C4);
  static const icon = Color(0xFFF5F0F8);
  static const accent = Color(0xFFC68BFF);
  static const orange = Color(0xFFFF6A2B);
  static const ink = Color(0xFF150C24);
  static const iconBack = Color(0xFF766085);
  static const iconBackLight = Color(0xFFBDA4D2);
  static const iconBackEdge = Color(0xFF4B395D);
  static const iconPaperShade = Color(0xFFDED0DD);
  static const iconPaperEdge = Color(0xFFB09AA9);
  static const iconInset = Color(0xFFE1D6E7);
  static const iconInsetShade = Color(0xFFC0ACC9);
  static const iconRim = Color(0xFFD9C9D3);
  static const iconSymbol = Color(0xFF6B4C83);
  static const iconSymbolDark = Color(0xFF382345);
  static const iconOrangeLight = Color(0xFFFFAA61);
  static const iconOrangeEdge = Color(0xFFB7481D);
  static const ctaEnd = Color(0xFFE85A1E);
  static const label = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      height: 1.5);
  static const title = TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      height: 1.25);
  static const body = TextStyle(fontSize: 15, color: secondary, height: 1.5);
  static const helper = TextStyle(fontSize: 12, color: secondary, height: 1.45);

  static InputDecoration field(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: body,
        filled: true,
        fillColor: input,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: accent, width: 2)),
      );
}
