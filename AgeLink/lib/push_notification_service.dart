
import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance =
  PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _databaseUrl =
      'https://agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app';

  static const AndroidNotificationChannel _channel =
  AndroidNotificationChannel(
    'agelink_medication_alerts',
    'Medication Alerts',
    description: 'AgeLink medication activity notifications',
    importance: Importance.max,
    playSound: true,
  );

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;

  bool _initialized = false;
  String? _registeredUserId;

  DatabaseReference get _database => FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: _databaseUrl,
  ).ref();

  Future<String> _deviceId() async {
    const key = 'agelink_push_device_id';

    final stored = await _storage.read(key: key);

    if (stored != null && stored.isNotEmpty) {
      return stored;
    }

    final random = Random.secure();

    final identifier = List<int>.generate(
      16,
          (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();

    await _storage.write(key: key, value: identifier);

    return identifier;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const settings = InitializationSettings(
      android: androidSettings,
    );

    await _localNotifications.initialize(
      settings: settings,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((user) async {
          if (user != null) {
            try {
              await registerDevice();
            } catch (error) {
              debugPrint('Push registration failed: $error');
            }
          } else {
            _registeredUserId = null;
          }
        });

    _tokenSubscription = _messaging.onTokenRefresh.listen((token) async {
      try {
        await _saveToken(token);
      } catch (error) {
        debugPrint('Push token refresh failed: $error');
      }
    });

    _messageSubscription =
        FirebaseMessaging.onMessage.listen((message) async {
          final notification = message.notification;

          if (notification == null) return;

          await _localNotifications.show(
            id: message.messageId.hashCode,
            title: notification.title ?? 'AgeLink',
            body: notification.body ?? 'New medication activity',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'agelink_medication_alerts',
                'Medication Alerts',
                channelDescription: 'AgeLink medication activity notifications',
                importance: Importance.max,
                priority: Priority.high,
                playSound: true,
              ),
            ),
          );
        });
  }

  Future<void> registerDevice() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final settings = await _messaging.getNotificationSettings();

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    final token = await _messaging.getToken();
    if (token == null) return;

    await _saveToken(token);
  }

  Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final deviceId = await _deviceId();

    await _database
        .child('pushTokens/${user.uid}/$deviceId')
        .set(token);

    _registeredUserId = user.uid;
  }

  Future<void> unregisterDevice() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final deviceId = await _deviceId();

    await _database
        .child('pushTokens/${user.uid}/$deviceId')
        .remove();

    _registeredUserId = null;
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();

    _initialized = false;
  }
}
