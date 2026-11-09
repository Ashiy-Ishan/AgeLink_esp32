import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'constants.dart';

class FamilyInvitationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _invitations =>
      _db.collection('artifacts').doc(kAppId).collection('family_invitations');

  static CollectionReference<Map<String, dynamic>> _members(String ownerUid) =>
      _db.collection('artifacts').doc(kAppId).collection('users')
          .doc(ownerUid).collection('family_members');

  static String get _email {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null || user.email!.trim().isEmpty) {
      throw StateError('Sign in with an email account to manage invitations.');
    }
    if (!user.emailVerified) {
      throw StateError('Verify your email address before managing family invitations.');
    }
    return user.email!.trim().toLowerCase();
  }

  static User get _user {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('You must be signed in.');
    return user;
  }

  static String _invitationId(String uid, String email) {
    final encoded = base64Url.encode(utf8.encode(email)).replaceAll('=', '');
    return '${uid}_$encoded';
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> receivedInvitations() {
    return _invitations.where('recipientEmail', isEqualTo: _email).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> sentInvitations() {
    return _invitations.where('ownerUid', isEqualTo: _user.uid).snapshots();
  }

  static Future<void> sendInvitation({required String email, required String mode}) async {
    final sender = _user;
    final senderEmail = _email;
    final recipient = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(recipient)) {
      throw ArgumentError('Enter a valid email address.');
    }
    if (recipient == senderEmail) {
      throw ArgumentError('You cannot invite your own account.');
    }
    if (mode != 'View Mode' && mode != 'Full Mode') {
      throw ArgumentError('Invalid access level.');
    }
    final ref = _invitations.doc(_invitationId(sender.uid, recipient));
    final senderName = (sender.displayName ?? '').trim();
    await _db.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (existing.exists) {
        final status = (existing.data()?['status'] ?? '').toString();
        if (status == 'pending') {
          throw StateError('An invitation is already pending for this address.');
        }
        if (status == 'accepted') {
          throw StateError('This family member has already accepted your invitation.');
        }
        throw StateError('This invitation was declined. Contact support to re-invite this address.');
      }
      transaction.set(ref, {
        'ownerUid': sender.uid,
        'ownerEmail': senderEmail,
        'ownerName': senderName.isNotEmpty ? senderName : senderEmail,
        'recipientEmail': recipient,
        'mode': mode,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> acceptInvitation(
      QueryDocumentSnapshot<Map<String, dynamic>> invitation) async {
    final recipient = _user;
    final recipientEmail = _email;
    final ref = invitation.reference;
    final data = invitation.data();
    if (data['recipientEmail'] != recipientEmail || data['status'] != 'pending') {
      throw StateError('This invitation is no longer available.');
    }
    final ownerUid = data['ownerUid'] as String;
    final memberRef = _members(ownerUid).doc(recipient.uid);
    await _db.runTransaction((transaction) async {
      final latest = await transaction.get(ref);
      if (!latest.exists || latest.data()?['status'] != 'pending') {
        throw StateError('This invitation has already been processed.');
      }
      final existingMember = await transaction.get(memberRef);
      if (existingMember.exists) {
        throw StateError('Your account is already in this care group.');
      }
      transaction.set(memberRef, {
        'uid': recipient.uid,
        'name': (recipient.displayName ?? '').trim().isNotEmpty
            ? recipient.displayName!.trim()
            : recipientEmail,
        'email': recipientEmail,
        'mode': data['mode'],
        'invitationId': invitation.id,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(ref, {
        'status': 'accepted',
        'acceptedByUid': recipient.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> declineInvitation(
      QueryDocumentSnapshot<Map<String, dynamic>> invitation) async {
    final recipient = _user;
    if (invitation.data()['recipientEmail'] != _email) {
      throw StateError('This invitation is not addressed to you.');
    }
    await _db.runTransaction((transaction) async {
      final latest = await transaction.get(invitation.reference);
      if (!latest.exists || latest.data()?['status'] != 'pending') {
        throw StateError('This invitation is no longer pending.');
      }
      transaction.update(invitation.reference, {
        'status': 'declined',
        'declinedByUid': recipient.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
