// lib/help_page.dart
import 'package:flutter/material.dart';
import 'constants.dart';
import 'gradient_scaffold.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Help Center', style: TextStyle(color: Color(0xFF0D47A1), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Constants.darkblue),
        centerTitle: true,
      ),
      body: Center(
        child: Text(
          'Help Page Content Goes Here',
          style: TextStyle(fontSize: 18, color: Constants.darkGrey, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}