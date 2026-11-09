import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'constants.dart';
import 'gradient_scaffold.dart';

class InviteMemberPage extends StatefulWidget {
  const InviteMemberPage({super.key});

  @override
  State<InviteMemberPage> createState() => _InviteMemberPageState();
}

class _InviteMemberPageState extends State<InviteMemberPage> {
  bool _isSharing = false;

  //add the download URL here inside ''
  static const String _downloadUrl = '';

  String get _invitationMessage {
    final String name = 'A family member';
    final String link = _downloadUrl.trim();
    final String linkSection = link.isEmpty
        ? 'Ask me for the AgeLink app installation details.'
        : 'Get AgeLink here: $link';

    return '''Hello!\n\n$name would like to invite you to discover AgeLink.\n\nAgeLink helps families stay informed about medication reminders and care routines for their loved ones.\n\n$linkSection\n\nThis invitation is a friendly introduction only. It does not grant access to anyone's health information or device.''';
  }

  Future<void> _shareInvitation() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);

    try {
      final renderObject = context.findRenderObject();
      final Rect? shareOrigin = renderObject is RenderBox
          ? renderObject.localToGlobal(Offset.zero) & renderObject.size
          : null;

      await SharePlus.instance.share(
        ShareParams(
          text: _invitationMessage,
          subject: 'Invitation to AgeLink',
          title: 'Invite a family member to AgeLink',
          sharePositionOrigin: shareOrigin,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open sharing: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Constants.lightBlue,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Constants.darkblue, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Constants.darkGrey,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyle(
                  color: Constants.mediumGrey,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: Text(
          'Invite Family',
          style: TextStyle(
            color: Constants.darkblue,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        leading: BackButton(color: Constants.darkblue),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: kPrimaryGradient,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: Constants.darkblue.withValues(alpha: 0.13),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Colors.white,
                              size: 27,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Care is better together',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Share AgeLink with family through your favorite messaging or email app.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'How it works',
                      style: TextStyle(
                        color: Constants.darkGrey,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Constants.darkblue.withValues(alpha: 0.09),
                        ),
                      ),
                      child: Column(
                        children: [
                          _infoCard(
                            icon: Icons.share_rounded,
                            title: 'Choose an app',
                            detail: 'Open the share menu and select Email, Messages, WhatsApp, or another compatible app.',
                          ),
                          const SizedBox(height: 22),
                          _infoCard(
                            icon: Icons.person_add_alt_1_rounded,
                            title: 'Choose your family member',
                            detail: 'Pick the recipient inside the selected app and review the invitation.',
                          ),
                          const SizedBox(height: 22),
                          _infoCard(
                            icon: Icons.send_rounded,
                            title: 'Send when ready',
                            detail: 'Confirm sending in that app. AgeLink will not send a message automatically.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Constants.lightBlue,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            color: Constants.darkblue,
                            size: 23,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Sharing an invitation does not provide access to medication data, family permissions, or the AgeLink device.',
                              style: TextStyle(
                                color: Constants.darkblue,
                                fontSize: 13,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                border: Border(
                  top: BorderSide(
                    color: Constants.darkblue.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: kPrimaryGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _isSharing ? null : _shareInvitation,
                    icon: _isSharing
                        ? const SizedBox(
                      height: 19,
                      width: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(
                      Icons.ios_share_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                    label: Text(
                      _isSharing ? 'Opening share options...' : 'Share invitation',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
