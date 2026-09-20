import 'package:flutter/material.dart';

import '../../../core/services/app_haptics.dart';
import '../pressable_scale.dart';
import '../../../core/theme/opener_home_style.dart';
export '../../../core/theme/opener_home_style.dart';

class OpenerHomePanel extends StatelessWidget {
  const OpenerHomePanel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [OpenerHomeStyle.panel, OpenerHomeStyle.panelEnd]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                offset: const Offset(0, 6),
                blurRadius: 16)
          ],
        ),
        child: child,
      );
}

class OpenerModeControl<T> extends StatelessWidget {
  const OpenerModeControl(
      {super.key,
      required this.value,
      required this.options,
      required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: OpenerHomeStyle.input,
            borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          for (final option in options)
            Expanded(
                child: Semantics(
              selected: value == option.$1,
              child: TextButton(
                onPressed: () {
                  if (value == option.$1) return;
                  AppHaptics.light();
                  onChanged(option.$1);
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  backgroundColor: value == option.$1
                      ? OpenerHomeStyle.selected
                      : Colors.transparent,
                  foregroundColor: value == option.$1
                      ? Colors.white
                      : OpenerHomeStyle.secondary,
                  textStyle: Theme.of(context)
                      .textTheme
                      .labelLarge!
                      .copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(option.$2),
              ),
            ))
        ]),
      );
}

class OpenerSourceTabs extends StatelessWidget {
  const OpenerSourceTabs(
      {super.key, required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int>? onChanged;
  @override
  Widget build(BuildContext context) => Row(children: [
        for (final (index, label) in const [(0, '截圖自介'), (1, '手動輸入')])
          Expanded(
            child: Semantics(
                selected: selected == index,
                child: Container(
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: selected == index
                                  ? OpenerHomeStyle.accent
                                  : Colors.transparent,
                              width: 2))),
                  child: TextButton(
                      onPressed: onChanged == null
                          ? null
                          : () {
                              if (selected == index) return;
                              AppHaptics.light();
                              onChanged!(index);
                            },
                      style: TextButton.styleFrom(
                          minimumSize: const Size(44, 48),
                          foregroundColor: selected == index
                              ? Colors.white
                              : OpenerHomeStyle.secondary,
                          textStyle: Theme.of(context)
                              .textTheme
                              .labelLarge!
                              .copyWith(
                                  fontSize: 15,
                                  fontWeight: selected == index
                                      ? FontWeight.w600
                                      : FontWeight.w400)),
                      child: Text(label)),
                )),
          )
      ]);
}

class OpenerSituationGrid extends StatelessWidget {
  const OpenerSituationGrid(
      {super.key,
      required this.options,
      required this.selected,
      required this.onChanged});
  final List<({String label, String value})> options;
  final String? selected;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final single = MediaQuery.textScalerOf(context).scale(15) > 20 ||
            constraints.maxWidth < 280;
        Widget item(({String label, String value}) option) {
          final active = selected == option.value;
          return Semantics(
              selected: active,
              inMutuallyExclusiveGroup: true,
              child: OutlinedButton(
                onPressed: onChanged == null
                    ? null
                    : () {
                        AppHaptics.light();
                        onChanged!(option.value);
                      },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  backgroundColor:
                      active ? OpenerHomeStyle.selected : OpenerHomeStyle.input,
                  foregroundColor:
                      active ? Colors.white : OpenerHomeStyle.secondary,
                  side: BorderSide(
                      color:
                          active ? OpenerHomeStyle.accent : Colors.transparent),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  textStyle: Theme.of(context)
                      .textTheme
                      .labelLarge!
                      .copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (active) ...[
                    const Icon(Icons.check, size: 16),
                    const SizedBox(width: 6)
                  ],
                  Flexible(
                      child: Text(option.label, textAlign: TextAlign.center)),
                ]),
              ));
        }

        return Column(children: [
          for (var i = 0; i < options.length; i += single ? 1 : 2) ...[
            if (i > 0) const SizedBox(height: 12),
            if (single)
              item(options[i])
            else
              Row(children: [
                Expanded(child: item(options[i])),
                const SizedBox(width: 12),
                Expanded(child: item(options[i + 1]))
              ]),
          ]
        ]);
      });
}

class OpenerActionFooter extends StatelessWidget {
  const OpenerActionFooter(
      {super.key,
      required this.label,
      required this.hint,
      required this.onPressed,
      required this.onQuota,
      this.buttonKey});
  final String label;
  final String hint;
  final VoidCallback? onPressed;
  final VoidCallback onQuota;
  final Key? buttonKey;
  @override
  Widget build(BuildContext context) => ColoredBox(
      color: OpenerHomeStyle.canvas,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (hint.isNotEmpty) ...[
            Text(hint,
                textAlign: TextAlign.center, style: OpenerHomeStyle.helper),
            const SizedBox(height: 8)
          ],
          PressableScale(
              enabled: onPressed != null,
              emitHaptics: false,
              reduceMotion: MediaQuery.disableAnimationsOf(context),
              child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: onPressed == null
                        ? null
                        : const LinearGradient(colors: [
                            OpenerHomeStyle.orange,
                            OpenerHomeStyle.ctaEnd
                          ]),
                    color: onPressed == null ? OpenerHomeStyle.disabled : null,
                    boxShadow: onPressed == null
                        ? null
                        : [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.20),
                                offset: const Offset(0, 4),
                                blurRadius: 12)
                          ],
                  ),
                  child: ElevatedButton(
                    key: buttonKey,
                    onPressed: AppHaptics.onPress(onPressed),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(44, 56),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: OpenerHomeStyle.ink,
                      disabledBackgroundColor: Colors.transparent,
                      disabledForegroundColor: OpenerHomeStyle.disabledText,
                      elevation: 0,
                      textStyle: Theme.of(context)
                          .textTheme
                          .labelLarge!
                          .copyWith(fontSize: 19, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Text(label, textAlign: TextAlign.center),
                  ))),
          TextButton(
              onPressed: AppHaptics.onPress(onQuota),
              style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: OpenerHomeStyle.accent),
              child: const Text('額度說明', style: TextStyle(fontSize: 12))),
        ]),
      ));
}

/// Exactly one footer; the form stays at the same element path across keyboard
/// and text-size changes, preserving its focus, controllers and picker state.
class OpenerResponsiveBody extends StatelessWidget {
  const OpenerResponsiveBody(
      {super.key,
      required this.content,
      required this.controller,
      this.footer});
  final Widget content;
  final ScrollController controller;
  final Widget? footer;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final fixed = constraints.maxHeight >= 600 &&
            MediaQuery.viewInsetsOf(context).bottom == 0 &&
            MediaQuery.textScalerOf(context).scale(15) < 20;
        return Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(children: [
                  Expanded(
                      child: SingleChildScrollView(
                          controller: controller,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                content,
                                if (!fixed && footer != null) footer!
                              ]))),
                  if (fixed && footer != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: footer!),
                ])));
      });
}
