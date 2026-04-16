import 'package:flutter/material.dart';

const List<String> kBuiltinCategories = [
  'Food',
  'Transport',
  'Utilities',
  'Entertainment',
  'Shopping',
  'Health',
  'Others',
];

Color categoryColor(String category) {
  return switch (category.toLowerCase()) {
    'food' => Colors.orange,
    'transport' => Colors.blue,
    'utilities' => Colors.green,
    'entertainment' => Colors.deepPurple,
    'shopping' => Colors.pink,
    'health' => Colors.red,
    _ => Colors.blueGrey,
  };
}

IconData categoryIcon(String category) {
  return switch (category.toLowerCase()) {
    'food' => Icons.restaurant_rounded,
    'transport' => Icons.directions_car_rounded,
    'utilities' => Icons.lightbulb_rounded,
    'entertainment' => Icons.movie_rounded,
    'shopping' => Icons.shopping_bag_rounded,
    'health' => Icons.medical_services_rounded,
    _ => Icons.category_rounded,
  };
}
