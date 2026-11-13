import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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

  static Future<Map<String, dynamic>?> _status() =>
      _channel.invokeMapMethod<String, dynamic>('status');

  static Future<void> _setUp() async {
    try {
      final permission = await Permission.notification.request();
      final status = await _status();
      if (status == null) return;
      if (status['notifications'] != true) {
        if (permission.isGranted || permission.isPermanentlyDenied) {
          await openAppSettings();
        }
      } else if (status['exact'] != true) {
        await _channel.invokeMethod<void>('exactSettings');
      }
    } on PlatformException {
      debugPrint('AgeLink could not open Android reminder settings.');
    }
  }

  @override
  State<LocalReminderSync> createState() => _LocalReminderSyncState();
}

class _LocalReminderSyncState extends State<LocalReminderSync> with WidgetsBindingObserver {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _schedule;
  bool _offeredSetup = false;

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
      _schedule = FirebaseFirestore.instance
          .collection('users').doc(widget.uid).collection('medicationSchedules')
          .where('isActive', isEqualTo: true).limit(1)
          .snapshots(includeMetadataChanges: true)
          .listen(
        (snapshot) => unawaited(_replace(snapshot)),
        onError: (Object error) => debugPrint('AgeLink kept the local schedule after a Firebase read error.'),
      );
      await _offerSetup();
    } on PlatformException {
      debugPrint('AgeLink could not start local reminder sync.');
    }
  }

  Future<void> _replace(QuerySnapshot<Map<String, dynamic>> snapshot) async {
    if (!mounted || snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) return;
    final medications = snapshot.docs.isEmpty
        ? const [] : snapshot.docs.first.data()['medications'];
    if (medications is! List) return;

    final doses = <Map<String, Object>>[];
    final clockPattern = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$');
    for (final medication in medications) {
      if (medication is! Map) continue;
      final times = medication['times'];
      final entries = times is List ? times : [medication['time']];
      for (final value in entries) {
        if (value is! String) continue;
        final match = clockPattern.firstMatch(value.trim());
        if (match == null) continue;
        doses.add({
          'minute': int.parse(match[1]!) * 60 + int.parse(match[2]!),
          'name': medication['name']?.toString().trim() ?? '',
        });
      }
    }

    try {
      await LocalReminderSync._channel.invokeMethod<void>('replace', {
        'uid': widget.uid,
        'doses': jsonEncode(doses),
      });
      await _offerSetup();
    } on PlatformException {
      debugPrint('AgeLink could not update the phone reminder schedule.');
    }
  }

  Future<void> _offerSetup() async {
    if (!mounted || _offeredSetup ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final status = await LocalReminderSync._status();
    if (!mounted || _offeredSetup || status == null || status['doses'] == 0 ||
        (status['notifications'] == true && status['exact'] == true)) {
      return;
    }

    _offeredSetup = true;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: const Text('Allow notifications and exact alarms for phone reminders.'),
      action: SnackBarAction(label: 'Set up', onPressed: LocalReminderSync._setUp),
    ));
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
      await _offerSetup();
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
      final status = await LocalReminderSync._status();
      if (mounted) setState(() => _status = status);
    } on PlatformException {
      if (mounted) setState(() => _status = null);
    }
  }

  Future<void> _setUp() async {
    await LocalReminderSync._setUp();
    await _readStatus();
  }

  Future<void> _test() async {
    String message;
    try {
      await LocalReminderSync._channel.invokeMethod<void>('test');
      message = 'Test notification scheduled for five seconds from now.';
    } on PlatformException catch (error) {
      message = error.message ?? 'Could not schedule the test notification.';
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _formatTime(Object? value) {
    if (value is! int || value <= 0) return 'None';
    return DateFormat('MMM d, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(value));
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
      detail = '${status['doses']} daily doses saved. Next ${_formatTime(status['next'])}.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.notifications_active_rounded),
          title: const Text('Phone reminders'),
          subtitle: Text(detail),
          trailing: const Icon(Icons.chevron_right),
          onTap: _setUp,
        ),
        if (status?['lastDelivery'] is int && (status!['lastDelivery'] as int) > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text("Last dose alert ${_formatTime(status['lastDelivery'])}"),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _test, child: const Text('Test notification')),
        ),
      ],
    );
  }
}
