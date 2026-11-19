import 'package:flutter/material.dart';

import '../models/note_models.dart';

enum ToolKind {
  pen,
  highlighter,
  eraser,
  lasso,
  text,
  shape,
  dimension,
  gdt,
  datum,
  surface,
  weld,
  cone,
  lane,
  road,
  route,
  motorcycle,
  gate,
  distance,
  north,
  pan,
}

class ToolInfo {
  final ToolKind kind;
  final String label;
  final IconData icon;
  final String? shortcut;
  const ToolInfo(this.kind, this.label, this.icon, [this.shortcut]);
}

const toolInfos = <ToolKind, ToolInfo>{
  ToolKind.pen: ToolInfo(ToolKind.pen, 'Kalem', Icons.edit, 'P'),
  ToolKind.highlighter: ToolInfo(ToolKind.highlighter, 'Fosforlu', Icons.highlight, 'H'),
  ToolKind.eraser: ToolInfo(ToolKind.eraser, 'Silgi', Icons.auto_fix_normal, 'E'),
  ToolKind.lasso: ToolInfo(ToolKind.lasso, 'Kement', Icons.gesture, 'L'),
  ToolKind.text: ToolInfo(ToolKind.text, 'Metin', Icons.text_fields, 'T'),
  ToolKind.shape: ToolInfo(ToolKind.shape, 'Şekil', Icons.category_outlined, 'S'),
  ToolKind.dimension: ToolInfo(ToolKind.dimension, 'Ölçü', Icons.straighten, 'D'),
  ToolKind.gdt: ToolInfo(ToolKind.gdt, 'GD&T', Icons.grid_view),
  ToolKind.datum: ToolInfo(ToolKind.datum, 'Datum', Icons.change_history),
  ToolKind.surface: ToolInfo(ToolKind.surface, 'Yüzey', Icons.check),
  ToolKind.weld: ToolInfo(ToolKind.weld, 'Kaynak', Icons.call_split),
  ToolKind.cone: ToolInfo(ToolKind.cone, 'Koni', Icons.change_history, 'C'),
  ToolKind.lane: ToolInfo(ToolKind.lane, 'Şerit', Icons.view_stream),
  ToolKind.road: ToolInfo(ToolKind.road, 'Yol', Icons.add_road),
  ToolKind.route: ToolInfo(ToolKind.route, 'Rota oku', Icons.route),
  ToolKind.motorcycle: ToolInfo(ToolKind.motorcycle, 'Motosiklet', Icons.two_wheeler),
  ToolKind.gate: ToolInfo(ToolKind.gate, 'Start/Finiş', Icons.flag_outlined),
  ToolKind.distance: ToolInfo(ToolKind.distance, 'Mesafe (m)', Icons.straighten),
  ToolKind.north: ToolInfo(ToolKind.north, 'Kuzey', Icons.navigation_outlined),
  ToolKind.pan: ToolInfo(ToolKind.pan, 'Kaydır', Icons.pan_tool_outlined),
};

const _common = [ToolKind.pen, ToolKind.highlighter, ToolKind.eraser, ToolKind.lasso, ToolKind.text, ToolKind.shape];
const _engineering = [ToolKind.dimension, ToolKind.gdt, ToolKind.datum, ToolKind.surface, ToolKind.weld];
const _moto = [ToolKind.cone, ToolKind.lane, ToolKind.road, ToolKind.route, ToolKind.motorcycle, ToolKind.gate, ToolKind.distance, ToolKind.north];

List<ToolKind> toolsFor(PageMode mode) => switch (mode) {
      PageMode.engineering => [..._common, ..._engineering],
      PageMode.moto => [..._common, ..._moto],
      PageMode.both => [..._common, ..._engineering, ..._moto],
    };

/// Telefon alt çubuğunda doğrudan görünenler
List<ToolKind> primaryToolsFor(PageMode mode) => switch (mode) {
      PageMode.moto => [ToolKind.pen, ToolKind.eraser, ToolKind.cone, ToolKind.lane, ToolKind.lasso],
      _ => [ToolKind.pen, ToolKind.eraser, ToolKind.shape, ToolKind.dimension, ToolKind.lasso],
    };

const penPalette = <int>[
  0xFF000000, 0xFF1A237E, 0xFF0D47A1, 0xFFC62828, 0xFF2E7D32, 0xFFEF6C00, 0xFF6A1B9A, 0xFF546E7A,
];
const highlighterPalette = <int>[0xFFFFEB3B, 0xFF76FF03, 0xFF40C4FF, 0xFFFF80AB, 0xFFFFAB40];
