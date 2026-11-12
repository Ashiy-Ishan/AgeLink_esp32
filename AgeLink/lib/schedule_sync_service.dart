import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;

class ScheduleSyncService {
  static DocumentReference<Map<String, dynamic>> _user(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  static Future<bool> save(
    String uid,
    String name,
    List<Map<String, dynamic>> medications, {
    String? scheduleId,
  }) async {
    final user = _user(uid);
    final schedules = user.collection('medicationSchedules');
    final existingActive = scheduleId == null
        ? await schedules.where('isActive', isEqualTo: true).get()
        : null;
    final target = scheduleId == null ? schedules.doc() : schedules.doc(scheduleId);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final userData = (await transaction.get(user)).data() ?? {};
      final revision = (userData['scheduleSyncRevision'] as num?)?.toInt() ?? 0;
      final activeId = userData['activeMedicationScheduleId'] as String?;
      final data = {'scheduleName': name, 'medications': medications};

      if (scheduleId == null) {
        final activeIds = {
          if (activeId != null) activeId,
          ...existingActive!.docs.map((doc) => doc.id),
        };
        // Read each document so a concurrent deletion cannot break activation.
        final activeDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final id in activeIds) {
          activeDocs.add(await transaction.get(schedules.doc(id)));
        }
        for (final doc in activeDocs) {
          if (doc.exists) transaction.update(doc.reference, {'isActive': false});
        }
        transaction.set(target, {
          ...data,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
        _markRevision(transaction, user, target.id, revision + 1);
      } else {
        final old = await transaction.get(target);
        if (!old.exists) throw StateError('This schedule no longer exists.');
        transaction.update(target, data);
        if (activeId == target.id ||
            (revision == 0 && old.data()?['isActive'] == true)) {
          _markRevision(transaction, user, target.id, revision + 1);
        }
      }
    });

    return triggerSync(uid);
  }

  static Future<bool> delete(String uid, String scheduleId) async {
    final user = _user(uid);
    final target = user.collection('medicationSchedules').doc(scheduleId);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final userData = (await transaction.get(user)).data() ?? {};
      final old = await transaction.get(target);
      if (!old.exists) return;
      final revision = (userData['scheduleSyncRevision'] as num?)?.toInt() ?? 0;
      final activeId = userData['activeMedicationScheduleId'];
      transaction.delete(target);
      if (activeId == target.id ||
          (revision == 0 && old.data()?['isActive'] == true)) {
        _markRevision(transaction, user, null, revision + 1);
      }
    });
    return triggerSync(uid);
  }

  static void _markRevision(
    Transaction transaction,
    DocumentReference<Map<String, dynamic>> user,
    String? scheduleId,
    int revision,
  ) {
    transaction.set(user, {
      'activeMedicationScheduleId': scheduleId,
      'scheduleSyncRevision': revision,
    }, SetOptions(merge: true));
  }

  // Firestore is authoritative. Opening Home retries a failed RTDB update.
  static Future<bool> triggerSync(String uid) async {
    try {
      final user = _user(uid);
      final snapshot = await FirebaseFirestore.instance.runTransaction((transaction) async {
        final data = (await transaction.get(user)).data();
        final revision = (data?['scheduleSyncRevision'] as num?)?.toInt() ?? 0;
        final activeId = data?['activeMedicationScheduleId'] as String?;
        final schedule = revision > 0 && activeId != null
            ? await transaction.get(user.collection('medicationSchedules').doc(activeId))
            : null;
        return (revision, schedule?.data()?['medications']);
      });
      final (revision, medications) = snapshot;
      if (revision == 0) return true;

      final doses = <String, Map<String, String>>{};
      final occurrences = <String, int>{};
      if (medications is List) {
        for (final (index, med) in medications.indexed) {
          if (med is! Map || med['times'] is! List) continue;
          final name = med['name']?.toString().trim() ?? '';
          if (name.isEmpty) continue;
          for (final value in med['times'] as List) {
            final time = value.toString();
            if (!RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(time)) continue;
            final normalizedTime = time.padLeft(5, '0');
            final dosage = med['dosage']?.toString() ?? '';
            final identity = base64Url.encode(
              utf8.encode(jsonEncode([name, dosage, normalizedTime])),
            );
            final baseKey = identity.length <= 700
                ? 'dose_$identity'
                : 'dose_${index}_${normalizedTime.replaceAll(':', '')}';
            final occurrence = occurrences.update(baseKey, (int previous) => previous + 1, ifAbsent: () => 0);
            doses['${baseKey}_$occurrence'] = {
              'name': name,
              'dosage': dosage,
              'time': normalizedTime,
            };
          }
        }
      }

      final scheduleRef = rtdb.FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app',
      ).ref('reminders/$uid/schedule');
      await scheduleRef.runTransaction((value) {
        final current = value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
        final currentRevision = (current['source_revision'] as num?)?.toInt() ?? 0;
        if (currentRevision >= revision) return rtdb.Transaction.abort();
        current['source_revision'] = revision;
        current['current_status'] = 'IDLE';
        if (doses.isEmpty) {
          current.remove('med_times');
        } else {
          current['med_times'] = doses;
        }
        return rtdb.Transaction.success(current);
      }, applyLocally: false);
      return true;
    } catch (_) {
      return false;
    }
  }
}
