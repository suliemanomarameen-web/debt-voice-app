import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/stats_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<CustomerStat> _top = [];
  List<MonthlyPoint> _trend = [];
  Map<String, double> _summary = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final top = await StatsService.topDebtors();
    final trend = await StatsService.monthlyTrend();
    final sum = await StatsService.summary();
    if (!mounted) return;
    setState(() {
      _top = top;
      _trend = trend;
      _summary = sum;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإحصائيات')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _buildSummaryCards(),
                    const SizedBox(height: 20),
                    _buildTopDebtors(),
                    const SizedBox(height: 20),
                    _buildMonthlyChart(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final items = [
      ('إجمالي الديون', _summary['total_debt'] ?? 0, Colors.red),
      ('إجمالي المدفوع', _summary['total_paid'] ?? 0, Colors.green),
      ('المتبقي', _summary['outstanding'] ?? 0, Colors.orange),
      ('عدد الحسابات', _summary['customers'] ?? 0, Colors.blue),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.0,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: items.map((e) {
        final (label, value, color) = e;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: TextStyle(color: color, fontSize: 12)),
              const SizedBox(height: 6),
              Text(value.toStringAsFixed(0),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTopDebtors() {
    if (_top.isEmpty) return const SizedBox();
    final maxVal = _top.first.balance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('أعلى 5 حسابات مديونية',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ..._top.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(c.name),
                          Text('${c.balance.toStringAsFixed(0)} ريال',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: maxVal == 0 ? 0 : c.balance / maxVal,
                        backgroundColor: Colors.red.shade50,
                        valueColor:
                            const AlwaysStoppedAnimation(Colors.red),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyChart() {
    if (_trend.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: Text('لا توجد بيانات بعد')),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('تطور الديون شهرياً',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _trend
                          .map((p) => p.debt > p.payment ? p.debt : p.payment)
                          .reduce((a, b) => a > b ? a : b) *
                      1.2,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= _trend.length) {
                            return const SizedBox();
                          }
                          final m = _trend[i].month.split('-');
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('${m[1]}/${m[0].substring(2)}',
                                style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(_trend.length, (i) {
                    final p = _trend[i];
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: p.debt,
                          color: Colors.red,
                          width: 8,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        BarChartRodData(
                          toY: p.payment,
                          color: Colors.green,
                          width: 8,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legend('الديون', Colors.red),
                const SizedBox(width: 20),
                _legend('المدفوع', Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(String label, Color c) => Row(
        children: [
          Container(width: 12, height: 12, color: c),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}
