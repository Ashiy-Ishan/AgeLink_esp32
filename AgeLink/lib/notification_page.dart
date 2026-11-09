import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'constants.dart';

class DoseNotification {
  final String docId;
  final String medicationName;
  final String time;
  final DateTime date;
  final bool isTaken;
  final String reminderState;

  DoseNotification({
    required this.docId,
    required this.medicationName,
    required this.time,
    required this.date,
    required this.isTaken,
    required this.reminderState,
  });

  factory DoseNotification.fromRTDB(DataSnapshot snapshot) {
    final data = Map<String, dynamic>.from(snapshot.value as Map);

    DateTime doseDate = DateTime.now();
    if (data['date'] != null && data['date'] is int) {
      doseDate = DateTime.fromMillisecondsSinceEpoch(data['date']);
    } else if (data['confirmed_at_timestamp'] != null && data['confirmed_at_timestamp'] is int) {
      doseDate = DateTime.fromMillisecondsSinceEpoch(data['confirmed_at_timestamp']);
    }

    String state = (data['reminder_state'] ?? 'Missed').toString();
    String medName = (data['medicine_name'] ?? 'Unknown Medication').toString();
    String confirmedAt = (data['confirmed_at'] ?? 'N/A').toString();
    bool taken = (state == 'Green' || state == 'Orange' || state == 'Red');

    return DoseNotification(
      docId: snapshot.key ?? '',
      medicationName: medName,
      time: confirmedAt,
      date: doseDate,
      isTaken: taken,
      reminderState: state,
    );
  }
}

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  final String? userId = FirebaseAuth.instance.currentUser?.uid;
  DatabaseReference? _alertsRef;

  @override
  void initState() {
    super.initState();
    if (userId != null) {
      _alertsRef = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: "https://agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app"
      ).ref('reminders/$userId/confirmation');
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final doseDay = DateTime(date.year, date.month, date.day);

    if (doseDay.isAtSameMomentAs(today)) return 'Today';
    if (doseDay.isAtSameMomentAs(yesterday)) return 'Yesterday';
    return DateFormat('MMMM d, yyyy').format(date);
  }

  Widget _buildDateHeader(DateTime date) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: Constants.darkblue,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _formatDate(date),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Constants.darkGrey,
              ),
            ),
          ),
          Icon(Icons.calendar_today_rounded, size: 16, color: Constants.mediumGrey),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      children: [
        _buildHeading(),
        const SizedBox(height: 34),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 46),
          decoration: _surfaceDecoration(),
          child: Column(
            children: [
              Container(
                height: 78,
                width: 78,
                decoration: BoxDecoration(
                  color: Constants.lightBlue,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.notifications_none_rounded, size: 40, color: Constants.darkblue),
              ),
              const SizedBox(height: 20),
              Text(
                'No alerts yet',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Constants.darkGrey),
              ),
              const SizedBox(height: 10),
              Text(
                'Medication confirmations and missed-dose records will appear here when available.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5, color: Constants.mediumGrey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _surfaceDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Constants.darkblue.withValues(alpha: 0.07)),
      boxShadow: [
        BoxShadow(
          color: Constants.darkblue.withValues(alpha: 0.07),
          blurRadius: 18,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }

  Widget _buildHeading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notifications',
          style: TextStyle(
            color: Constants.darkGrey,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Keep track of medication confirmations and missed doses.',
          style: TextStyle(color: Constants.mediumGrey, fontSize: 13.5, height: 1.35),
        ),
      ],
    );
  }

  Widget _buildSummary(List<DoseNotification> alerts) {
    final takenCount = alerts.where((a) => a.isTaken).length;
    final missedCount = alerts.length - takenCount;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Constants.darkblue.withValues(alpha: 0.17),
            blurRadius: 17,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 19, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: Colors.white, size: 19),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Medication activity',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'All records',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildSummaryMetric('${alerts.length}', 'Records', Icons.receipt_long_rounded),
              Container(width: 1, height: 42, color: Colors.white.withValues(alpha: 0.25)),
              _buildSummaryMetric('$takenCount', 'Taken', Icons.check_circle_outline_rounded),
              Container(width: 1, height: 42, color: Colors.white.withValues(alpha: 0.25)),
              _buildSummaryMetric('$missedCount', 'Missed', Icons.error_outline_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric(String value, String label, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.88), size: 13),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.94), fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(DoseNotification notification) {
    final Color statusColor = notification.isTaken ? Constants.greenColor : Constants.redColor;
    final Color bgColor = statusColor.withValues(alpha: 0.11);
    final IconData statusIcon = notification.isTaken ? Icons.check_circle_rounded : Icons.error_rounded;
    final String statusText = notification.isTaken ? 'Taken (${notification.reminderState})' : 'Missed';

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: _surfaceDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14)),
              child: Icon(statusIcon, color: statusColor, size: 25),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.medicationName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(9)),
                    child: Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded, size: 14, color: Constants.mediumGrey),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          notification.time,
                          style: TextStyle(color: Constants.mediumGrey, fontSize: 13, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
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

  @override
  Widget build(BuildContext context) {
    if (userId == null) return const Center(child: Text("Please log in to view alerts.", style: TextStyle(fontSize: 18)));
    if (_alertsRef == null) return const Center(child: Text("Error: Alerts collection path is invalid.", style: TextStyle(fontSize: 18)));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StreamBuilder<DatabaseEvent>(
        stream: _alertsRef!.orderByChild('date').onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Error loading alerts: ${snapshot.error}'));

          final List<DoseNotification> alerts = [];
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            for (final child in snapshot.data!.snapshot.children) {
              try { alerts.add(DoseNotification.fromRTDB(child)); } catch (e) { debugPrint('Error parsing notification: $e'); }
            }
            alerts.sort((a, b) => b.date.compareTo(a.date));
          }

          if (alerts.isEmpty) return _buildEmptyState();

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 15, 22, 26),
            itemCount: alerts.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeading(),
                    const SizedBox(height: 19),
                    _buildSummary(alerts),
                    const SizedBox(height: 8),
                  ],
                );
              }

              final notification = alerts[index - 1];
              final DateTime currentDoseDate = DateTime(notification.date.year, notification.date.month, notification.date.day);

              bool showDateHeader = true;
              if (index > 1) {
                final previousNotification = alerts[index - 2];
                final DateTime previousDoseDate = DateTime(previousNotification.date.year, previousNotification.date.month, previousNotification.date.day);
                if (currentDoseDate.isAtSameMomentAs(previousDoseDate)) showDateHeader = false;
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showDateHeader) _buildDateHeader(notification.date),
                  _buildAlertCard(notification),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
