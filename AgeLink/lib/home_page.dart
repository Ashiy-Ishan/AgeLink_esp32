import 'package:flutter/material.dart';
import 'constants.dart';
import 'home_screen.dart';
import 'medication_schedule_page.dart';
import 'notification_page.dart';
import 'app_menu_drawer.dart';
import 'gradient_scaffold.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    HomeScreen(),
    MedicationSchedulePage(),
    NotificationPage(),
  ];

  void _onItemTapped(int index, BuildContext context) {
    if (index == 3) {
      Scaffold.of(context).openEndDrawer();
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  Widget _navItem(BuildContext context, int index, IconData icon, IconData activeIcon, String label) {
    final bool selected = _selectedIndex == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () => _onItemTapped(index, context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            decoration: BoxDecoration(
              color: selected ? Constants.lightBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  size: 23,
                  color: selected ? Constants.darkblue : Constants.mediumGrey,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? Constants.darkblue : Constants.mediumGrey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      endDrawer: const AppMenuDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 74,
        leadingWidth: 143,
        leading: Padding(
          padding: const EdgeInsets.only(left: 20, top: 8, bottom: 8),
          child: Image.asset(
            'assets/agelink_logo.png',
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (context, error, stackTrace) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'AgeLink',
                style: TextStyle(color: Constants.darkblue, fontWeight: FontWeight.w800, fontSize: 22),
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Builder(
              builder: (context) {
                return Material(
                  color: Constants.lightBlue,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Scaffold.of(context).openEndDrawer(),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.person_outline_rounded, color: Constants.darkblue, size: 25),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: Builder(
        builder: (context) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Constants.darkblue.withValues(alpha: 0.08))),
              boxShadow: [
                BoxShadow(
                  color: Constants.darkblue.withValues(alpha: 0.055),
                  blurRadius: 14,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Row(
                  children: [
                    _navItem(context, 0, Icons.home_outlined, Icons.home_rounded, 'Home'),
                    _navItem(context, 1, Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Schedule'),
                    _navItem(context, 2, Icons.notifications_none_rounded, Icons.notifications_rounded, 'Alerts'),
                    _navItem(context, 3, Icons.menu_rounded, Icons.menu_rounded, 'Menu'),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
