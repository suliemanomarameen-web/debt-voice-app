import 'package:flutter/material.dart';
import 'debts_tab.dart';
import 'customers_tab.dart';
import 'transactions_tab.dart';
import 'logs_tab.dart';
import 'settings_tab.dart';

class TabsScreen extends StatefulWidget {
  const TabsScreen({super.key});
  @override
  State<TabsScreen> createState() => _TabsScreenState();
}

class _TabsScreenState extends State<TabsScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            const DebtsTab(),
            const CustomersTab(),
            TransactionsTab(key: _transactionsKey),
            LogsTab(key: _logsKey), // 🆕 تبويب السجل
            const SettingsTab(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) {
            setState(() => _currentIndex = i);

            // تحديث تبويب العمليات عند اختياره
            if (i == 2) {
              Future.delayed(const Duration(milliseconds: 100), () {
                final state = _transactionsKey.currentState;
                if (state != null && state.mounted) {
                  state.reload();
                }
              });
            }
            // تحديث تبويب السجل عند اختياره
            if (i == 3) {
              Future.delayed(const Duration(milliseconds: 100), () {
                final state = _logsKey.currentState;
                if (state != null && state.mounted) {
                  state.reload();
                }
              });
            }
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.book_outlined),
              selectedIcon: Icon(Icons.book),
              label: 'دفتر الديون',
            ),
            const NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'الحسابات',
            ),
            const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'العمليات',
            ),
            // 🆕 تبويب السجل مع شارة التنبيهات
            const NavigationDestination(
              icon: LogsTabIcon(selected: false),
              selectedIcon: LogsTabIcon(selected: true),
              label: 'السجل',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'الإعدادات',
            ),
          ],
        ),
      ),
    );
  }
}

/// 🆕 مفتاح عالمي لتبويب العمليات
final GlobalKey<TransactionsTabState> _transactionsKey =
    GlobalKey<TransactionsTabState>();

/// 🆕 مفتاح عالمي لتبويب السجل
final GlobalKey<LogsTabState> _logsKey = GlobalKey<LogsTabState>();
