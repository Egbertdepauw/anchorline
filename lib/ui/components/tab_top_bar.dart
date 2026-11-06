import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/anchorline_logo.dart';

/// The one-row top bar of the Gas and Settings destinations: the anchor
/// (taps back to the home screen), a hairline divider, and a [TabBar] driven
/// by the enclosing [DefaultTabController]. Use as `Scaffold.appBar`.
class TabTopBar extends StatelessWidget implements PreferredSizeWidget {
  const TabTopBar({super.key, required this.tabs, required this.onHome});

  final List<Widget> tabs;
  final VoidCallback onHome;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceBg,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: Spacing.sm),
              InkResponse(
                key: const ValueKey('tab-top-bar-home'),
                onTap: onHome,
                radius: 24,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: AnchorlineLogo(
                        mark: AnchorlineMark.icon, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Container(width: 1, height: 28, color: palette.surfaceRaised),
              Expanded(child: TabBar(tabs: tabs)),
            ],
          ),
        ),
      ),
    );
  }
}
