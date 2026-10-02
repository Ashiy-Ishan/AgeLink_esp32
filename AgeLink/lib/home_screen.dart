// lib/home_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'constants.dart';
import 'package:intl/intl.dart';

import 'pair_device_page.dart';

class _TodayDose {
  final String time;
  final String name;
  final String dosage;

  _TodayDose({
    required this.time,
    required this.name,
    required this.dosage,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _currentDate = 'Loading...';

  final User? _currentUser = FirebaseAuth.instance.currentUser;

  late final DatabaseReference _deviceRef;
  late final DatabaseReference _medsRef;
  late final DatabaseReference _historyRef;

  @override
  void initState() {
    super.initState();
    DateTime now = DateTime.now();
    _currentDate = _formatDate(now);

    if (_currentUser != null) {
      final db = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL:
          "https://agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app");

      final uid = _currentUser!.uid;
      final todayDate = DateFormat('yyyy-MM-dd').format(now);

      _deviceRef = db.ref('reminders/$uid/device');
      _medsRef = db.ref('reminders/$uid/schedule/med_times');
      _historyRef = db.ref('reminders/$uid/history/$todayDate');
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('EEEE, MMMM d').format(date);
  }

  String _formatTime12h(String time24h) {
    try {
      final parts = time24h.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final dt = DateTime(2025, 1, 1, hour, minute);
      return TimeOfDay.fromDateTime(dt).format(context);
    } catch (e) {
      return time24h;
    }
  }

  Widget _buildGradientButton({
    required VoidCallback? onPressed,
    required String text,
    IconData? icon,
    required Gradient gradient,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.0),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18.0),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                ],
                Text(
                  text,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- STUNNING MODERN UI: "Next Dose" Hero Card with Geometric Depth ---
  Widget _buildNextDoseCard(_TodayDose dose) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF396AFC), Color(0xFF2948FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2948FF).withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background abstract geometric circles for depth
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),

          // Foreground Content
          Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Frosted Glass Label
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_active_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 8),
                              Text(
                                'UPCOMING DOSE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Icon(Icons.medication_liquid_rounded, color: Colors.white.withValues(alpha: 0.4), size: 40),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  _formatTime12h(dose.time),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  dose.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.science_rounded, color: Colors.white.withValues(alpha: 0.8), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Dosage: ${dose.dosage}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- ULTRA-CLEAN UI: Floating Status Cards (No lines/dots) ---
  Widget _buildDailyLogCard(_TodayDose dose, String status) {
    Color statusColor;
    Color bgColor;
    String statusText;
    IconData statusIcon;

    if (status == 'taken') {
      statusColor = Constants.greenColor;
      bgColor = Constants.greenColor.withValues(alpha: 0.1);
      statusText = 'Taken';
      statusIcon = Icons.check_circle_rounded;
    } else if (status == 'missed') {
      statusColor = Colors.redAccent;
      bgColor = Colors.redAccent.withValues(alpha: 0.1);
      statusText = 'Missed';
      statusIcon = Icons.cancel_rounded;
    } else {
      statusColor = const Color(0xFF1E88E5);
      bgColor = const Color(0xFF1E88E5).withValues(alpha: 0.1);
      statusText = 'Pending';
      statusIcon = Icons.schedule_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Accent Bar
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    // Time block
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _formatTime12h(dose.time),
                        style: TextStyle(
                          color: Constants.darkGrey,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Med Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dose.name,
                            style: TextStyle(
                              color: Constants.darkGrey,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dose.dosage,
                            style: TextStyle(
                              color: Constants.mediumGrey,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Status Chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(statusIcon, color: statusColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Center(child: Text('Please log in.'));
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),

          // Header Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Constants.mediumGrey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _currentDate,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Constants.darkGrey,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // --- EXACT ORIGINAL DEVICE CONNECTED BANNER ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: StreamBuilder<DatabaseEvent>(
              stream: _deviceRef.onValue,
              builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    snapshot.data!.snapshot.value == null) {
                  return _buildGradientButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PairDevicePage(),
                        ),
                      );
                    },
                    text: 'Connect Device',
                    icon: Icons.device_hub,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                  );
                }

                final deviceData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                final bool isOnline = deviceData['device_active'] == true;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isOnline
                          ? [Constants.greenColor.withValues(alpha: 0.8), Constants.greenColor]
                          : [Colors.redAccent.shade200, Colors.redAccent.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: (isOnline ? Constants.greenColor : Colors.redAccent)
                            .withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOnline ? 'Device Connected' : 'Device Offline',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isOnline ? 'Ready for today\'s schedule' : 'Please check connection',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 32),

          // --- SCHEDULE STREAM BUILDER ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: StreamBuilder<DatabaseEvent>(
              stream: _medsRef.onValue,
              builder: (context, scheduleSnapshot) {
                if (scheduleSnapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.all(32.0), child: Center(child: CircularProgressIndicator()));
                }

                if (scheduleSnapshot.hasError || !scheduleSnapshot.hasData || scheduleSnapshot.data!.snapshot.value == null) {
                  return _buildEmptyScheduleState();
                }

                final medTimesMap = scheduleSnapshot.data!.snapshot.value as Map;
                final todayDoses = medTimesMap.entries.map((entry) {
                  final med = Map<String, dynamic>.from(entry.value as Map);
                  return _TodayDose(
                    time: med['time'] ?? '00:00',
                    name: med['name'] ?? 'N/A',
                    dosage: med['dosage'] ?? 'N/A',
                  );
                }).toList();

                todayDoses.sort((a, b) => a.time.compareTo(b.time));

                if (todayDoses.isEmpty) {
                  return _buildEmptyScheduleState();
                }

                return FutureBuilder<DatabaseEvent>(
                    future: _historyRef.once(),
                    builder: (context, historySnapshot) {
                      final historyMap = historySnapshot.data?.snapshot.value as Map<dynamic, dynamic>? ?? {};

                      List<Map<String, dynamic>> processedDoses = [];
                      DateTime now = DateTime.now();
                      int takenCount = 0;

                      for (var dose in todayDoses) {
                        final String safeName = dose.name.replaceAll(' ', '_');
                        final String doseKey = "${safeName}_${dose.time.replaceAll(":", "")}";
                        String status = historyMap[doseKey]?['status']?.toString() ?? 'pending';

                        if (status == 'pending') {
                          try {
                            final timeParts = dose.time.split(':');
                            final scheduledTime = DateTime(
                              now.year, now.month, now.day,
                              int.parse(timeParts[0]), int.parse(timeParts[1]),
                            );
                            if (scheduledTime.isBefore(now)) {
                              status = 'missed';
                            }
                          } catch (e) {
                            // Leave as pending
                          }
                        }

                        if (status == 'taken') takenCount++;
                        processedDoses.add({'dose': dose, 'status': status});
                      }

                      int nextDoseIndex = processedDoses.indexWhere((d) => d['status'] == 'pending');
                      List<Widget> scheduleWidgets = [];

                      // 1. Hero "Next Dose" Card
                      if (nextDoseIndex != -1) {
                        scheduleWidgets.add(_buildNextDoseCard(processedDoses[nextDoseIndex]['dose']));
                        scheduleWidgets.add(const SizedBox(height: 40));
                      }

                      // 2. Daily Log Section
                      bool hasOtherDoses = processedDoses.length > (nextDoseIndex != -1 ? 1 : 0);

                      if (hasOtherDoses) {
                        scheduleWidgets.add(
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Daily Log',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Constants.darkGrey,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Text(
                                  '$takenCount / ${processedDoses.length} Taken',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Constants.mediumGrey,
                                  ),
                                ),
                              ],
                            )
                        );
                        scheduleWidgets.add(const SizedBox(height: 20));

                        List<Map<String, dynamic>> timelineDoses = List.from(processedDoses);
                        if (nextDoseIndex != -1) {
                          timelineDoses.removeAt(nextDoseIndex);
                        }

                        for (int i = 0; i < timelineDoses.length; i++) {
                          scheduleWidgets.add(_buildDailyLogCard(
                            timelineDoses[i]['dose'],
                            timelineDoses[i]['status'],
                          ));
                        }
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: scheduleWidgets,
                      );
                    });
              },
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildEmptyScheduleState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.task_alt_rounded, size: 40, color: Color(0xFF1E88E5)),
          ),
          const SizedBox(height: 24),
          Text(
            "All Clear!",
            style: TextStyle(
                color: Constants.darkGrey,
                fontSize: 22,
                fontWeight: FontWeight.w800
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "No active medications scheduled for today.",
            style: TextStyle(color: Constants.mediumGrey, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}