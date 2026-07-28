import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import 'shell/desktop_shell.dart';
import 'shell/form_factor.dart';
import 'shell/mobile_shell.dart';
import 'shell/tv_shell.dart';

void main() {
  runApp(const ProviderScope(child: IptvApp()));
}

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reproductor IPTV',
      debugShowCheckedModeBanner: false,
      theme: IptvTheme.dark(),
      home: switch (FormFactorDetector.detect()) {
        FormFactor.tv => const TvShell(),
        FormFactor.mobile => const MobileShell(),
        FormFactor.desktop => const DesktopShell(),
      },
    );
  }
}
