// lib/pair_device_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'constants.dart';
import 'gradient_scaffold.dart';

const kPrimaryGradient = LinearGradient(
  colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class PairDevicePage extends StatefulWidget {
  const PairDevicePage({super.key});

  @override
  State<PairDevicePage> createState() => _PairDevicePageState();
}

class _PairDevicePageState extends State<PairDevicePage> {
  final BleService _bleService = BleService();

  bool _isScanning = false;
  List<ScanResult> _scanResults = [];
  StreamSubscription? _scanSub;
  bool _isLoading = false;

  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bleService.listenToAdapterState(() {
      if (mounted) {
        _showBluetoothOffDialog();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _startScan();
      }
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _bleService.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showBluetoothOffDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.bluetooth_disabled_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 10),
            const Text('Bluetooth is Off'),
          ],
        ),
        content: Text(
          'Please turn on Bluetooth to connect your AgeLink device.',
          style: TextStyle(color: Constants.darkGrey, fontSize: 16),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E88E5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _startScan() {
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      _showBluetoothOffDialog();
      return;
    }

    setState(() {
      _isScanning = true;
      _scanResults = [];
    });

    _scanSub = _bleService.scanForDevices().listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results;
        });
      }
    }, onError: (e) {
      debugPrint('Scan Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan Error: $e')));
      }
    });

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        _bleService.stopScan();
        setState(() {
          _isScanning = false;
        });
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() { _isLoading = true; });

    try {
      await _bleService.connectToDevice(device);
      if (!mounted) return;
      _showWifiDialog(device.remoteId.toString());

    } catch (e) {
      debugPrint('Connection Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: $e'))
      );
    } finally {
      if(mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  Future<void> _sendWifiCredentials(String deviceId) async {
    if (_ssidController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    setState(() { _isLoading = true; });

    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: You are not logged in.')),
      );
      setState(() { _isLoading = false; });
      return;
    }

    final String ssid = _ssidController.text;
    final String pass = _passwordController.text;
    final String userId = currentUser.uid;

    const String fbHost = "agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app";
    const String fbAuth = "iVNn4iHyjp2TizXHcx0QgrwGyEboJba8pxuDVLGm";

    final Map<String, dynamic> provisioningData = {
      "ssid": ssid,
      "pass": pass,
      "user_id": userId,
      "fb_host": fbHost,
      "fb_auth": fbAuth,
    };

    final String jsonString = jsonEncode(provisioningData);

    try {
      await _bleService.sendWifiCredentials(jsonString);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({'pairedDeviceId': deviceId}, SetOptions(merge: true));

      await _bleService.disconnect();

      if (!mounted) return;
      Navigator.pop(context); // Close the WiFi dialog
      Navigator.pop(context); // Go back to the home screen
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device paired successfully!')),
      );

    } catch (e) {
      debugPrint('Error sending credentials or saving to Firestore: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Could not complete pairing.')),
      );
    } finally {
      if(mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  // --- PREMIUM UI: Styled WiFi Credential Dialog ---
  void _showWifiDialog(String deviceId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_rounded, size: 40, color: Color(0xFF1E88E5)),
              ),
              const SizedBox(height: 16),
              Text(
                'Connect to WiFi',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Constants.darkGrey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your home network details to put AgeLink online.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Constants.mediumGrey),
              ),
              const SizedBox(height: 24),

              // Styled SSID Input
              TextField(
                controller: _ssidController,
                style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'WiFi Name (SSID)',
                  prefixIcon: const Icon(Icons.router_rounded, color: Color(0xFF1E88E5)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Styled Password Input
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'WiFi Password',
                  prefixIcon: const Icon(Icons.lock_rounded, color: Color(0xFF1E88E5)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        _bleService.disconnect();
                        Navigator.pop(context);
                      },
                      child: Text('Cancel', style: TextStyle(color: Constants.mediumGrey, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: kPrimaryGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _sendWifiCredentials(deviceId),
                        child: const Text('Connect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text(
          'Pair Device',
          style: TextStyle(color: Color(0xFF0D47A1), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Constants.darkblue),
        centerTitle: true,
        actions: [
          if (!_isLoading) // Hide refresh while loading
            IconButton(
              icon: Icon(_isScanning ? Icons.stop_rounded : Icons.refresh_rounded, color: Constants.darkblue),
              onPressed: _startScan,
            ),
        ],
      ),
      body: _isLoading
          ? Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)
              ]
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF1E88E5)),
              SizedBox(height: 16),
              Text('Connecting...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            child: Text(
              'Available Devices',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Constants.darkGrey,
              ),
            ),
          ),
          Expanded(
            child: _scanResults.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isScanning) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const CircularProgressIndicator(color: Color(0xFF1E88E5)),
                    ),
                    const SizedBox(height: 24),
                    Text('Scanning for AgeLink devices...', style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.w600, fontSize: 16)),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.bluetooth_searching_rounded, size: 48, color: Constants.mediumGrey),
                    ),
                    const SizedBox(height: 24),
                    Text('No devices found.', style: TextStyle(color: Constants.darkGrey, fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 8),
                    Text('Tap the refresh icon to scan again.', style: TextStyle(color: Constants.mediumGrey)),
                  ]
                ],
              ),
            )
                : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _scanResults.length,
              itemBuilder: (context, index) {
                var result = _scanResults[index];
                final deviceName = result.device.platformName.isNotEmpty
                    ? result.device.platformName
                    : 'Unknown Device';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _connectToDevice(result.device),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.memory_rounded, color: Color(0xFF1E88E5)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    deviceName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Constants.darkGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    result.device.remoteId.toString(),
                                    style: TextStyle(
                                      color: Constants.mediumGrey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}