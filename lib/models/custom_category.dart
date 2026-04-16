import 'package:flutter/material.dart';

class CustomCategory {
  final int? id;
  final String name;
  final String iconCodepoint; // hex string e.g. 'e148'
  final String colorValue; // hex ARGB string e.g. 'FF607D8B'

  const CustomCategory({
    this.id,
    required this.name,
    required this.iconCodepoint,
    required this.colorValue,
  });

  IconData get iconData => IconData(
        int.parse(iconCodepoint, radix: 16),
        fontFamily: 'MaterialIcons',
      );

  Color get color => Color(int.parse(colorValue, radix: 16));

  CustomCategory copyWith({
    int? id,
    String? name,
    String? iconCodepoint,
    String? colorValue,
  }) =>
      CustomCategory(
        id: id ?? this.id,
        name: name ?? this.name,
        iconCodepoint: iconCodepoint ?? this.iconCodepoint,
        colorValue: colorValue ?? this.colorValue,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'icon': iconCodepoint,
        'color': colorValue,
      };

  factory CustomCategory.fromMap(Map<String, dynamic> map) => CustomCategory(
        id: map['id'] as int?,
        name: map['name'] as String,
        iconCodepoint: map['icon'] as String,
        colorValue: map['color'] as String,
      );

  /// Preset color swatches for the category picker UI.
  static const List<Color> presetColors = [
    Color(0xFFE53935), // Red
    Color(0xFFF4511E), // Deep Orange
    Color(0xFFFB8C00), // Orange
    Color(0xFFFFB300), // Amber
    Color(0xFF43A047), // Green
    Color(0xFF00ACC1), // Cyan
    Color(0xFF1E88E5), // Blue
    Color(0xFF5E35B1), // Deep Purple
    Color(0xFFD81B60), // Pink
    Color(0xFF607D8B), // Blue Grey
  ];

  /// Preset icons for the category picker UI.
  static const List<IconData> presetIcons = [
    Icons.fastfood_rounded,
    Icons.directions_bus_rounded,
    Icons.home_rounded,
    Icons.sports_esports_rounded,
    Icons.checkroom_rounded,
    Icons.fitness_center_rounded,
    Icons.school_rounded,
    Icons.pets_rounded,
    Icons.flight_rounded,
    Icons.local_cafe_rounded,
    Icons.car_repair_rounded,
    Icons.business_center_rounded,
    Icons.child_care_rounded,
    Icons.celebration_rounded,
    Icons.spa_rounded,
  ];
}
