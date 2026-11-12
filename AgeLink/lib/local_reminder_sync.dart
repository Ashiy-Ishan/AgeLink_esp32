import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class LocalReminderSync extends StatefulWidget {
  const LocalReminderSync({required this.uid, required this.child, super.key});

  final String uid;
  final Widget child;

  static const _channel = MethodChannel('agelink/local_reminders');
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> clear() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } on PlatformException {
      debugPrint('AgeLink could not clear the local reminder schedule.');
    }
  }

  @override
  State<LocalReminderSync> createState() => _LocalReminderSyncState();
}

class _LocalReminderSyncState extends State<LocalReminderSync> with WidgetsBindingObserver {
  StreamSubscription<DatabaseEvent>? _schedule;

  @override
  void initState() {
    super.initState();
    if (!LocalReminderSync.supported) return;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_begin());
  }

  Future<void> _begin() async {
    try {
      await LocalReminderSync._channel.invokeMethod<void>('begin', {'uid': widget.uid});
      if (!mounted) return;
      final database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app',
      );
      _schedule = database.ref('reminders/${widget.uid}/schedule/med_times').onValue.listen(
        (event) => unawaited(_replace(event.snapshot)),
        onError: (Object error) => debugPrint('AgeLink kept the local schedule after a Firebase read error.'),
      );
    } on PlatformException {
      debugPrint('AgeLink could not start local reminder sync.');
    }
  }

  Future<void> _replace(DataSnapshot snapshot) async {
    if (!mounted) return;
    final data = snapshot.value;
    if (data != null && data is! Map && data is! List) return;

    final doses = <Map<String, Object>>[];
    for (final child in snapshot.children) {
      final value = child.value;
      if (value is! Map || value['time'] is! String) continue;
      final match = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$')
          .firstMatch((value['time'] as String).trim());
      if (match == null) continue;
      doses.add({
        'minute': int.parse(match[1]!) * 60 + int.parse(match[2]!),
        'name': value['name']?.toString().trim() ?? '',
      });
    }
    try {
      await LocalReminderSync._channel.invokeMethod<void>('replace', {
        'uid': widget.uid,
        'doses': jsonEncode(doses),
      });
    } on PlatformException {
      debugPrint('AgeLink could not update the phone reminder schedule.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    try {
      await LocalReminderSync._channel.invokeMethod<void>('refresh');
    } on PlatformException {
      debugPrint('AgeLink could not refresh local reminders.');
    }
  }

  @override
  void dispose() {
    if (LocalReminderSync.supported) WidgetsBinding.instance.removeObserver(this);
    _schedule?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class PhoneReminderSettings extends StatefulWidget {
  const PhoneReminderSettings({super.key});

  @override
  State<PhoneReminderSettings> createState() => _PhoneReminderSettingsState();
}

class _PhoneReminderSettingsState extends State<PhoneReminderSettings> with WidgetsBindingObserver {
  Map<String, dynamic>? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_readStatus());
  }

  Future<void> _readStatus() async {
    try {
      final status = await LocalReminderSync._channel.invokeMapMethod<String, dynamic>('status');
      if (mounted) setState(() => _status = status);
    } on PlatformException {
      if (mounted) setState(() => _status = null);
    }
  }

  Future<void> _setUp() async {
    final permission = await Permission.notification.request();
    await _readStatus();
    if (!mounted || _status == null) return;
    if (_status?['notifications'] != true) {
      if (permission.isGranted || permission.isPermanentlyDenied) {
        await openAppSettings();
      }
    } else if (_status?['exact'] != true) {
      await LocalReminderSync._channel.invokeMethod<void>('exactSettings');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_readStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String detail;
    final status = _status;
    if (status == null) {
      detail = 'Check Android reminder permissions';
    } else if (status['notifications'] != true) {
      detail = 'Allow notifications to get dose alerts';
    } else if (status['exact'] != true) {
      detail = 'Allow Alarms & reminders for on-time alerts';
    } else if (status['doses'] == 0) {
      detail = 'Ready. Sync a medication schedule to start.';
    } else {
      detail = '${status['doses']} daily doses saved on this phone';
    }
    return ListTile(
      leading: const Icon(Icons.notifications_active_rounded),
      title: const Text('Phone reminders'),
      subtitle: Text(detail),
      trailing: const Icon(Icons.chevron_right),
      onTap: _setUp,
    );
  }
}
