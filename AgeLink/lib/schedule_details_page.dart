// lib/schedule_details_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'constants.dart';
import 'gradient_scaffold.dart';
import 'edit_full_schedule_page.dart'; // Make sure you created this file from the previous step

class ScheduleDetailsPage extends StatelessWidget {
  final String scheduleId; // <-- DEFINED HERE
  final String scheduleName;
  final Timestamp? createdAt;
  final bool isActive;
  final List<Map<String, dynamic>> medications;

  const ScheduleDetailsPage({
    super.key,
    required this.scheduleId, // <-- ADDED TO CONSTRUCTOR
    required this.scheduleName,
    required this.createdAt,
    required this.isActive,
    required this.medications,
  });

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
    // Navigates to the Edit Page passing all current data
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => EditFullSchedulePage(
              scheduleId: scheduleId,
              initialScheduleName: scheduleName,
              initialMedications: medications,
              isActive: isActive,
            )
        )
    );
  }

  // --- MODERN UI: Fluid Timeline Row (Zero Boxes) ---
  Widget _buildTimelineMedRow(Map<String, dynamic> med, bool isLast, BuildContext context) {
    final name = med['name'] ?? 'Unknown';
    final dosage = med['dosage'] ?? 'N/A';
    final time = med['time'] ?? '00:00';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Side: Time
          SizedBox(
            width: 75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatTime12h(time),
                  style: const TextStyle(
                    color: Color(0xFF1E88E5),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Timeline Node & Line
          Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFF1E88E5), width: 3.5),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E88E5).withValues(alpha: 0.4),
                        blurRadius: 8,
                      )
                    ]
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: const Color(0xFF1E88E5).withValues(alpha: 0.2),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),

          // Right Side: Medication Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 19,
                      color: Constants.darkGrey,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.medication_liquid_rounded, size: 16, color: Constants.mediumGrey),
                      const SizedBox(width: 6),
                      Text(
                        'Dosage: $dosage',
                        style: TextStyle(
                          color: Constants.mediumGrey,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedMeds = List<Map<String, dynamic>>.from(medications);
    sortedMeds.sort((a, b) {
      String timeA = a['time'] ?? '00:00';
      String timeB = b['time'] ?? '00:00';
      return timeA.compareTo(timeB);
    });

    return GradientScaffold(
      appBar: AppBar(
        title: const Text(
          'Schedule Details',
          style: TextStyle(color: Color(0xFF0D47A1), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Constants.darkblue),
        centerTitle: true,
      ),

      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 16.0, bottom: 100.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Overview Hero Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isActive
                          ? [const Color(0xFF4CAF50), const Color(0xFF2E7D32)]
                          : [Constants.darkblue.withValues(alpha: 0.7), Constants.darkblue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: (isActive ? const Color(0xFF4CAF50) : Constants.darkblue).withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(
                              isActive ? Icons.verified_rounded : Icons.history_rounded,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: 36
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isActive ? 'ACTIVE' : 'PAST',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        scheduleName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Created ${_formatTimestamp(createdAt)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Meds Header
                Row(
                  children: [
                    Icon(Icons.medication_rounded, color: Constants.darkGrey, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Medications (${sortedMeds.length})',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Constants.darkGrey,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Meds Timeline List
                if (sortedMeds.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0),
                    child: Text(
                      'No medications were added to this schedule.',
                      style: TextStyle(color: Constants.mediumGrey, fontStyle: FontStyle.italic, fontSize: 16),
                    ),
                  )
                else
                  ...List.generate(sortedMeds.length, (index) {
                    return _buildTimelineMedRow(
                        sortedMeds[index],
                        index == sortedMeds.length - 1,
                        context
                    );
                  }),
              ],
            ),
          ),

          // 2. The Custom Floating Action Button Layer
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E88E5).withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FloatingActionButton(
                onPressed: () => _navigateToEditSchedule(context),
                backgroundColor: Colors.transparent,
                elevation: 0,
                highlightElevation: 0,
                child: const Icon(Icons.edit_rounded, color: Colors.white, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }
}