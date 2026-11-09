import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'pair_device_page.dart';
import 'constants.dart';
import 'gradient_scaffold.dart';
import 'custom_snackbar.dart';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  DatabaseReference? _userRemindersRef;
  Stream<DatabaseEvent>? _deviceStream;
  double? _localVolume;

  @override
  void initState() {
    super.initState();
    _setupDeviceReference();
  }

  void _setupDeviceReference() {
    if (_currentUser == null) return;
    try {
      final db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: "https://agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app");
      _userRemindersRef = db.ref('reminders/${_currentUser.uid}');
      _deviceStream = _userRemindersRef!.onValue;
    } catch (e) {
      debugPrint("Error initializing Firebase: $e");
    }
  }

  Future<void> _updateVolume(double sliderValue) async {
    if (_userRemindersRef == null) return;
    try {
      await _userRemindersRef!.child('device').child('volume').set(sliderValue / 100.0);
    } catch (e) {
      if (mounted) CustomSnackBar.show(context: context, message: 'Error updating volume.', isError: true);
    }
  }

  void _disconnectDevice() async {
    if (_currentUser == null || _userRemindersRef == null) return;
    try {
      try { await FirebaseFirestore.instance.collection('users').doc(_currentUser.uid).update({'pairedDeviceId': FieldValue.delete()}); } catch (e) {}
      await _userRemindersRef!.remove();
      if (mounted) {
        CustomSnackBar.show(context: context, message: 'Device unpaired successfully.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) CustomSnackBar.show(context: context, message: 'Failed to unpair device.', isError: true);
    }
  }

  void _showDisconnectConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Constants.redColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.link_off_rounded,
                      color: Constants.redColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Disconnect Device?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Constants.darkGrey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Are you sure you want to unpair this device? You will stop receiving alerts until you pair a device again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Constants.mediumGrey,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _disconnectDevice();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Constants.redColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Disconnect',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Constants.darkblue,
                        side: BorderSide(color: Constants.gradiantBlue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  num _parseNum(dynamic value, [num defaultValue = 0]) {
    if (value == null) return defaultValue;
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  Widget _buildGradientButton({required VoidCallback? onPressed, required String text, IconData? icon, required Gradient gradient}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.0),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), backgroundColor: Colors.transparent, shadowColor: Colors.transparent),
        child: Ink(
          decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(16.0)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18.0),
            alignment: Alignment.center,
            child: (icon != null) ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: Colors.white, size: 22), const SizedBox(width: 8), Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5))]) : Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
          ),
        ),
      ),
    );
  }

  Widget _surface({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(20)}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Constants.darkblue.withValues(alpha: 0.08)),
        boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.045), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      child: child,
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your AgeLink device', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: Constants.darkblue)),
          const SizedBox(height: 6),
          Text('Manage the pill reminder device for your loved one.', style: TextStyle(fontSize: 14, height: 1.4, color: Constants.mediumGrey)),
          const SizedBox(height: 24),
          _surface(child: Column(children: [
            Container(width: 90, height: 90, decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(28)), child: Icon(Icons.devices_other_rounded, size: 44, color: Constants.darkblue)),
            const SizedBox(height: 22),
            Text('No device paired', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Constants.darkGrey)),
            const SizedBox(height: 8),
            Text('Pair an AgeLink pill dispenser to check its status and adjust its reminder volume.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.5, color: Constants.mediumGrey)),
            const SizedBox(height: 24),
            _buildGradientButton(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (context) => const PairDevicePage())); }, text: 'Pair AgeLink Device', icon: Icons.bluetooth_searching_rounded, gradient: kPrimaryGradient),
          ])),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon, {Color? valueColor, bool isBadge = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: Constants.darkblue, size: 21)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: Constants.mediumGrey)),
          const SizedBox(height: 4),
          Text(value, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: valueColor ?? Constants.darkGrey)),
        ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) return const GradientScaffold(body: Center(child: Text('Please log in to manage your device.')));

    return GradientScaffold(
      appBar: AppBar(
        title: Text('Device settings', style: TextStyle(color: Constants.darkblue, fontWeight: FontWeight.w800, fontSize: 19)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Constants.darkblue),
        centerTitle: true,
      ),
      body: _deviceStream == null
          ? _buildEmptyState()
          : StreamBuilder<DatabaseEvent>(
        stream: _deviceStream,
        builder: (context, AsyncSnapshot<DatabaseEvent> eventSnapshot) {
          if (eventSnapshot.connectionState == ConnectionState.waiting && !eventSnapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (eventSnapshot.hasError) return Center(child: Text('Error loading data: ${eventSnapshot.error.toString()}'));
          if (!eventSnapshot.hasData || eventSnapshot.data!.snapshot.value == null) return _buildEmptyState();

          final dataMap = eventSnapshot.data!.snapshot.value as Map<dynamic, dynamic>;
          final data = <String, dynamic>{};
          dataMap.forEach((key, value) { data[key.toString()] = value; });
          final deviceData = data['device'] as Map<dynamic, dynamic>? ?? {};

          String deviceName = deviceData['device_id']?.toString() ?? 'Unknown Device';
          final bool isActive = deviceData['device_active'] == true;
          String status = isActive ? 'Online' : 'Offline';
          Color statusColor = isActive ? const Color(0xFF4CAF50) : Colors.redAccent;
          final String lastSyncString = deviceData['last_sync']?.toString() ?? 'N/A';
          String lastSync = lastSyncString == 'N/A' ? 'Never' : lastSyncString;
          try { if (lastSyncString != 'N/A') { final parts = lastSyncString.split(':'); final dt = DateTime(2025, 1, 1, int.parse(parts[0]), int.parse(parts[1])); lastSync = 'Today at ${TimeOfDay.fromDateTime(dt).format(context)}'; } } catch (e) {}

          final num volumeNum = _parseNum(deviceData['volume'], 0.5);
          final double currentVolume = (volumeNum.toDouble() * 100.0).clamp(0.0, 100.0);
          double sliderValue = _localVolume ?? currentVolume;

          return Column(children: [
            Expanded(child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your AgeLink device', style: TextStyle(color: Constants.darkblue, fontSize: 27, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('Connection and reminder settings at a glance', style: TextStyle(color: Constants.mediumGrey, fontSize: 14)),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(gradient: kPrimaryGradient, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.17), blurRadius: 18, offset: const Offset(0, 8))]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 54, height: 54, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.17), borderRadius: BorderRadius.circular(17)), child: const Icon(Icons.medication_liquid_rounded, size: 29, color: Colors.white)),
                      const Spacer(),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(30)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(isActive ? Icons.check_circle_rounded : Icons.wifi_off_rounded, color: Colors.white, size: 16), const SizedBox(width: 6), Text(status, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))])),
                    ]),
                    const SizedBox(height: 20),
                    const Text('PILL REMINDER DEVICE', style: TextStyle(color: Color(0xFFDFEAFF), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                    const SizedBox(height: 6),
                    Text(deviceName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 9),
                    Text(isActive ? 'Your device is connected.' : 'Your device is currently offline.', style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ]),
                ),
                const SizedBox(height: 22),
                Text('Device information', style: TextStyle(color: Constants.darkGrey, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                _surface(child: Column(children: [
                  _buildInfoRow('Device ID', deviceName, Icons.memory_rounded),
                  Divider(height: 1, color: Colors.grey.shade200),
                  _buildInfoRow('Connection status', status, isActive ? Icons.wifi_rounded : Icons.wifi_off_rounded, valueColor: statusColor),
                  Divider(height: 1, color: Colors.grey.shade200),
                  _buildInfoRow('Last synchronized', lastSync, Icons.sync_rounded),
                ])),
                const SizedBox(height: 22),
                Text('Reminder settings', style: TextStyle(color: Constants.darkGrey, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                _surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 43, height: 43, decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(13)), child: Icon(Icons.volume_up_rounded, color: Constants.darkblue)),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Buzzer volume', style: TextStyle(color: Constants.darkGrey, fontSize: 16, fontWeight: FontWeight.w700))),
                    Text('${sliderValue.round()}%', style: TextStyle(color: Constants.darkblue, fontSize: 18, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 14),
                  SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 5, activeTrackColor: Constants.darkblue, inactiveTrackColor: Constants.lightBlue, thumbColor: Constants.darkblue), child: Slider(value: sliderValue, min: 0, max: 100, divisions: 10, onChanged: (value) { setState(() { _localVolume = value; }); }, onChangeEnd: (value) async { await _updateVolume(value); if (mounted) { setState(() { _localVolume = null; }); } })),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Mute', style: TextStyle(color: Constants.mediumGrey, fontSize: 12)), Text('Maximum', style: TextStyle(color: Constants.mediumGrey, fontSize: 12))]),
                ])),
                const SizedBox(height: 16),
              ]),
            )),
            SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 14), child: OutlinedButton.icon(
              onPressed: _showDisconnectConfirmation,
              icon: const Icon(Icons.link_off_rounded, size: 20),
              label: const Text('Disconnect device'),
              style: OutlinedButton.styleFrom(foregroundColor: Constants.redColor, backgroundColor: Colors.white, minimumSize: const Size(double.infinity, 54), side: BorderSide(color: Constants.redColor.withValues(alpha: 0.4)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ))),
          ]);
        },
      ),
    );
  }
}
