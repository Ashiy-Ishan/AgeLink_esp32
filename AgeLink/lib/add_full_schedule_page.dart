import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'constants.dart';
import 'gradient_scaffold.dart';
import 'custom_snackbar.dart';

const kPrimaryGradient = LinearGradient(
  colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);
const kGreenGradient = LinearGradient(
  colors: [Color(0xFF66BB6A), Color(0xFF388E3C)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

class _MedicationEntry {
  final TextEditingController name;
  final TextEditingController dosage;
  final List times;
  String frequency;

  _MedicationEntry()
      : name = TextEditingController(),
        dosage = TextEditingController(),
        times = [],
        frequency = 'Daily';
}

class AddFullSchedulePage extends StatefulWidget {
  const AddFullSchedulePage({super.key});

  @override
  State<AddFullSchedulePage> createState() => _AddFullSchedulePageState();
}

class _AddFullSchedulePageState extends State<AddFullSchedulePage> {
  final _formKey = GlobalKey<FormState>();
  final _scheduleNameController = TextEditingController();
  final List _medicationEntries = [_MedicationEntry()];
  bool _isLoading = false;

  final User? _currentUser = FirebaseAuth.instance.currentUser;
  late final DatabaseReference _remindersRef;

  @override
  void initState() {
    super.initState();
    if (_currentUser != null) {
      _remindersRef = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: "https://agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app"
      ).ref('reminders/${_currentUser?.uid}');
    }
  }

  Widget _buildGradientButton({
    required VoidCallback? onPressed,
    required String text,
    IconData? icon,
    required Gradient gradient,
    double verticalPadding = 18.0,
  }) {
    final bool isEnabled = onPressed != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.0),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          elevation: 0,
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: isEnabled
                ? gradient
                : LinearGradient(
              colors: [Constants.mediumGrey, Constants.mediumGrey.withValues(alpha: 0.7)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: verticalPadding),
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
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
        validator: validator,
        style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Constants.mediumGrey, fontSize: 14),
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

  void _addMedicationRow() {
    setState(() {
      _medicationEntries.add(_MedicationEntry());
    });
  }

  void _removeMedicationRow(int index) {
    if (_medicationEntries.length > 1) {
      setState(() {
        _medicationEntries.removeAt(index);
      });
    }
  }

  Future<void> _selectTime(int entryIndex) async {
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
        final currentEntry = _medicationEntries[entryIndex] as _MedicationEntry;
        currentEntry.times.add(picked);
        currentEntry.times.sort((a, b) {
          final tA = a as TimeOfDay;
          final tB = b as TimeOfDay;
          return (tA.hour * 60 + tA.minute).compareTo(tB.hour * 60 + tB.minute);
        });
      });
    }
  }

  void _removeTime(int entryIndex, dynamic time) {
    setState(() {
      final currentEntry = _medicationEntries[entryIndex] as _MedicationEntry;
      currentEntry.times.remove(time);
    });
  }

  Future<void> _saveSchedule() async {
    if (!_formKey.currentState!.validate()) return;
    if (_currentUser == null) return;

    setState(() { _isLoading = true; });

    try {
      final Map rtdbScheduleObject = {};
      final List firestoreMedicationsList = [];

      for (var entryObj in _medicationEntries) {
        final entry = entryObj as _MedicationEntry;
        if (entry.name.text.isNotEmpty && entry.times.isNotEmpty) {
          final List timesList = [];

          for (var timeObj in entry.times) {
            final time = timeObj as TimeOfDay;
            String timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
            final String safeName = entry.name.text.replaceAll(' ', '_');
            String key = "${safeName}_${timeStr.replaceAll(":", "")}";

            rtdbScheduleObject[key] = {
              'name': entry.name.text,
              'dosage': entry.dosage.text,
              'time': timeStr,
            };

            timesList.add(timeStr);
          }

          firestoreMedicationsList.add({
            'name': entry.name.text,
            'dosage': entry.dosage.text,
            'frequency': entry.frequency,
            'times': timesList,
          });
        }
      }

      if (rtdbScheduleObject.isEmpty) {
        CustomSnackBar.show(
            context: context,
            message: 'Please add at least one valid medication with a time.',
            isError: true
        );
        setState(() { _isLoading = false; });
        return;
      }

      final firestoreRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser?.uid)
          .collection('medicationSchedules');

      final existingSchedules = await firestoreRef.where('isActive', isEqualTo: true).get();
      for (final doc in existingSchedules.docs) {
        await doc.reference.update({'isActive': false});
      }

      final firestoreScheduleData = {
        'scheduleName': _scheduleNameController.text,
        'isActive': true,
        'createdAt': Timestamp.now(),
        'medications': firestoreMedicationsList,
      };

      await firestoreRef.add(firestoreScheduleData);
      await _remindersRef.child('schedule/med_times').set(rtdbScheduleObject);
      await _remindersRef.child('schedule/current_status').set("IDLE");

      if (mounted) {
        CustomSnackBar.show(
            context: context,
            message: 'New schedule saved and activated!'
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
            context: context,
            message: 'Failed to save schedule: $e',
            isError: true
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }


  Widget _sectionTitle(int number, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(11)),
          child: Text('$number', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Constants.darkblue)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Constants.darkGrey)),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(fontSize: 12.5, color: Constants.mediumGrey, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: Constants.mediumGrey, fontSize: 13),
      hintStyle: TextStyle(color: Constants.mediumGrey.withValues(alpha: 0.75), fontSize: 13),
      prefixIcon: Icon(icon, color: Constants.darkblue, size: 20),
      filled: true,
      fillColor: const Color(0xFFF7FAFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFD9E7FA))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFD9E7FA))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Constants.darkblue, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Constants.redColor)),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0EAFA)),
        boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.045), blurRadius: 20, offset: const Offset(0, 7))],
      ),
      child: child,
    );
  }

  Widget _frequencySelector(String frequency, ValueChanged<String> onSelected) {
    return LayoutBuilder(builder: (context, constraints) {
      return Row(
        children: ['Daily', 'Weekly', 'Custom'].map((value) {
          final selected = frequency == value;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => onSelected(value),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(minHeight: 45),
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? Constants.darkblue : const Color(0xFFF4F8FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? Constants.darkblue : const Color(0xFFE0EAFA)),
                  ),
                  child: Text(value, textAlign: TextAlign.center, style: TextStyle(color: selected ? Colors.white : Constants.darkGrey, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          );
        }).toList(),
      );
    });
  }

  Widget _actionButton({required String label, required IconData icon, required VoidCallback action, bool destructive = false}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: action,
        icon: Icon(icon, size: 19),
        label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        style: ElevatedButton.styleFrom(
          backgroundColor: destructive ? Constants.redColor : Constants.darkblue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }

  Widget _medicationFormCard(_MedicationEntry entry, int index) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.medication_rounded, color: Constants.darkblue, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Medication ${index + 1}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Constants.darkGrey)),
              Text('Medicine information & reminders', style: TextStyle(fontSize: 11.5, color: Constants.mediumGrey)),
            ])),
            if (_medicationEntries.length > 1)
              IconButton(
                tooltip: 'Remove medication',
                onPressed: () => _removeMedicationRow(index),
                icon: Icon(Icons.delete_outline_rounded, color: Constants.redColor),
              ),
          ]),
          const SizedBox(height: 18),
          TextFormField(
            controller: entry.name,
            validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w600),
            decoration: _fieldDecoration('Medicine name', Icons.medication_outlined, hint: 'e.g. Amoxicillin'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: entry.dosage,
            style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w600),
            decoration: _fieldDecoration('Dosage', Icons.science_outlined, hint: 'e.g. 1 tablet'),
          ),
          const SizedBox(height: 19),
          Text('How often?', style: TextStyle(color: Constants.darkGrey, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 9),
          _frequencySelector(entry.frequency, (value) => setState(() => entry.frequency = value)),
          const SizedBox(height: 20),
          Row(children: [
            Icon(Icons.schedule_rounded, color: Constants.darkblue, size: 19),
            const SizedBox(width: 8),
            Text('Reminder times', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Constants.darkGrey)),
            const Spacer(),
            Text('${entry.times.length} added', style: TextStyle(fontSize: 12, color: Constants.mediumGrey)),
          ]),
          const SizedBox(height: 10),
          if (entry.times.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entry.times.map((timeObj) {
                  final time = timeObj as TimeOfDay;
                  return InputChip(
                    avatar: Icon(Icons.access_time_rounded, size: 16, color: Constants.darkblue),
                    label: Text(time.format(context), style: TextStyle(color: Constants.darkblue, fontWeight: FontWeight.w700)),
                    backgroundColor: Constants.lightBlue,
                    side: BorderSide.none,
                    deleteIcon: Icon(Icons.close_rounded, size: 17, color: Constants.darkblue),
                    onDeleted: () => _removeTime(index, time),
                  );
                }).toList(),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('No reminder time added yet', style: TextStyle(fontSize: 12.5, color: Constants.mediumGrey)),
            ),
          SizedBox(
            width: double.infinity,
            height: 45,
            child: OutlinedButton.icon(
              onPressed: () => _selectTime(index),
              icon: const Icon(Icons.add_alarm_rounded, size: 19),
              label: const Text('Add reminder time', style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Constants.darkblue,
                side: BorderSide(color: Constants.darkblue.withValues(alpha: 0.35)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: Text('Create Schedule', style: TextStyle(color: Constants.darkblue, fontSize: 17, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: BackButton(color: Constants.darkblue),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: Column(children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(color: Constants.darkblue, borderRadius: BorderRadius.circular(16)),
                            child: const Icon(Icons.medication_rounded, color: Colors.white, size: 25),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('New medication plan', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Constants.darkGrey)),
                            const SizedBox(height: 3),
                            Text('Set up a clear reminder routine for your loved one.', style: TextStyle(fontSize: 12.5, color: Constants.mediumGrey, height: 1.35)),
                          ])),
                        ]),
                        const SizedBox(height: 26),
                        _sectionTitle(1, 'Plan details', 'Give this medication routine a recognizable name'),
                        const SizedBox(height: 12),
                        _panel(child: TextFormField(
                          controller: _scheduleNameController,
                          validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a name for the schedule' : null,
                          style: TextStyle(color: Constants.darkGrey, fontSize: 15, fontWeight: FontWeight.w600),
                          decoration: _fieldDecoration('Schedule name', Icons.edit_note_rounded, hint: 'e.g. Morning medication plan'),
                        )),
                        const SizedBox(height: 26),
                        Row(children: [
                          Expanded(child: _sectionTitle(2, 'Medications', 'Add medicines, frequency, and reminder times')),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(20)),
                            child: Text('${_medicationEntries.length} total', style: TextStyle(color: Constants.darkblue, fontSize: 12, fontWeight: FontWeight.w800)),
                          ),
                        ]),
                        const SizedBox(height: 13),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _medicationEntries.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 13),
                          itemBuilder: (context, index) => _medicationFormCard(_medicationEntries[index] as _MedicationEntry, index),
                        ),
                        const SizedBox(height: 15),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: _addMedicationRow,
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            label: const Text('Add another medication', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Constants.darkblue,
                              backgroundColor: Colors.white.withValues(alpha: 0.8),
                              side: BorderSide(color: Constants.darkblue.withValues(alpha: 0.35)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 13),
                        Row(children: [
                          Icon(Icons.info_outline_rounded, size: 15, color: Constants.mediumGrey),
                          const SizedBox(width: 7),
                          Expanded(child: Text('Review your medication details before saving.', style: TextStyle(color: Constants.mediumGrey, fontSize: 12))),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(18, 12, 18, MediaQuery.of(context).padding.bottom > 0 ? 12 : 17),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Constants.darkblue.withValues(alpha: 0.09))),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _isLoading
                      ? const SizedBox(height: 52, child: Center(child: CircularProgressIndicator()))
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                    _actionButton(label: 'Save & activate schedule', icon: Icons.check_circle_outline_rounded, action: _saveSchedule),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
