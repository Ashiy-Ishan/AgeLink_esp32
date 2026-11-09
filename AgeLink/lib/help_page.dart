import 'package:flutter/material.dart';
import 'constants.dart';
import 'gradient_scaffold.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  Widget _helpItem(IconData icon, String title, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Constants.darkblue.withValues(alpha: 0.07)),
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          childrenPadding: const EdgeInsets.fromLTRB(17, 0, 17, 17),
          leading: Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: Constants.darkblue, size: 22),
          ),
          title: Text(title, style: TextStyle(color: Constants.darkGrey, fontSize: 15, fontWeight: FontWeight.w700)),
          iconColor: Constants.darkblue,
          collapsedIconColor: Constants.mediumGrey,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(description, style: TextStyle(color: Constants.mediumGrey, fontSize: 14, height: 1.55)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guideStep(int number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 19),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(11)),
            child: Text('$number', style: TextStyle(color: Constants.darkblue, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Constants.darkGrey)),
                const SizedBox(height: 3),
                Text(description, style: TextStyle(fontSize: 13, height: 1.5, color: Constants.mediumGrey)),
              ],
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
        title: Text('Help Center', style: TextStyle(color: Constants.darkblue, fontWeight: FontWeight.w800)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Constants.darkblue),
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
                padding: const EdgeInsets.all(23),
                decoration: BoxDecoration(
                  gradient: kPrimaryGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 7))],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.support_agent_rounded, color: Colors.white, size: 42),
                    SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('How can we help?', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white)),
                      SizedBox(height: 6),
                      Text('A quick guide to using AgeLink for family care.', style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white)),
                    ])),
                  ],
                ),
              ),
              const SizedBox(height: 27),
              Text('Getting started', style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w800, fontSize: 19)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 5),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.93), borderRadius: BorderRadius.circular(21)),
                child: Column(
                  children: [
                    _guideStep(1, 'Connect the device', 'Open Device Settings or Connect Device, then follow the pairing steps.'),
                    _guideStep(2, 'Create a medication schedule', 'Open Schedule, add the medicine details and reminder times, then save and activate it.'),
                    _guideStep(3, 'Review daily activity', 'Check Home for today’s medication information and Notifications for recorded dose confirmations.'),
                  ],
                ),
              ),
              const SizedBox(height: 27),
              Text('Frequently asked questions', style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w800, fontSize: 19)),
              const SizedBox(height: 14),
              _helpItem(Icons.bluetooth_rounded, 'How do I pair an AgeLink device?', 'Open the menu, choose Device Settings, and select Pair New Device when no device is paired. Keep Bluetooth enabled, select your AgeLink device, and follow the Wi-Fi setup prompts.'),
              _helpItem(Icons.medication_rounded, 'How can I change medication times?', 'Open Schedule, select the appropriate schedule, and choose Edit Schedule. Update the reminder times and save your changes.'),
              _helpItem(Icons.notifications_rounded, 'Where can I see medication history?', 'Open Notifications to view recorded medication confirmations grouped by date. The screen shows taken and missed results based on the existing device records.'),
              _helpItem(Icons.emergency_rounded, 'Where do I add emergency contacts?', 'Open the menu, select App Settings, and use Add emergency contact to save a contact name and phone number.'),
              _helpItem(Icons.family_restroom_rounded, 'How can I invite a family member?', 'Open Family & Permissions, then Invite Family Member. You can share an AgeLink invitation using a messaging or email app. Sharing an invitation does not automatically grant access to healthcare data.'),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(17)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: Constants.darkblue, size: 21),
                    const SizedBox(width: 10),
                    Expanded(child: Text('For medication concerns or urgent medical situations, contact a qualified healthcare professional or local emergency services.', style: TextStyle(color: Constants.darkblue, fontSize: 13, height: 1.5))),
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
