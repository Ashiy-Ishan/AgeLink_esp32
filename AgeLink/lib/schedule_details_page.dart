// lib/schedule_details_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'constants.dart';
import 'gradient_scaffold.dart';
import 'edit_full_schedule_page.dart';

class ScheduleDetailsPage extends StatelessWidget {
  final String scheduleId;
  final String scheduleName;
  final Timestamp? createdAt;
  final bool isActive;
  final List<Map<String, dynamic>> medications;

  const ScheduleDetailsPage({
    super.key,
    required this.scheduleId,
    required this.scheduleName,
    required this.createdAt,
    required this.isActive,
    required this.medications,
  });

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

  // --- SIMPLE UI: Clean Medication Card ---
  Widget _buildMedicationRow(Map<String, dynamic> med) {
    final name = med['name'] ?? 'Unknown';
    final dosage = med['dosage'] ?? 'N/A';
    final time = med['time'] ?? '00:00';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Time Block
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _formatTime12h(time),
              style: TextStyle(
                color: Constants.darkGrey,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Medication Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Constants.darkGrey,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.medication_liquid_rounded, size: 14, color: Constants.mediumGrey),
                    const SizedBox(width: 4),
                    Text(
                      'Dosage: $dosage',
                      style: TextStyle(
                        color: Constants.mediumGrey,
                        fontSize: 14,
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

                // --- HEADER: Name and Status Inline ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        scheduleName,
                        style: TextStyle(
                          color: Constants.darkGrey,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF4CAF50).withValues(alpha: 0.1)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isActive ? Icons.verified_rounded : Icons.history_rounded,
                            size: 16,
                            color: isActive ? const Color(0xFF4CAF50) : Constants.mediumGrey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isActive ? 'ACTIVE' : 'PAST',
                            style: TextStyle(
                              color: isActive ? const Color(0xFF4CAF50) : Constants.mediumGrey,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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

                // Meds List
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
                    return _buildMedicationRow(sortedMeds[index]);
                  }),
              ],
            ),
          ),

          // Custom Floating Action Button Layer
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