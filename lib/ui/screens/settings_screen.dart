import 'package:flutter/material.dart';

import '../notifiers/settings_notifier.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsNotifier notifier;

  const SettingsScreen({super.key, required this.notifier});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Use speed coloured graph'),
            subtitle: const Text(
                'Colour the depth trace by vertical speed (red above 9 m/min)'),
            value: widget.notifier.useSpeedColoredGraph,
            onChanged: (v) => widget.notifier.setUseSpeedColoredGraph(v),
          ),
        ],
      ),
    );
  }
}
