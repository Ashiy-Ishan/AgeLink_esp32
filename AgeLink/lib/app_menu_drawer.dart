import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'family_permissions_page.dart';
import 'device_page.dart';
import 'settings_page.dart';
import 'help_page.dart';
import 'edit_profile_page.dart';
import 'constants.dart';
import 'custom_snackbar.dart';
import 'local_reminder_sync.dart';

class AppMenuDrawer extends StatelessWidget {
  const AppMenuDrawer({super.key});

  final String appId = kAppId;

  void _logout(BuildContext context) async {
    Navigator.of(context).pop();
    CustomSnackBar.show(
        context: context,
        message: 'Logging out...'
    );
    await LocalReminderSync.clear();
    await FirebaseAuth.instance.signOut();
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }


  Widget _buildMenuItem({required IconData icon, required String title, required VoidCallback onTap, Color? color, bool isLogout = false}) {
    final itemColor = color ?? Constants.darkGrey;
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Material(color: Colors.transparent,
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(
                  color: (color ?? Constants.darkblue).withValues(alpha: 0.09), borderRadius: BorderRadius.circular(13)),
                  child: Icon(icon, color: color ?? Constants.darkblue, size: 22)),
              const SizedBox(width: 13),
              Expanded(child: Text(title, style: TextStyle(color: itemColor, fontSize: 14, fontWeight: FontWeight.w700))),
              if (!isLogout) Icon(Icons.chevron_right_rounded, color: Constants.mediumGrey, size: 21),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Drawer(child: Center(child: Text('Not logged in.')));
    final userDocRef = FirebaseFirestore.instance.collection('artifacts').doc(appId).collection('users')
        .doc(user.uid).collection('profile').doc('details');
    return Drawer(backgroundColor: Colors.white,
      child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 14, 12),
          child: Row(children: [
            Expanded(child: Image.asset('assets/agelink_logo.png', height: 35, alignment: Alignment.centerLeft, fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Text('AgeLink', style: TextStyle(color: Constants.darkblue, fontSize: 21, fontWeight: FontWeight.w800)))),
            IconButton(onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, color: Constants.darkGrey), tooltip: 'Close menu'),
          ]),
        ),
        StreamBuilder<DocumentSnapshot>(stream: userDocRef.snapshots(), builder: (context, snapshot) {
          String name;
          String email = user.email ?? 'No email';
          String? profileImageUrl;
          if (snapshot.connectionState == ConnectionState.waiting) {
            name = 'Loading...';
          } else if (snapshot.hasError) {
            name = 'Error';
          } else if (!snapshot.hasData || !snapshot.data!.exists) {
            name = user.displayName ?? 'New User';
          } else {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            name = data['name'] ?? user.displayName ?? 'Caregiver User';
            email = data['email'] ?? user.email!;
            profileImageUrl = data['profileImageUrl'];
          }
          return Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 17),
            child: Container(padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                Row(children: [
                  CircleAvatar(radius: 27, backgroundColor: Colors.white,
                      backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty ? NetworkImage(profileImageUrl) : null,
                      child: profileImageUrl == null || profileImageUrl.isEmpty ? Icon(Icons.person_rounded, color: Constants.darkblue, size: 28) : null),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Constants.darkGrey, fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(email, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Constants.mediumGrey, fontSize: 12)),
                  ])),
                ]),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(
                  onPressed: () => _navigateTo(context, const EditProfilePage()),
                  style: OutlinedButton.styleFrom(side: BorderSide(color: Constants.darkblue.withValues(alpha: 0.18)),
                      backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  icon: Icon(Icons.edit_outlined, size: 17, color: Constants.darkblue),
                  label: Text('Edit profile', style: TextStyle(color: Constants.darkblue, fontWeight: FontWeight.w700)),
                )),
              ]),
            ),
          );
        }),
        Expanded(child: SingleChildScrollView(physics: const BouncingScrollPhysics(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 6, 16, 9),
              child: Text('CARE & DEVICES', style: TextStyle(color: Constants.mediumGrey, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1))),
          _buildMenuItem(icon: Icons.family_restroom_rounded, title: 'Family & Permissions', onTap: () => _navigateTo(context, const FamilyPermissionsPage())),
          _buildMenuItem(icon: Icons.devices_rounded, title: 'Device Settings', onTap: () => _navigateTo(context, const DevicePage())),
          const SizedBox(height: 14),
          Padding(padding: const EdgeInsets.fromLTRB(24, 6, 16, 9),
              child: Text('GENERAL', style: TextStyle(color: Constants.mediumGrey, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1))),
          _buildMenuItem(icon: Icons.settings_outlined, title: 'App Settings', onTap: () => _navigateTo(context, const SettingsPage())),
          _buildMenuItem(icon: Icons.help_outline_rounded, title: 'Help & Support', onTap: () => _navigateTo(context, const HelpPage())),
        ]))),
        Divider(height: 1, color: Constants.darkblue.withValues(alpha: 0.09)),
        const SizedBox(height: 9),
        _buildMenuItem(icon: Icons.logout_rounded, title: 'Log Out', color: Constants.redColor, isLogout: true,
            onTap: () => _showLogoutConfirmation(context)),
        const SizedBox(height: 14),
      ])),
    );
  }


  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              ),
              const SizedBox(width: 12),
              const Text('Log Out'),
            ],
          ),
          content: Text(
            'Are you sure you want to log out of AgeLink?',
            style: TextStyle(color: Constants.darkGrey, fontSize: 16),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(color: Constants.mediumGrey, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                _logout(context);
              },
              child: const Text('Log Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        );
      },
    );
  }
}
