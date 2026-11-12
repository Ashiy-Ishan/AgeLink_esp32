import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'constants.dart';
import 'gradient_scaffold.dart';
import 'custom_snackbar.dart';
import 'local_reminder_sync.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  late final DatabaseReference _contactsRef;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isDarkMode = false;
  final String _selectedLanguage = 'English';

  @override
  void initState() {
    super.initState();
    if (currentUser != null) {
      _contactsRef = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: "https://agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app").ref('appData/${currentUser!.uid}/emergencyContacts');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Widget _buildGradientButton({required VoidCallback? onPressed, required String text, IconData? icon, required Gradient gradient, EdgeInsets padding = const EdgeInsets.symmetric(vertical: 18.0), double? width = double.infinity, double fontSize = 16, FontWeight fontWeight = FontWeight.bold}) {
    final bool isEnabled = onPressed != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.0),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), backgroundColor: Colors.transparent, shadowColor: Colors.transparent, disabledBackgroundColor: Colors.transparent),
        child: Ink(
          decoration: BoxDecoration(gradient: isEnabled ? gradient : LinearGradient(colors: [Constants.mediumGrey, Constants.mediumGrey.withValues(alpha: 0.7)], begin: Alignment.centerLeft, end: Alignment.centerRight), borderRadius: BorderRadius.circular(16.0)),
          child: Container(
            width: width,
            padding: padding,
            alignment: Alignment.center,
            child: (icon != null) ? Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 22), const SizedBox(width: 8), Text(text, style: TextStyle(color: Colors.white, fontWeight: fontWeight, fontSize: fontSize, letterSpacing: 0.5))]) : Text(text, style: TextStyle(color: Colors.white, fontWeight: fontWeight, fontSize: fontSize, letterSpacing: 0.5)),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({required TextEditingController controller, required String label, required IconData icon, TextInputType keyboardType = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))]),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w600),
        decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: Constants.mediumGrey), prefixIcon: Icon(icon, color: const Color(0xFF1E88E5)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), filled: true, fillColor: Colors.transparent, contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
      ),
    );
  }

  void _showAddContactDialog() {
    _nameController.clear();
    _phoneController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF1E88E5).withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.contact_phone_rounded, color: Color(0xFF1E88E5))), const SizedBox(width: 12), const Text('Add Contact', style: TextStyle(fontWeight: FontWeight.bold))]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [_buildInputField(controller: _nameController, label: 'Name', icon: Icons.person_rounded), const SizedBox(height: 16), _buildInputField(controller: _phoneController, label: 'Phone', icon: Icons.phone_rounded, keyboardType: TextInputType.phone)]),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [TextButton(child: Text('Cancel', style: TextStyle(color: Constants.mediumGrey, fontWeight: FontWeight.bold, fontSize: 16)), onPressed: () => Navigator.of(context).pop()), _buildGradientButton(onPressed: () async {
            final saved = await _saveContact(
              name: _nameController.text.trim(),
              phone: _phoneController.text.trim(),
            );
            if (saved && context.mounted) Navigator.of(context).pop();
          }, text: 'Save', gradient: const LinearGradient(colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)], begin: Alignment.topLeft, end: Alignment.bottomRight), width: 100, fontSize: 14, padding: const EdgeInsets.symmetric(vertical: 12.0))],
        );
      },
    );
  }

  Future<bool> _saveContact({required String name, required String phone}) async {
    if (currentUser == null) return false;
    final number = phone.replaceAll(RegExp(r'[\s()\-]'), '');
    if (name.isEmpty || !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(number)) {
      CustomSnackBar.show(
        context: context,
        message: 'Enter a name and a valid phone number.',
        isError: true,
      );
      return false;
    }

    try {
      await _contactsRef.push().set({'name': name, 'phone': number});
      if (mounted) {
        CustomSnackBar.show(context: context, message: 'Emergency contact saved.');
      }
      return true;
    } catch (_) {
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Could not save the emergency contact.',
          isError: true,
        );
      }
      return false;
    }
  }

  Future<void> _deleteContact(String contactKey) async {
    if (currentUser == null) return;
    try {
      await _contactsRef.child(contactKey).remove();
      if (mounted) {
        CustomSnackBar.show(context: context, message: 'Contact removed.');
      }
    } catch (_) {
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Could not remove the emergency contact.',
          isError: true,
        );
      }
    }
  }

  Widget _sectionHeading(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Constants.lightBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Constants.darkblue, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Constants.darkGrey, fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(description, style: TextStyle(color: Constants.mediumGrey, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? value,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: Constants.darkblue, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w700, fontSize: 15.5)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Constants.mediumGrey, fontSize: 12.5, height: 1.3)),
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 6),
                Text(value, style: TextStyle(color: Constants.mediumGrey, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
              const SizedBox(width: 5),
              Icon(Icons.chevron_right_rounded, color: Constants.mediumGrey, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactCard(Map<String, String> contact) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Constants.darkblue.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              height: 45,
              width: 45,
              decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.contact_emergency_rounded, color: Constants.darkblue, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact['name']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 3),
                  Text(contact['phone']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Constants.mediumGrey, fontSize: 13)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove contact',
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              onPressed: () => _deleteContact(contact['key']!),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(color: Constants.darkblue, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Constants.darkblue),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: kPrimaryGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 7))],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.health_and_safety_rounded, color: Colors.white, size: 38),
                    SizedBox(width: 15),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Care settings', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                      SizedBox(height: 6),
                      Text('Manage emergency contacts and app preferences in one place.', style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
                    ])),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _sectionHeading(Icons.emergency_rounded, 'Emergency contacts', 'Contacts saved for the AgeLink SOS feature.'),
              if (currentUser == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text('Please log in to manage emergency contacts.', style: TextStyle(color: Constants.mediumGrey)),
                )
              else
                StreamBuilder<DatabaseEvent>(
                  stream: _contactsRef.onValue,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                    }
                    if (snapshot.hasError) {
                      return Padding(padding: const EdgeInsets.all(16), child: Text('Error: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                      return Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.86), borderRadius: BorderRadius.circular(20)),
                        child: Column(children: [
                          Icon(Icons.person_add_alt_1_rounded, color: Constants.darkblue, size: 32),
                          const SizedBox(height: 10),
                          Text('No contacts added yet', style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 5),
                          Text('Add a trusted person to your emergency contacts.', textAlign: TextAlign.center, style: TextStyle(color: Constants.mediumGrey, fontSize: 13)),
                        ]),
                      );
                    }
                    Map<dynamic, dynamic> contactsMap = snapshot.data!.snapshot.value as Map;
                    final contactsList = contactsMap.entries.map((entry) {
                      final data = Map<String, dynamic>.from(entry.value as Map);
                      return <String, String>{'key': entry.key.toString(), 'name': (data['name'] ?? 'No Name').toString(), 'phone': (data['phone'] ?? 'No Phone').toString()};
                    }).toList();
                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: contactsList.length,
                      itemBuilder: (context, index) => _contactCard(contactsList[index]),
                    );
                  },
                ),
              const SizedBox(height: 14),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _showAddContactDialog,
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: const Text('Add emergency contact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(backgroundColor: Constants.darkblue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                ),
              ),
              const SizedBox(height: 30),
              _sectionHeading(Icons.tune_rounded, 'App preferences', 'Personalize your AgeLink experience.'),
              Container(
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(20), border: Border.all(color: Constants.darkblue.withValues(alpha: 0.07))),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                      secondary: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(13)),
                        child: Icon(_isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: Constants.darkblue),
                      ),
                      title: Text('Dark mode', style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w700, fontSize: 15.5)),
                      subtitle: Text('Display preference', style: TextStyle(color: Constants.mediumGrey, fontSize: 12.5)),
                      value: _isDarkMode,
                      activeThumbColor: Constants.darkblue,
                      onChanged: (bool newValue) { setState(() { _isDarkMode = newValue; }); },
                    ),
                    Divider(indent: 72, endIndent: 18, height: 1, color: Constants.lightBlue),
                    _settingTile(icon: Icons.language_rounded, title: 'Language', subtitle: 'App display language', value: _selectedLanguage, onTap: () { CustomSnackBar.show(context: context, message: 'Language settings coming soon.'); }),
                    Divider(indent: 72, endIndent: 18, height: 1, color: Constants.lightBlue),
                    if (LocalReminderSync.supported) const PhoneReminderSettings(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
