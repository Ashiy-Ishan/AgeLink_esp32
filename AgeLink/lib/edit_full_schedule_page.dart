// lib/edit_full_schedule_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'constants.dart';
import 'gradient_scaffold.dart';
import 'custom_snackbar.dart';

const kPrimaryGradient = LinearGradient(
  colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);
const kRedGradient = LinearGradient(
  colors: [Color(0xFFEF5350), Color(0xFFD32F2F)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

class EditFullSchedulePage extends StatefulWidget {
  final String scheduleId;
  final String initialScheduleName;
  final List<Map<String, dynamic>> initialMedications;
  final bool isActive;

  const EditFullSchedulePage({
    super.key,
    required this.scheduleId,
    required this.initialScheduleName,
    required this.initialMedications,
    required this.isActive,
  });

  @override
  State<EditFullSchedulePage> createState() => _EditFullSchedulePageState();
}

class _EditFullSchedulePageState extends State<EditFullSchedulePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late List<Map<String, dynamic>> _medications;
  bool _isLoading = false;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialScheduleName);
    // Deep copy the medications to avoid mutating the original list
    _medications = List.from(widget.initialMedications.map((med) => Map<String, dynamic>.from(med)));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // --- Dynamic Medication Management ---
  void _addNewMedication() {
    setState(() {
      _medications.add({
        'name': '',
        'dosage': '',
        'time': '08:00',
      });
    });
  }

  void _removeMedication(int index) {
    setState(() {
      _medications.removeAt(index);
    });
  }

  Future<void> _selectTime(BuildContext context, int index) async {
    // Safely parse the time with a fallback
    final timeStr = _medications[index]['time']?.toString() ?? '08:00';
    final parts = timeStr.split(':');
    TimeOfDay initialTime = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 8,
        minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0
    );

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1E88E5),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        final String hour = picked.hour.toString().padLeft(2, '0');
        final String minute = picked.minute.toString().padLeft(2, '0');
        _medications[index]['time'] = '$hour:$minute';
      });
    }
  }

  // --- Firestore Logic ---
  Future<void> _updateSchedule() async {
    if (!_formKey.currentState!.validate()) return;

    if (_medications.isEmpty) {
      CustomSnackBar.show(context: context, message: 'Please add at least one medication.', isError: true);
      return;
    }

    setState(() { _isLoading = true; });

    try {
      if (_currentUser == null) throw Exception("User not logged in");

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('medicationSchedules')
          .doc(widget.scheduleId)
          .update({
        'scheduleName': _nameController.text.trim(),
        'medications': _medications,
      });

      if (mounted) {
        CustomSnackBar.show(context: context, message: 'Schedule updated successfully!');
        Navigator.pop(context); // Pop details page
        Navigator.pop(context); // Pop list page
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(context: context, message: 'Failed to update schedule: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _deleteSchedule() async {
    setState(() { _isLoading = true; });

    try {
      if (_currentUser == null) throw Exception("User not logged in");

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('medicationSchedules')
          .doc(widget.scheduleId)
          .delete();

      if (mounted) {
        CustomSnackBar.show(context: context, message: 'Schedule deleted.');
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(context: context, message: 'Failed to delete: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
              const SizedBox(width: 10),
              const Text('Delete Schedule?'),
            ],
          ),
          content: Text(
            'Are you sure you want to permanently delete "${_nameController.text}" and all its medications?',
            style: TextStyle(color: Constants.darkGrey, fontSize: 16),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Constants.mediumGrey,
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteSchedule();
              },
            ),
          ],
        );
      },
    );
  }

  // --- Styled UI Components ---
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
            child: (icon != null)
                ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
              ],
            )
                : Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    TextEditingController? controller,
    String? initialValue,
    void Function(String)? onChanged,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        initialValue: initialValue,
        onChanged: onChanged,
        validator: validator,
        style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Constants.mediumGrey),
          prefixIcon: Icon(icon, color: const Color(0xFF1E88E5)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text(
          'Edit Schedule',
          style: TextStyle(color: Color(0xFF0D47A1), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Constants.darkblue),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Schedule Overview ---
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Schedule Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
              ),
              _buildInputField(
                controller: _nameController,
                label: 'Schedule Name (e.g., Morning Routine)',
                icon: Icons.edit_calendar_rounded,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 32),

              // --- Medications List ---
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Medications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _addNewMedication,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.add_rounded, color: Color(0xFF1E88E5), size: 20),
                              const SizedBox(width: 4),
                              const Text('Add Pill', style: TextStyle(color: Color(0xFF1E88E5), fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              ...List.generate(_medications.length, (index) {
                // Safely extract variables to prevent Null type errors
                final String currentName = _medications[index]['name']?.toString() ?? '';
                final String currentDosage = _medications[index]['dosage']?.toString() ?? '';
                final String currentTime = _medications[index]['time']?.toString() ?? '00:00';

                return Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Pill ${index + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E88E5)),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                            onPressed: () => _removeMedication(index),
                            splashRadius: 24,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInputField(
                        initialValue: currentName,
                        onChanged: (val) => _medications[index]['name'] = val,
                        label: 'Medicine Name',
                        icon: Icons.medication_rounded,
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      _buildInputField(
                        initialValue: currentDosage,
                        onChanged: (val) => _medications[index]['dosage'] = val,
                        label: 'Dosage (e.g., 2 Pills)',
                        icon: Icons.scale_rounded,
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Styled Time Selector
                      InkWell(
                        onTap: () => _selectTime(context, index),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF1E88E5).withValues(alpha: 0.3), width: 1.5),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.access_time_rounded, color: Color(0xFF1E88E5), size: 22),
                                  const SizedBox(width: 12),
                                  const Text('Time', style: TextStyle(color: Color(0xFF1E88E5), fontSize: 16, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              Text(
                                  currentTime,
                                  style: const TextStyle(color: Color(0xFF1E88E5), fontSize: 18, fontWeight: FontWeight.bold)
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 24),

              // --- Action Buttons ---
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                children: [
                  _buildGradientButton(
                    onPressed: _updateSchedule,
                    text: 'Save Changes',
                    icon: Icons.save_rounded,
                    gradient: kPrimaryGradient,
                  ),
                  const SizedBox(height: 16),
                  _buildGradientButton(
                    onPressed: _showDeleteConfirmation,
                    text: 'Delete Schedule',
                    icon: Icons.delete_outline_rounded,
                    gradient: kRedGradient,
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}