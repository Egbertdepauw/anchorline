import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import '../../notifiers/equipment_notifiers.dart';
import 'dive_computer_detail_screen.dart';

class DiveComputersListScreen extends StatefulWidget {
  final EquipmentDao dao;

  const DiveComputersListScreen({super.key, required this.dao});

  @override
  State<DiveComputersListScreen> createState() =>
      _DiveComputersListScreenState();
}

class _DiveComputersListScreenState extends State<DiveComputersListScreen> {
  late final DiveComputersNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = DiveComputersNotifier(widget.dao);
    _notifier.addListener(_onChanged);
    _notifier.load();
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _notifier.removeListener(_onChanged);
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dive Computers')),
      body: _notifier.loading
          ? const Center(child: CircularProgressIndicator())
          : _notifier.computers.isEmpty
              ? const Center(child: Text('No dive computers yet'))
              : ListView.builder(
                  itemCount: _notifier.computers.length,
                  itemBuilder: (_, i) {
                    final dc = _notifier.computers[i];
                    return ListTile(
                      title: Text(_displayName(dc)),
                      subtitle: Text(
                        'FW ${dc.firmwareVersion ?? '?'} · ${_relativeTime(dc.updatedAt)}',
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => DiveComputerDetailScreen(
                            dao: widget.dao,
                            id: dc.id,
                          ),
                        ));
                        await _notifier.load();
                      },
                    );
                  },
                ),
    );
  }

  String _displayName(DiveComputer dc) {
    if (dc.nickname != null && dc.nickname!.isNotEmpty) return dc.nickname!;
    final model = modelFromHardware(dc.model).displayName;
    final hex = dc.serial.toRadixString(16).padLeft(8, '0');
    final tail = hex.substring(hex.length - 4);
    return '$model · …$tail';
  }

  String _relativeTime(int epochMs) {
    final delta = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(epochMs));
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    if (delta.inDays < 30) return '${(delta.inDays / 7).floor()}w ago';
    return '${(delta.inDays / 30).floor()}mo ago';
  }
}

extension on ShearwaterModel {
  String get displayName {
    switch (this) {
      case ShearwaterModel.predator:
        return 'Predator';
      case ShearwaterModel.petrel:
        return 'Petrel';
      case ShearwaterModel.petrel2:
        return 'Petrel 2';
      case ShearwaterModel.petrel3:
        return 'Petrel 3';
      case ShearwaterModel.nerd:
        return 'NERD';
      case ShearwaterModel.nerd2:
        return 'NERD 2';
      case ShearwaterModel.perdix:
        return 'Perdix';
      case ShearwaterModel.perdixAi:
        return 'Perdix AI';
      case ShearwaterModel.perdix2:
        return 'Perdix 2';
      case ShearwaterModel.teric:
        return 'Teric';
      case ShearwaterModel.peregrine:
        return 'Peregrine';
      case ShearwaterModel.peregrineTx:
        return 'Peregrine TX';
      case ShearwaterModel.tern:
        return 'Tern';
      case ShearwaterModel.unknown:
        return 'Unknown';
    }
  }
}
