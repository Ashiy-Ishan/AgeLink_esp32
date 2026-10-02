// lib/medication_schedule_page.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'constants.dart';
import 'add_full_schedule_page.dart';
import 'schedule_details_page.dart';

const kPrimaryGradient = LinearGradient(
  colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

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
      final String schedulesCollectionPath =
          'users/${_currentUser!.uid}/medicationSchedules';

      _schedulesStream = _firestore
          .collection(schedulesCollectionPath)
          .orderBy('isActive', descending: true)
          .orderBy('createdAt', descending: true)
          .snapshots();
    } else {
      _schedulesStream = const Stream.empty();
    }
  }

  void _navigateToAddSchedule() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AddFullSchedulePage(),
      ),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown Date';
    return DateFormat('MMM d, yyyy • h:mm a').format(timestamp.toDate());
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit_calendar_rounded, size: 56, color: Color(0xFF1E88E5)),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No Schedules Yet',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Constants.darkGrey,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tap the glowing + button below to create your first medication schedule.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Constants.mediumGrey, height: 1.5, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Center(child: Text('Please log in to manage schedules.'));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,

      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 16, right: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: kPrimaryGradient,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: _navigateToAddSchedule,
          backgroundColor: Colors.transparent,
          elevation: 0,
          highlightElevation: 0,
          child: const Icon(Icons.add_rounded, size: 32, color: Colors.white),
        ),
      ),

      body: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                Icon(Icons.edit_calendar_rounded, color: Constants.darkGrey, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Manage Schedules',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Constants.darkGrey,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _schedulesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(
                        'Error loading schedules.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Constants.mediumGrey),
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 100),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;

                    final scheduleName = data['scheduleName'] ?? 'Unnamed Schedule';
                    final createdAt = data['createdAt'] as Timestamp?;
                    final medications = List<Map<String, dynamic>>.from(data['medications'] ?? []);
                    final bool isActive = data['isActive'] ?? false;
                    final pillCount = medications.length;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isActive
                              ? [Colors.white, const Color(0xFFF1F8E9)]
                              : [Colors.white, const Color(0xFFF8F9FA)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isActive ? const Color(0xFF4CAF50).withValues(alpha: 0.4) : Colors.grey.shade200,
                          width: isActive ? 2 : 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isActive ? const Color(0xFF4CAF50) : Colors.black).withValues(alpha: 0.04),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ScheduleDetailsPage(
                                  scheduleId: doc.id,
                                  scheduleName: scheduleName,
                                  createdAt: createdAt,
                                  isActive: isActive,
                                  medications: medications,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Row(
                              children: [
                                // Left Icon/Badge
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                                        : Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: isActive ? [] : [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.04),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      )
                                    ],
                                  ),
                                  child: Icon(
                                    isActive ? Icons.verified_rounded : Icons.history_rounded,
                                    color: isActive ? const Color(0xFF4CAF50) : Constants.mediumGrey,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 16),

                                // Middle Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              scheduleName,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                                color: Constants.darkGrey,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isActive)
                                            Container(
                                              margin: const EdgeInsets.only(left: 8),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: const Text(
                                                'ACTIVE',
                                                style: TextStyle(
                                                  color: Color(0xFF2E7D32),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _formatTimestamp(createdAt),
                                        style: TextStyle(
                                          color: Constants.mediumGrey,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Icon(Icons.medication_liquid_rounded, size: 16, color: Constants.mediumGrey),
                                          const SizedBox(width: 6),
                                          Text(
                                            '$pillCount medication${pillCount == 1 ? '' : 's'}',
                                            style: TextStyle(
                                              color: Constants.darkblue,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Right Chevron
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 28),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}