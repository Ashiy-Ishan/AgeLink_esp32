import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'invite_member_page.dart' hide kPrimaryGradient;
import 'family_invitation_service.dart';
import 'gradient_scaffold.dart';
import 'constants.dart';
import 'custom_snackbar.dart';

class FamilyPermissionsPage extends StatefulWidget {
  const FamilyPermissionsPage({super.key});

  @override
  State<FamilyPermissionsPage> createState() => _FamilyPermissionsPageState();
}

class _FamilyPermissionsPageState extends State<FamilyPermissionsPage> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  late final Stream<QuerySnapshot> _familyStream;
  final String appId = kAppId;
  String? _processingInvitation;
  bool _savingAccess = false;

  @override
  void initState() {
    super.initState();
    if (currentUser != null) {
      _familyStream = FirebaseFirestore.instance
          .collection('artifacts')
          .doc(appId)
          .collection('users')
          .doc(currentUser!.uid)
          .collection('family_members')
          .snapshots();
    } else {
      _familyStream = const Stream.empty();
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
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: isEnabled ? gradient : LinearGradient(colors: [Constants.mediumGrey, Constants.mediumGrey.withValues(alpha: 0.7)], begin: Alignment.centerLeft, end: Alignment.centerRight),
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

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Constants.lightBlue),
              boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(22)),
                child: Icon(Icons.family_restroom_rounded, color: Constants.darkblue, size: 38)),
            const SizedBox(height: 18),
            Text('Your care circle starts here', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Constants.darkGrey)),
            const SizedBox(height: 8),
            Text('Invite a family member to share medication schedules and updates.', textAlign: TextAlign.center,
                style: TextStyle(color: Constants.mediumGrey, fontSize: 14, height: 1.5)),
          ]),
        ),
      ),
    );
  }

  Widget _buildMemberCard(String name, String mode) {
    final bool isFullMode = mode == 'Full Mode';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Constants.darkblue.withValues(alpha: 0.08)),
          boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 5))]),
      child: Row(children: [
        Container(width: 50, height: 50, decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(16)),
            child: Icon(Icons.person_outline_rounded, color: Constants.darkblue, size: 27)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Constants.darkGrey, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(isFullMode ? Icons.admin_panel_settings_outlined : Icons.visibility_outlined, size: 15,
                color: isFullMode ? Constants.darkblue : Constants.mediumGrey),
            const SizedBox(width: 5),
            Flexible(child: Text(mode, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: isFullMode ? Constants.darkblue : Constants.mediumGrey, fontSize: 12, fontWeight: FontWeight.w700))),
          ]),
        ])),
      ]),
    );
  }

  Future<void> _handleInvitation(
      QueryDocumentSnapshot<Map<String, dynamic>> invitation,
      bool accept) async {
    if (_processingInvitation != null) return;
    setState(() => _processingInvitation = invitation.id);
    try {
      if (accept) {
        await FamilyInvitationService.acceptInvitation(invitation);
      } else {
        await FamilyInvitationService.declineInvitation(invitation);
      }
      if (!mounted) return;
      CustomSnackBar.show(
        context: context,
        message: accept ? 'Invitation accepted.' : 'Invitation declined.',
      );
    } catch (error) {
      if (!mounted) return;
      CustomSnackBar.show(
        context: context,
        message: error.toString(),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _processingInvitation = null);
    }
  }

  Widget _emailVerificationCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Constants.lightBlue),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Verify your email to use invitations',
            style: TextStyle(color: Constants.darkGrey,
                fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Invitations are linked to your verified email address.',
            style: TextStyle(color: Constants.mediumGrey)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
            onPressed: () async {
              try {
                await FirebaseAuth.instance.currentUser!.sendEmailVerification();
                if (!mounted) return;
                CustomSnackBar.show(context: context,
                    message: 'Verification email sent. Check your inbox.');
              } catch (error) {
                if (!mounted) return;
                CustomSnackBar.show(context: context,
                    message: error.toString(), isError: true);
              }
            },
            child: const Text('Send verification email'),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.currentUser?.reload();
              if (mounted) setState(() {});
            },
            child: const Text('I have verified'),
          ),
        ]),
      ]),
    );
  }

  Widget _invitationSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FamilyInvitationService.receivedInvitations(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Unable to load invitations: ${snapshot.error}',
                style: TextStyle(color: Constants.redColor)),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()));
        }
        final pending = snapshot.data!.docs
            .where((doc) => doc.data()['status'] == 'pending')
            .toList();
        final accepted = snapshot.data!.docs
            .where((doc) => doc.data()['status'] == 'accepted')
            .toList();
        if (pending.isEmpty && accepted.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (pending.isNotEmpty) ...[
            Text('Invitations for you',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800,
                    color: Constants.darkGrey)),
            const SizedBox(height: 12),
            ...pending.map((doc) {
              final info = doc.data();
              final busy = _processingInvitation != null;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Constants.lightBlue),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(info['ownerName']?.toString() ?? 'Care group',
                      style: TextStyle(color: Constants.darkGrey,
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('Invited you with ${info['mode'] ?? 'View Mode'} access',
                      style: TextStyle(color: Constants.mediumGrey)),
                  const SizedBox(height: 15),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: busy ? null : () => _handleInvitation(doc, false),
                      child: const Text('Decline'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      onPressed: busy ? null : () => _handleInvitation(doc, true),
                      child: const Text('Accept', style: TextStyle(color: Colors.white)),
                    )),
                  ]),
                ]),
              );
            }),
            const SizedBox(height: 18),
          ],
          if (accepted.isNotEmpty) ...[
            Text('Care groups shared with you',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800,
                    color: Constants.darkGrey)),
            const SizedBox(height: 10),
            ...accepted.map((doc) {
              final info = doc.data();
              return _buildMemberCard(
                info['ownerName']?.toString() ?? 'Care group',
                info['mode']?.toString() ?? 'View Mode',
              );
            }),
            const SizedBox(height: 18),
          ],
        ]);
      },
    );
  }

  Widget _sentInvitationSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FamilyInvitationService.sentInvitations(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) {
          return snapshot.hasError
              ? Text('Unable to load sent invitations.',
              style: TextStyle(color: Constants.redColor))
              : const SizedBox.shrink();
        }
        final pending = snapshot.data!.docs
            .where((doc) => doc.data()['status'] == 'pending').toList();
        if (pending.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 22),
          Text('Awaiting acceptance',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800,
                  color: Constants.darkGrey)),
          const SizedBox(height: 12),
          ...pending.map((doc) {
            final info = doc.data();
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Icon(Icons.mark_email_unread_outlined, color: Constants.darkblue),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(info['recipientEmail']?.toString() ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Constants.darkGrey,
                              fontWeight: FontWeight.w700)),
                      Text('Pending · ${info['mode'] ?? 'View Mode'}',
                          style: TextStyle(color: Constants.mediumGrey, fontSize: 12)),
                    ])),
              ]),
            );
          }),
        ]);
      },
    );
  }

  CollectionReference<Map<String, dynamic>> get _membersRef =>
      FirebaseFirestore.instance
          .collection('artifacts')
          .doc(appId)
          .collection('users')
          .doc(currentUser!.uid)
          .collection('family_members');

  DocumentReference<Map<String, dynamic>> _invitationRef(String invitationId) =>
      FirebaseFirestore.instance
          .collection('artifacts')
          .doc(appId)
          .collection('family_invitations')
          .doc(invitationId);

  Future<void> _saveMemberMode(
      QueryDocumentSnapshot<Map<String, dynamic>> member,
      String mode,
      ) async {
    if (_savingAccess || currentUser == null) return;
    final data = member.data();
    final invitationId = data['invitationId']?.toString() ?? '';
    if (invitationId.isEmpty) {
      CustomSnackBar.show(
        context: context,
        message: 'This member has no linked invitation. Access cannot be edited here.',
        isError: true,
      );
      return;
    }
    setState(() => _savingAccess = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.update(member.reference, {'mode': mode});
      batch.update(_invitationRef(invitationId), {
        'mode': mode,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (!mounted) return;
      CustomSnackBar.show(context: context, message: 'Member role updated to $mode.');
    } catch (error) {
      if (!mounted) return;
      CustomSnackBar.show(context: context, message: error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _savingAccess = false);
    }
  }

  Future<void> _removeMember(
      QueryDocumentSnapshot<Map<String, dynamic>> member,
      ) async {
    if (_savingAccess || currentUser == null) return;
    final data = member.data();
    final invitationId = data['invitationId']?.toString() ?? '';
    if (invitationId.isEmpty) {
      CustomSnackBar.show(
        context: context,
        message: 'This member has no linked invitation. Removal needs manual review.',
        isError: true,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove family member?'),
        content: Text('Remove ${data['name'] ?? data['email'] ?? 'this member'} from your care circle?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _savingAccess = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.delete(member.reference);
      batch.update(_invitationRef(invitationId), {
        'status': 'revoked',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (!mounted) return;
      CustomSnackBar.show(context: context, message: 'Member removed from care circle.');
    } catch (error) {
      if (!mounted) return;
      CustomSnackBar.show(context: context, message: error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _savingAccess = false);
    }
  }

  Future<void> _editMember(
      QueryDocumentSnapshot<Map<String, dynamic>> member,
      ) async {
    if (_savingAccess) return;
    final data = member.data();
    final currentMode = data['mode'] == 'Full Mode' ? 'Full Mode' : 'View Mode';
    String selectedMode = currentMode;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Edit family member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data['name']?.toString() ?? 'Family member',
                style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                data['email']?.toString() ?? '',
                style: TextStyle(color: Constants.mediumGrey, fontSize: 13),
              ),
              const SizedBox(height: 18),
              const Text('Care circle role', style: TextStyle(fontWeight: FontWeight.w700)),
              RadioListTile<String>(
                title: const Text('View Mode'),
                subtitle: const Text('Stored role; medication read access is not enabled yet.'),
                value: 'View Mode',
                groupValue: selectedMode,
                onChanged: (value) => setDialogState(() => selectedMode = value!),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<String>(
                title: const Text('Full Mode'),
                subtitle: const Text('Stored role; medication editing is not enabled yet.'),
                value: 'Full Mode',
                groupValue: selectedMode,
                onChanged: (value) => setDialogState(() => selectedMode = value!),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _removeMember(member);
              },
              child: const Text('Remove member', style: TextStyle(color: Colors.redAccent)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedMode == currentMode
                  ? null
                  : () {
                Navigator.pop(dialogContext);
                _saveMemberMode(member, selectedMode);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditAccess() {
    if (currentUser == null || _savingAccess) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit access', style: TextStyle(color: Constants.darkblue, fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Manage care circle members and stored roles.', style: TextStyle(color: Constants.mediumGrey)),
              const SizedBox(height: 12),
              Flexible(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _membersRef.snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return const Text('Unable to load family members.');
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final members = snapshot.data!.docs;
                    if (members.isEmpty) return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No family members to manage yet.'),
                    );
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: members.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final member = members[index];
                        final data = member.data();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Constants.lightBlue,
                            child: Icon(Icons.person_outline_rounded, color: Constants.darkblue),
                          ),
                          title: Text(data['name']?.toString() ?? 'Family member', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${data['email'] ?? ''} · ${data['mode'] ?? 'View Mode'}', maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _editMember(member),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'These roles currently describe care circle membership only. They do not unlock medication or device data.',
                style: TextStyle(fontSize: 12, color: Constants.mediumGrey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInviteButton(BuildContext context) {
    return SizedBox(width: double.infinity, height: 54,
      child: DecoratedBox(decoration: BoxDecoration(gradient: kPrimaryGradient, borderRadius: BorderRadius.circular(16)),
        child: ElevatedButton.icon(
          onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (context) => const InviteMemberPage())); },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
          label: const Text('Invite family member', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) return const GradientScaffold(body: Center(child: Text('Please log in to view family members.')));
    return GradientScaffold(
      appBar: AppBar(title: Text('Family & permissions', style: TextStyle(color: Constants.darkblue, fontWeight: FontWeight.w700, fontSize: 18)),
          backgroundColor: Colors.transparent, elevation: 0, leading: BackButton(color: Constants.darkblue), centerTitle: true),
      body: SafeArea(child: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: _familyStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Text('Error loading family members.', style: TextStyle(color: Constants.mediumGrey)));
            final members = snapshot.data?.docs ?? [];
            return ListView(physics: const BouncingScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
              Container(padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(gradient: kPrimaryGradient, borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.17), blurRadius: 20, offset: const Offset(0, 8))]),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('YOUR CARE CIRCLE', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Text('${members.length} family member${members.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 7),
                    const Text('Stay connected with the people supporting your loved ones.',
                        style: TextStyle(color: Colors.white, fontSize: 13, height: 1.45)),
                  ])),
                  const SizedBox(width: 12),
                  const Icon(Icons.family_restroom_rounded, color: Colors.white70, size: 44),
                ]),
              ),
              const SizedBox(height: 26),
              Text('Family members', style: TextStyle(color: Constants.darkGrey, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text('See who has access to your care group.', style: TextStyle(color: Constants.mediumGrey, fontSize: 13)),
              const SizedBox(height: 16),
              if (FirebaseAuth.instance.currentUser?.emailVerified == true &&
                  FirebaseAuth.instance.currentUser?.email != null)
                _invitationSection()
              else
                _emailVerificationCard(),
              if (members.isEmpty) _buildEmptyState(context)
              else ...members.map((doc) {
                final member = doc.data() as Map<String, dynamic>;
                return _buildMemberCard(member['name'] ?? 'Unknown Name', member['mode'] ?? 'View Mode');
              }),
              _sentInvitationSection(),
            ]);
          },
        )),
        Container(padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9),
              border: Border(top: BorderSide(color: Constants.darkblue.withValues(alpha: 0.08)))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _buildInviteButton(context),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _showEditAccess,
              icon: Icon(Icons.manage_accounts_outlined, color: Constants.darkblue, size: 19),
              label: Text('Edit access', style: TextStyle(color: Constants.darkblue, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ])),
    );
  }
}
