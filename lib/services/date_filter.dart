enum DateFilterType {
  all,
  today,
  week,
  month,
  custom,
}

class DateFilter {
  final DateFilterType type;
  final DateTime? from;
  final DateTime? to;

  DateFilter({this.type = DateFilterType.all, this.from, this.to});

  bool matches(String isoDate) {
    if (type == DateFilterType.all) return true;
    try {
      final dt = DateTime.parse(isoDate);
      final now = DateTime.now();
      switch (type) {
        case DateFilterType.today:
          return dt.year == now.year &&
              dt.month == now.month &&
              dt.day == now.day;
        case DateFilterType.week:
          final weekAgo = now.subtract(const Duration(days: 7));
          return dt.isAfter(weekAgo);
        case DateFilterType.month:
          final monthAgo = now.subtract(const Duration(days: 30));
          return dt.isAfter(monthAgo);
        case DateFilterType.custom:
          if (from != null && dt.isBefore(from!)) return false;
          if (to != null) {
            final end = DateTime(to!.year, to!.month, to!.day, 23, 59, 59);
            if (dt.isAfter(end)) return false;
          }
          return true;
        case DateFilterType.all:
          return true;
      }
    } catch (_) {
      return true;
    }
  }

  String get label {
    switch (type) {
      case DateFilterType.all:
        return 'الكل';
      case DateFilterType.today:
        return 'اليوم';
      case DateFilterType.week:
        return 'الأسبوع';
      case DateFilterType.month:
        return 'الشهر';
      case DateFilterType.custom:
        if (from != null && to != null) {
          return '${_fmt(from!)} - ${_fmt(to!)}';
        }
        return 'مخصص';
    }
  }

  static String _fmt(DateTime d) {
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }
}
