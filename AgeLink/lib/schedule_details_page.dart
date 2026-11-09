import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'constants.dart';
import 'gradient_scaffold.dart';
import 'edit_full_schedule_page.dart' hide kPrimaryGradient, kRedGradient;

class ScheduleDetailsPage extends StatelessWidget {
  final String scheduleId;
  final String scheduleName;
  final Timestamp? createdAt;
  final bool isActive;
  final List medications;

  const ScheduleDetailsPage({super.key, required this.scheduleId, required this.scheduleName, required this.createdAt, required this.isActive, required this.medications});

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown Date';
    return DateFormat('MMMM d, yyyy • h:mm a').format(timestamp.toDate());
  }

  String _formatTime12h(String time24h) {
    try {
      final parts = time24h.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final String ampm = hour >= 12 ? 'PM' : 'AM';
      final int hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      final String minStr = minute.toString().padLeft(2, '0');
      return '$hour12:$minStr $ampm';
    } catch (e) {
      return time24h;
    }
  }

  void _navigateToEditSchedule(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => EditFullSchedulePage(scheduleId: scheduleId, initialScheduleName: scheduleName, initialMedications: medications, isActive: isActive)));
  }

  Widget _buildMedicationRow(Map med, int index) {
    final name = med['name']?.toString() ?? 'Unknown';
    final dosage = med['dosage']?.toString() ?? 'N/A';
    List times = [];
    if (med['times'] != null && med['times'] is List) {
      times = List.from(med['times']);
    } else if (med['time'] != null) {
      times = [med['time'].toString()];
    } else {
      times = ['00:00'];
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Constants.darkblue.withValues(alpha: 0.07)),
        boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.045), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(13)), child: Icon(Icons.medication_outlined, color: Constants.darkblue, size: 23)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(color: Constants.darkGrey, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Dosage: $dosage', style: TextStyle(color: Constants.mediumGrey, fontSize: 13)),
              ])),
              Text('#${index + 1}', style: TextStyle(color: Constants.mediumGrey, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 15),
          Text('REMINDER TIMES', style: TextStyle(color: Constants.mediumGrey, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.7)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: times.map((time) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(11)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.schedule_rounded, size: 16, color: Constants.darkblue), const SizedBox(width: 6), Text(_formatTime12h(time.toString()), style: TextStyle(color: Constants.darkblue, fontSize: 13, fontWeight: FontWeight.w700))]),
            )).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: Text('Schedule Details', style: TextStyle(color: Constants.darkblue, fontWeight: FontWeight.w800, fontSize: 19)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Constants.darkblue),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(gradient: kPrimaryGradient, borderRadius: BorderRadius.circular(23), boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.17), blurRadius: 18, offset: const Offset(0, 8))]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [Icon(Icons.event_note_rounded, color: Colors.white.withValues(alpha: 0.94), size: 23), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(9)), child: Text(isActive ? 'ACTIVE SCHEDULE' : 'PAST SCHEDULE', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)))]),
                      const SizedBox(height: 18),
                      Text(scheduleName, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 9),
                      Text('Created ${_formatTimestamp(createdAt)}', style: TextStyle(color: Colors.white.withValues(alpha: 0.87), fontSize: 12)),
                      const SizedBox(height: 21),
                      Row(children: [Icon(Icons.medication_rounded, color: Colors.white.withValues(alpha: 0.9), size: 18), const SizedBox(width: 7), Text('${medications.length} medication${medications.length == 1 ? '' : 's'} in this plan', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))]),
                    ],
                  ),
                ),
                const SizedBox(height: 27),
                Text('Medication details', style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w800, fontSize: 21)),
                const SizedBox(height: 6),
                Text('Review medicine names, dosages and reminder times.', style: TextStyle(color: Constants.mediumGrey, fontSize: 13)),
                const SizedBox(height: 15),
                if (medications.isEmpty)
                  Container(width: double.infinity, padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Text('No medications were added to this schedule.', style: TextStyle(color: Constants.mediumGrey, fontSize: 15)))
                else
                  ...List.generate(medications.length, (index) {
                    final medObj = medications[index];
                    if (medObj is Map) return _buildMedicationRow(medObj, index);
                    return const SizedBox();
                  }),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            right: 20,
            child: FloatingActionButton.extended(
              heroTag: 'edit_schedule_details',
              onPressed: () => _navigateToEditSchedule(context),
              backgroundColor: Constants.darkblue,
              foregroundColor: Colors.white,
              elevation: 3,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Schedule', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
