import 'package:flutter/material.dart';

enum SpendingInsightType {
  anomaly,
  weekendSpender,
  peakHour,
  overspendDay,
  growingCategory,
  recurringDetected,
  budgetWarning,
}

class SpendingInsight {
  final SpendingInsightType type;
  final String title;
  final String body;
  final IconData icon;
  final bool isWarning;

  const SpendingInsight({
    required this.type,
    required this.title,
    required this.body,
    required this.icon,
    this.isWarning = false,
  });
}
