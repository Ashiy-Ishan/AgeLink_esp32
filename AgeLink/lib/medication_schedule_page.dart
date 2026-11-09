import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'constants.dart';
import 'add_full_schedule_page.dart' hide kPrimaryGradient, kGreenGradient;
import 'schedule_details_page.dart';

class MedicationSchedulePage extends StatefulWidget {
  const MedicationSchedulePage({super.key});

  @override
  State<MedicationSchedulePage> createState() => _MedicationSchedulePageState();
}

class _MedicationSchedulePageState extends State<MedicationSchedulePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  late final Stream<QuerySnapshot> _schedulesStream;

  @override
  void initState() {
    super.initState();
    if (_currentUser != null) {
      _schedulesStream = _firestore
          .collection('users/${_currentUser.uid}/medicationSchedules')
          .orderBy('isActive', descending: true)
          .orderBy('createdAt', descending: true)
          .snapshots();
    } else {
      _schedulesStream = const Stream.empty();
    }
  }

  void _navigateToAddSchedule() {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AddFullSchedulePage()));
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown Date';
    return DateFormat('MMM d, yyyy • h:mm a').format(timestamp.toDate());
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 38),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Constants.darkblue.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(22)),
            child: Icon(Icons.calendar_month_rounded, color: Constants.darkblue, size: 34),
          ),
          const SizedBox(height: 20),
          Text('No schedules yet', style: TextStyle(color: Constants.darkGrey, fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Create a medication schedule to keep your loved one’s routine organized.', textAlign: TextAlign.center, style: TextStyle(color: Constants.mediumGrey, fontSize: 14, height: 1.5)),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _navigateToAddSchedule,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create Schedule'),
              style: ElevatedButton.styleFrom(backgroundColor: Constants.darkblue, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(List<QueryDocumentSnapshot> docs) {
    final activeCount = docs.where((doc) => (doc.data() as Map<String, dynamic>)['isActive'] == true).length;
    final totalMedications = docs.fold<int>(0, (value, doc) {
      final data = doc.data() as Map<String, dynamic>;
      return value + ((data['medications'] as List<dynamic>?)?.length ?? 0);
    });
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: kPrimaryGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.16), blurRadius: 18, offset: const Offset(0, 7))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [Icon(Icons.health_and_safety_outlined, color: Colors.white, size: 19), SizedBox(width: 8), Text('Medication plan overview', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))]),
          const SizedBox(height: 19),
          Row(
            children: [
              _summaryValue('${docs.length}', 'Schedules'),
              Container(height: 40, width: 1, color: Colors.white.withValues(alpha: 0.28)),
              _summaryValue('$activeCount', 'Active'),
              Container(height: 40, width: 1, color: Colors.white.withValues(alpha: 0.28)),
              _summaryValue('$totalMedications', 'Medicines'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryValue(String value, String label) {
    return Expanded(child: Column(children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)), const SizedBox(height: 2), Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12))]));
  }

  Widget _buildScheduleCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final scheduleName = data['scheduleName'] ?? 'Unnamed Schedule';
    final createdAt = data['createdAt'] as Timestamp?;
    final medications = (data['medications'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final bool isActive = data['isActive'] ?? false;
    final pillCount = medications.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? Constants.darkblue.withValues(alpha: 0.25) : Constants.darkblue.withValues(alpha: 0.06), width: isActive ? 1.5 : 1),
        boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.045), blurRadius: 16, offset: const Offset(0, 5))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => ScheduleDetailsPage(scheduleId: doc.id, scheduleName: scheduleName, createdAt: createdAt, isActive: isActive, medications: medications)));
          },
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: isActive ? Constants.lightBlue : const Color(0xFFF2F4F7), borderRadius: BorderRadius.circular(15)),
                  child: Icon(isActive ? Icons.event_available_rounded : Icons.event_note_rounded, color: isActive ? Constants.darkblue : Constants.mediumGrey, size: 24),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(scheduleName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Constants.darkGrey, fontSize: 17, fontWeight: FontWeight.w800))),
                        if (isActive) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: Constants.greenColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: Text('ACTIVE', style: TextStyle(color: Constants.greenColor, fontSize: 10, fontWeight: FontWeight.w800))),
                      ]),
                      const SizedBox(height: 9),
                      Row(children: [Icon(Icons.medication_outlined, color: Constants.darkblue, size: 16), const SizedBox(width: 5), Text('$pillCount medication${pillCount == 1 ? '' : 's'}', style: TextStyle(color: Constants.darkblue, fontWeight: FontWeight.w700, fontSize: 13))]),
                      const SizedBox(height: 7),
                      Text('Created ${_formatTimestamp(createdAt)}', style: TextStyle(color: Constants.mediumGrey, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Padding(padding: const EdgeInsets.only(top: 12), child: Icon(Icons.chevron_right_rounded, color: Constants.mediumGrey, size: 23)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) return const Center(child: Text('Please log in to manage schedules.'));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddSchedule,
        backgroundColor: Constants.darkblue,
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Schedule', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _schedulesStream,
        builder: (context, snapshot) {
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 115),
            children: [
              Text('Medication Schedules', style: TextStyle(color: Constants.darkGrey, fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text('Manage medication routines for your loved ones.', style: TextStyle(color: Constants.mediumGrey, fontSize: 14)),
              const SizedBox(height: 22),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                Padding(padding: const EdgeInsets.all(22), child: Text('Error loading schedules.', style: TextStyle(color: Constants.mediumGrey)))
              else if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                  _buildEmptyState()
                else ...[
                    _buildSummary(snapshot.data!.docs),
                    const SizedBox(height: 25),
                    Row(children: [Expanded(child: Text('Your schedules', style: TextStyle(color: Constants.darkGrey, fontSize: 19, fontWeight: FontWeight.w800))), Text('${snapshot.data!.docs.length} total', style: TextStyle(color: Constants.mediumGrey, fontSize: 13, fontWeight: FontWeight.w600))]),
                    const SizedBox(height: 13),
                    ...snapshot.data!.docs.map(_buildScheduleCard),
                  ],
            ],
          );
        },
      ),
    );
  }
}
