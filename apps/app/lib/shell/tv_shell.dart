import 'package:flutter/material.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

/// Shell 10-foot: navegación por D-pad, foco siempre visible (P9).
/// Esqueleto del Sprint 0 — la navegación real llega con las pantallas
/// de ui-spec en F3.
class TvShell extends StatefulWidget {
  const TvShell({super.key});

  @override
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<TvShell> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IptvColors.background,
      body: Center(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: IptvSpacing.xxl,
              vertical: IptvSpacing.xl,
            ),
            decoration: BoxDecoration(
              color: IptvColors.surface,
              borderRadius: BorderRadius.circular(IptvSpacing.radius),
              border: _focused ? IptvFocus.ring() : null,
              boxShadow: _focused ? IptvFocus.haloShadow() : null,
            ),
            child: Text(
              'TvShell',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: IptvColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
