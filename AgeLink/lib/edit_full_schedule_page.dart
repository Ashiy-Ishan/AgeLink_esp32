import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
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
  final List initialMedications;
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
  late List _medications;
  bool _isLoading = false;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  late final DatabaseReference _remindersRef;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialScheduleName);

    _medications = [];
    for (var med in widget.initialMedications) {
      if (med is Map) {
        final times = [];
        if (med['times'] != null && med['times'] is Iterable) {
          times.addAll(med['times']);
        } else if (med['time'] != null) {
          times.add(med['time']);
        } else {
          times.add('08:00');
        }

        _medications.add({
          'name': med['name']?.toString() ?? '',
          'dosage': med['dosage']?.toString() ?? '',
          'frequency': med['frequency']?.toString() ?? 'Daily',
          'times': times,
        });
      }
    }

    if (_currentUser != null) {
      _remindersRef = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: "https://agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app"
      ).ref('reminders/${_currentUser.uid}');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addNewMedication() {
    setState(() {
      _medications.add({
        'name': '',
        'dosage': '',
        'frequency': 'Daily',
        'times': [],
      });
    });
  }

  void _removeMedication(int index) {
    if (_medications.length > 1) {
      setState(() {
        _medications.removeAt(index);
      });
    }
  }

  Future<void> _addTime(int index) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
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
        final String timeStr = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        final currentTimes = _medications[index]['times'] as List;
        if (!currentTimes.contains(timeStr)) {
          currentTimes.add(timeStr);
          currentTimes.sort();
        }
      });
    }
  }

  void _removeTime(int medIndex, String timeStr) {
    setState(() {
      final currentTimes = _medications[medIndex]['times'] as List;
      currentTimes.remove(timeStr);
    });
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

  Future<void> _updateSchedule() async {
    if (!_formKey.currentState!.validate()) return;

    bool hasValidMed = false;
    for (var med in _medications) {
      final name = med['name']?.toString() ?? '';
      final times = med['times'] as List? ?? [];
      if (name.isNotEmpty && times.isNotEmpty) {
        hasValidMed = true;
        break;
      }
    }

    if (!hasValidMed) {
      CustomSnackBar.show(context: context, message: 'Please add at least one medication with a time.', isError: true);
      return;
    }

    setState(() { _isLoading = true; });

    try {
      if (_currentUser == null) throw Exception("User not logged in");

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser.uid)
          .collection('medicationSchedules')
          .doc(widget.scheduleId)
          .update({
        'scheduleName': _nameController.text.trim(),
        'medications': _medications,
      });

      if (widget.isActive) {
        final rtdbScheduleObject = <String, dynamic>{};
        for (final entry in _medications) {
          final String name = entry['name']?.toString() ?? '';
          final String dosage = entry['dosage']?.toString() ?? '';
          final times = entry['times'] as List? ?? [];

          if (name.isNotEmpty && times.isNotEmpty) {
            for (var t in times) {
              final String timeStr = t.toString();
              final String safeName = name.replaceAll(' ', '_');
              String key = "${safeName}_${timeStr.replaceAll(":", "")}";
              rtdbScheduleObject[key] = {
                'name': name,
                'dosage': dosage,
                'time': timeStr,
              };
            }
          }
        }
        await _remindersRef.child('schedule/med_times').set(rtdbScheduleObject);
        await _remindersRef.child('schedule/current_status').set("IDLE");
      }

      if (mounted) {
        CustomSnackBar.show(context: context, message: 'Schedule updated successfully!');
        Navigator.pop(context);
        Navigator.pop(context);
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
          .doc(_currentUser.uid)
          .collection('medicationSchedules')
          .doc(widget.scheduleId)
          .delete();

      if (widget.isActive) {
        await _remindersRef.child('schedule/med_times').remove();
        await _remindersRef.child('schedule/current_status').set("IDLE");
      }

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
          elevation: 5,
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
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text('Schedule Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                    ),
                    _buildInputField(
                      controller: _nameController,
                      label: 'Schedule Name (e.g., Morning Routine)',
                      icon: Icons.edit_calendar_rounded,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 32),

                    Row(
                      children: [
                        Icon(Icons.medication_rounded, color: Constants.darkGrey, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'Medications',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Constants.darkGrey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _medications.length,
                      itemBuilder: (context, index) {
                        final String currentName = _medications[index]['name']?.toString() ?? '';
                        final String currentDosage = _medications[index]['dosage']?.toString() ?? '';
                        final String currentFrequency = _medications[index]['frequency']?.toString() ?? 'Daily';
                        final currentTimes = _medications[index]['times'] as List? ?? [];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 24.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                            border: Border.all(color: Colors.grey.shade100, width: 2),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Medication #${index + 1}',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Constants.mediumGrey
                                      ),
                                    ),
                                    if (_medications.length > 1)
                                      InkWell(
                                        onTap: () => _removeMedication(index),
                                        borderRadius: BorderRadius.circular(50),
                                        child: Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent.shade200, size: 22),
                                        ),
                                      ),
                                  ],
                                ),
                                const Divider(height: 24),

                                _buildInputField(
                                  initialValue: currentName,
                                  onChanged: (val) => _medications[index]['name'] = val,
                                  label: 'Medicine Name',
                                  icon: Icons.vaccines_rounded,
                                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                                ),
                                const SizedBox(height: 16),

                                _buildInputField(
                                  initialValue: currentDosage,
                                  onChanged: (val) => _medications[index]['dosage'] = val,
                                  label: 'Dosage (e.g., 1 Pill)',
                                  icon: Icons.scale_rounded,
                                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                                ),
                                const SizedBox(height: 24),

                                const Text('Frequency', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 8),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: Row(
                                    children: ['Daily', 'Weekly', 'Custom'].map((String value) {
                                      final isSelected = currentFrequency == value;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 12.0),
                                        child: ChoiceChip(
                                          label: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            child: Text(value),
                                          ),
                                          selected: isSelected,
                                          onSelected: (bool selected) {
                                            if (selected) {
                                              setState(() {
                                                _medications[index]['frequency'] = value;
                                              });
                                            }
                                          },
                                          selectedColor: const Color(0xFF1E88E5),
                                          backgroundColor: Colors.white,
                                          elevation: isSelected ? 3 : 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            side: BorderSide(
                                              color: isSelected ? const Color(0xFF1E88E5) : Colors.grey.shade300,
                                              width: 1.5,
                                            ),
                                          ),
                                          labelStyle: TextStyle(
                                            color: isSelected ? Colors.white : Constants.darkGrey,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Reminder Times', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () => _addTime(index),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.add_alarm_rounded, color: Color(0xFF1E88E5), size: 18),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Add Time',
                                                style: TextStyle(color: const Color(0xFF1E88E5), fontWeight: FontWeight.bold, fontSize: 14),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                if (currentTimes.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                                    child: Text(
                                      'Tap "Add Time" to schedule this medication.',
                                      style: TextStyle(color: Constants.mediumGrey, fontStyle: FontStyle.italic, fontSize: 13),
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 12.0,
                                    runSpacing: 12.0,
                                    children: currentTimes.map((time) {
                                      final timeStr = time.toString();
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFF1E88E5).withValues(alpha: 0.3), width: 1.5),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.access_time_rounded, color: Color(0xFF1E88E5), size: 16),
                                            const SizedBox(width: 6),
                                            Text(
                                              _formatTime12h(timeStr),
                                              style: const TextStyle(
                                                color: Color(0xFF1E88E5),
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            InkWell(
                                              onTap: () => _removeTime(index, timeStr),
                                              child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    Center(
                      child: TextButton.icon(
                        onPressed: _addNewMedication,
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
                        label: const Text(
                          'Add Another Medication',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF1E88E5),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: const Color(0xFF1E88E5).withValues(alpha: 0.3), width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.transparent,
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                children: [
                  _buildGradientButton(
                    onPressed: _updateSchedule,
                    text: 'Save Changes',
                    icon: Icons.save_rounded,
                    gradient: kPrimaryGradient,
                  ),
                  const SizedBox(height: 12),
                  _buildGradientButton(
                    onPressed: _showDeleteConfirmation,
                    text: 'Delete Schedule',
                    icon: Icons.delete_outline_rounded,
                    gradient: kRedGradient,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}