import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AnalyticsRangePreset { last7, last30, monthToDate }

final analyticsRangeProvider = StateProvider<AnalyticsRangePreset>(
  (ref) => AnalyticsRangePreset.last7,
);

(DateTime start, DateTime end) analyticsRangeToDates(AnalyticsRangePreset preset) {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

  switch (preset) {
    case AnalyticsRangePreset.last7:
      final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      return (start, end);
    case AnalyticsRangePreset.last30:
      final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
      return (start, end);
    case AnalyticsRangePreset.monthToDate:
      final start = DateTime(now.year, now.month, 1);
      return (start, end);
  }
}
