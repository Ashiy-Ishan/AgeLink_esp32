import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'constants.dart';
import 'pair_device_page.dart' hide kPrimaryGradient;

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
        databaseURL: 'https://agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app',
      );
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

  BoxDecoration _surface({double radius = 22}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Constants.darkblue.withValues(alpha: 0.07)),
      boxShadow: [
        BoxShadow(
          color: Constants.darkblue.withValues(alpha: 0.045),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Widget _sectionHeading(String title, {String? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: Constants.darkGrey,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: TextStyle(
              color: Constants.mediumGrey,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _buildWelcome() {
    String firstName = '';
    if (_currentUser!.displayName != null &&
        _currentUser!.displayName!.trim().isNotEmpty) {
      firstName = _currentUser!.displayName!.trim().split(' ').first;
    }
    final greeting = firstName.isNotEmpty ? 'Hello, $firstName' : 'Hello';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: TextStyle(
            fontSize: 15,
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
            letterSpacing: -0.85,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'A little care makes every day better.',
          style: TextStyle(fontSize: 13.5, color: Constants.mediumGrey),
        ),
      ],
    );
  }

  Widget _buildDeviceCard() {
    return StreamBuilder<DatabaseEvent>(
      stream: _deviceRef.onValue,
      builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 82,
            decoration: _surface(),
            alignment: Alignment.center,
            child: CircularProgressIndicator(color: Constants.darkblue),
          );
        }

        if (snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data!.snapshot.value == null) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PairDevicePage(),
                  ),
                );
              },
              child: Ink(
                decoration: BoxDecoration(
                  gradient: kPrimaryGradient,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Constants.darkblue.withValues(alpha: 0.13),
                      blurRadius: 15,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.devices_rounded, size: 25, color: Colors.white),
                      ),
                      const SizedBox(width: 13),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connect your device',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Pair your AgeLink reminder',
                              style: TextStyle(color: Colors.white, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final deviceData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
        final bool isOnline = deviceData['device_active'] == true;
        final statusColor = isOnline ? Constants.greenColor : Constants.redColor;

        return Container(
          decoration: _surface(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  color: statusColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOnline ? 'Device connected' : 'Device offline',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Constants.darkGrey,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isOnline ? "Ready for today's schedule" : 'Please check connection',
                      style: TextStyle(color: Constants.mediumGrey, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetric(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w800, fontSize: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(color: Constants.mediumGrey, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _buildDailySummary(int total, int taken, int missed) {
    final double progress = total == 0 ? 0 : taken / total;
    return Container(
      decoration: _surface(),
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Constants.lightBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.insights_rounded, color: Constants.darkblue, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Today's overview",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Constants.darkGrey),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Constants.darkblue),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Constants.lightBlue,
              valueColor: AlwaysStoppedAnimation<Color>(Constants.darkblue),
            ),
          ),
          const SizedBox(height: 19),
          Row(
            children: [
              _buildMetric('Scheduled', '$total', Icons.calendar_today_rounded, Constants.darkblue),
              Container(height: 39, width: 1, color: Constants.lightBlue),
              const SizedBox(width: 12),
              _buildMetric('Taken', '$taken', Icons.check_circle_rounded, Constants.greenColor),
              Container(height: 39, width: 1, color: Constants.lightBlue),
              const SizedBox(width: 12),
              _buildMetric('Missed', '$missed', Icons.error_outline_rounded, Constants.redColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNextDoseCard(_TodayDose dose) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: kPrimaryGradient,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Constants.darkblue.withValues(alpha: 0.17),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Stack(
          children: [
            Positioned(
              top: -62,
              right: -54,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.075)),
              ),
            ),
            Positioned(
              bottom: -85,
              right: 30,
              child: Container(
                width: 145,
                height: 145,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.045)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.17),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_active_outlined, size: 15, color: Colors.white),
                            SizedBox(width: 7),
                            Text(
                              'NEXT MEDICATION',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.6),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.medication_liquid_outlined, color: Colors.white.withValues(alpha: 0.85), size: 28),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    _formatTime12h(dose.time),
                    style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -1.2, color: Colors.white),
                  ),
                  const SizedBox(height: 17),
                  Container(height: 1, color: Colors.white.withValues(alpha: 0.22)),
                  const SizedBox(height: 16),
                  Text(
                    dose.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.medication_rounded, size: 17, color: Colors.white.withValues(alpha: 0.9)),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Dosage: ${dose.dosage}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.92)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
      statusColor = Constants.redColor;
      bgColor = Constants.redColor.withValues(alpha: 0.1);
      statusText = 'Missed';
      statusIcon = Icons.error_rounded;
    } else {
      statusColor = Constants.darkblue;
      bgColor = Constants.lightBlue;
      statusText = 'Pending';
      statusIcon = Icons.schedule_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: _surface(radius: 19),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 51,
            height: 51,
            decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(15)),
            child: Icon(Icons.medication_outlined, color: Constants.darkblue, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dose.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Constants.darkGrey, fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_formatTime12h(dose.time)}  ·  ${dose.dosage}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Constants.mediumGrey, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(15)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: statusColor, size: 13),
                const SizedBox(width: 4),
                Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyScheduleState() {
    return Container(
      width: double.infinity,
      decoration: _surface(),
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 22),
      child: Column(
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(20)),
            child: Icon(Icons.event_available_rounded, color: Constants.darkblue, size: 33),
          ),
          const SizedBox(height: 17),
          Text('No medications scheduled', style: TextStyle(color: Constants.darkGrey, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'When a medication is scheduled, its next dose and daily status will appear here.',
            style: TextStyle(color: Constants.mediumGrey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcome(),
          const SizedBox(height: 24),
          _sectionHeading('AgeLink device'),
          const SizedBox(height: 12),
          _buildDeviceCard(),
          const SizedBox(height: 26),
          StreamBuilder<DatabaseEvent>(
            stream: _medsRef.onValue,
            builder: (context, scheduleSnapshot) {
              if (scheduleSnapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
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
                    final String doseKey = '${safeName}_${dose.time.replaceAll(':', '')}';
                    String status = historyMap[doseKey]?['status']?.toString() ?? 'pending';

                    if (status == 'pending') {
                      try {
                        final timeParts = dose.time.split(':');
                        final scheduledTime = DateTime(
                          now.year,
                          now.month,
                          now.day,
                          int.parse(timeParts[0]),
                          int.parse(timeParts[1]),
                        );
                        if (scheduledTime.isBefore(now)) {
                          status = 'missed';
                        }
                      } catch (e) {}
                    }

                    if (status == 'taken') takenCount++;
                    processedDoses.add({'dose': dose, 'status': status});
                  }

                  int nextDoseIndex = processedDoses.indexWhere((d) => d['status'] == 'pending');
                  List<Widget> scheduleWidgets = [];
                  final missedCount = processedDoses.where((d) => d['status'] == 'missed').length;

                  scheduleWidgets.add(_sectionHeading('Medication overview'));
                  scheduleWidgets.add(const SizedBox(height: 12));
                  scheduleWidgets.add(_buildDailySummary(processedDoses.length, takenCount, missedCount));
                  scheduleWidgets.add(const SizedBox(height: 25));

                  if (nextDoseIndex != -1) {
                    scheduleWidgets.add(_sectionHeading('Up next'));
                    scheduleWidgets.add(const SizedBox(height: 12));
                    scheduleWidgets.add(_buildNextDoseCard(processedDoses[nextDoseIndex]['dose']));
                    scheduleWidgets.add(const SizedBox(height: 26));
                  }

                  bool hasOtherDoses = processedDoses.length > (nextDoseIndex != -1 ? 1 : 0);

                  if (hasOtherDoses) {
                    scheduleWidgets.add(_sectionHeading('Daily log', trailing: '$takenCount of ${processedDoses.length} taken'));
                    scheduleWidgets.add(const SizedBox(height: 12));

                    List<Map<String, dynamic>> timelineDoses = List.from(processedDoses);
                    if (nextDoseIndex != -1) {
                      timelineDoses.removeAt(nextDoseIndex);
                    }

                    for (int i = 0; i < timelineDoses.length; i++) {
                      scheduleWidgets.add(
                        _buildDailyLogCard(timelineDoses[i]['dose'], timelineDoses[i]['status']),
                      );
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: scheduleWidgets,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
