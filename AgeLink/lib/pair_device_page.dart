import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'constants.dart';
import 'gradient_scaffold.dart';


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
      Navigator.pop(context);
      Navigator.pop(context);
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

  void _showWifiDialog(String deviceId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(16)), child: Icon(Icons.wifi_rounded, color: Constants.darkblue, size: 28)),
            const SizedBox(height: 16),
            Text('Connect to Wi-Fi', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: Constants.darkblue)),
            const SizedBox(height: 8),
            Text('Enter the network details the AgeLink device should use.', style: TextStyle(fontSize: 14, height: 1.45, color: Constants.mediumGrey)),
            const SizedBox(height: 24),
            Text('Wi-Fi network name', style: TextStyle(fontWeight: FontWeight.w700, color: Constants.darkGrey)),
            const SizedBox(height: 8),
            TextField(controller: _ssidController, decoration: InputDecoration(hintText: 'Network name (SSID)', prefixIcon: Icon(Icons.router_rounded, color: Constants.darkblue), filled: true, fillColor: Constants.lightBlue.withValues(alpha: 0.45), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
            const SizedBox(height: 16),
            Text('Wi-Fi password', style: TextStyle(fontWeight: FontWeight.w700, color: Constants.darkGrey)),
            const SizedBox(height: 8),
            TextField(controller: _passwordController, obscureText: true, decoration: InputDecoration(hintText: 'Enter your password', prefixIcon: Icon(Icons.lock_outline_rounded, color: Constants.darkblue), filled: true, fillColor: Constants.lightBlue.withValues(alpha: 0.45), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
            const SizedBox(height: 26),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () { _bleService.disconnect(); Navigator.pop(context); }, style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), foregroundColor: Constants.darkblue), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(child: Container(decoration: BoxDecoration(gradient: kPrimaryGradient, borderRadius: BorderRadius.circular(14)), child: ElevatedButton(onPressed: () => _sendWifiCredentials(deviceId), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: const Text('Connect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(23), border: Border.all(color: Constants.darkblue.withValues(alpha: 0.07)), boxShadow: [BoxShadow(color: Constants.darkblue.withValues(alpha: 0.04), blurRadius: 18, offset: const Offset(0, 7))]),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: Text('Pair device', style: TextStyle(color: Constants.darkblue, fontWeight: FontWeight.w800, fontSize: 19)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Constants.darkblue),
        centerTitle: true,
        actions: [if (!_isLoading) IconButton(tooltip: 'Scan again', icon: Icon(Icons.refresh_rounded, color: Constants.darkblue), onPressed: _startScan)],
      ),
      body: _isLoading
          ? Center(child: _panel(child: const Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 18), Text('Connecting to your AgeLink device...', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700))])))
          : Column(children: [
        Expanded(child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          children: [
            Text('Set up AgeLink', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Constants.darkblue)),
            const SizedBox(height: 6),
            Text('Find and connect your loved one’s medication reminder device.', style: TextStyle(color: Constants.mediumGrey, height: 1.45, fontSize: 14)),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: kPrimaryGradient, borderRadius: BorderRadius.circular(24)),
              child: Row(children: [
                Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.bluetooth_searching_rounded, color: Colors.white, size: 30)),
                const SizedBox(width: 15),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_isScanning ? 'Looking for nearby devices' : 'Device discovery', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(_isScanning ? 'Scanning for AgeLink devices…' : 'Select a device below to continue', style: const TextStyle(color: Colors.white, fontSize: 13)),
                ])),
                if (_isScanning) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              ]),
            ),
            const SizedBox(height: 26),
            Row(children: [
              Expanded(child: Text('Available devices', style: TextStyle(color: Constants.darkGrey, fontSize: 19, fontWeight: FontWeight.w800))),
              Text('${_scanResults.length} found', style: TextStyle(color: Constants.mediumGrey, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            if (_scanResults.isEmpty)
              _panel(child: Column(children: [
                const SizedBox(height: 12),
                Container(width: 74, height: 74, decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(23)), child: Icon(_isScanning ? Icons.bluetooth_searching_rounded : Icons.devices_other_rounded, color: Constants.darkblue, size: 36)),
                const SizedBox(height: 20),
                Text(_isScanning ? 'Searching for devices' : 'No AgeLink devices found', style: TextStyle(fontSize: 18, color: Constants.darkGrey, fontWeight: FontWeight.w800)),
                const SizedBox(height: 9),
                Text(_isScanning ? 'Keep the device nearby while scanning.' : 'Make sure the device is powered on, then use the refresh icon to scan again.', textAlign: TextAlign.center, style: TextStyle(color: Constants.mediumGrey, fontSize: 14, height: 1.5)),
                const SizedBox(height: 12),
              ]))
            else
              ..._scanResults.map((result) {
                final deviceName = result.device.platformName.isNotEmpty ? result.device.platformName : 'Unknown Device';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(color: Colors.transparent, child: InkWell(
                    borderRadius: BorderRadius.circular(23),
                    onTap: () => _connectToDevice(result.device),
                    child: _panel(child: Row(children: [
                      Container(width: 50, height: 50, decoration: BoxDecoration(color: Constants.lightBlue, borderRadius: BorderRadius.circular(15)), child: Icon(Icons.memory_rounded, color: Constants.darkblue, size: 25)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(deviceName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Constants.darkGrey)),
                        const SizedBox(height: 5),
                        Text(result.device.remoteId.toString(), overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Constants.mediumGrey)),
                      ])),
                      Icon(Icons.chevron_right_rounded, color: Constants.darkblue),
                    ])),
                  )),
                );
              }),
          ],
        )),
      ]),
    );
  }
}