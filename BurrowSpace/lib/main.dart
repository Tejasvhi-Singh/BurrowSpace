import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() {
  runApp(const BurrowSpaceApp());
}

class BurrowSpaceApp extends StatelessWidget {
  const BurrowSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Burrow Space',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  String? _peerCode;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final _progress = 0.0;
  final String serverUrl = "https://burrowspace.onrender.com";
  final encrypt.Key _encryptionKey = encrypt.Key.fromLength(32);
  final encrypt.IV _iv = encrypt.IV.fromLength(16);
  bool _permissionsGranted = false;
  bool _isConnected = false;
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _checkInternetConnection();
    _requestPermission();
  }

  void _log(String message) {
    _logs.add(message);
    debugPrint(message);
  }

  Future<void> _checkInternetConnection() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    setState(() {
      _isConnected = connectivityResult == ConnectivityResult.mobile || connectivityResult == ConnectivityResult.wifi;
    });
  }

  Future<void> _requestPermission() async {
    PermissionStatus storageStatus = await Permission.storage.request();

    if (storageStatus.isGranted) {
      _log("Storage permission granted.");
    } else {
      _log("Storage permission denied.");
      _showPermissionDialog();
    }

    if (_isConnected) {
      _log("Internet connection available.");
      _initializePeerConnection();
    } else {
      _log("Internet connection not available.");
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Permission Required"),
          content: const Text("This app needs storage permission to provide a better experience. Please enable it in the app settings."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text("Open Settings"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _initializePeerConnection() async {
    try {
      Map<String, dynamic> configuration = {
        "iceServers": [
          {"urls": "stun:stun.l.google.com:19302"}
        ]
      };
      _peerConnection = await createPeerConnection(configuration, {});

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        if (mounted) {
          _log("Connection state: $state");
        }
      };

      _dataChannel = await _peerConnection!.createDataChannel("fileTransfer", RTCDataChannelInit());
      _dataChannel!.onMessage = (RTCDataChannelMessage message) {
        if (mounted) {
          _log("Message received: ${message.text}");
          _receiveFile(message.text);
        }
      };

      setState(() {
        _peerCode = Uuid().v4().substring(0, 8);
      });

      var response = await http.get(Uri.parse("https://api64.ipify.org?format=json"));
      if (response.statusCode == 200) {
        String publicIP = jsonDecode(response.body)["ip"];
        await http.post(
          Uri.parse("$serverUrl/register"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"peerCode": _peerCode, "ip": publicIP}),
        );
        _log("Peer registered with IP: $publicIP");
        _log("Data channel state: ${_dataChannel!.state}");
        _log("UUID: $_peerCode");
      }
    } catch (e) {
      if (mounted) {
        _log("Error initializing peer connection: $e");
      }
    }
  }

  Future<void> _fetchReceiverIP() async {
    await _requestPermission();

    String? enteredPeerCode = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        TextEditingController peerCodeController = TextEditingController();
        return AlertDialog(
          title: const Text("Enter Receiver's Peer Code"),
          content: TextField(
            controller: peerCodeController,
            decoration: const InputDecoration(hintText: "Peer Code"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(peerCodeController.text),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );

    if (enteredPeerCode == null || enteredPeerCode.isEmpty) {
      return;
    }

    var response = await http.get(Uri.parse("$serverUrl/lookup/$enteredPeerCode"));
    var jsonData = jsonDecode(response.body);
    if (jsonData is Map<String, dynamic> && jsonData.containsKey("ip")) {
      String receiverIP = jsonData["ip"];
      await _pickAndSendFile(receiverIP);
      _log("Receiver IP: $receiverIP");
    }
  }

  Future<void> _pickAndSendFile(String receiverIP) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      List<int> fileBytes = await file.readAsBytes();
      String fileName = file.path.split('/').last;

      var encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey));
      String encryptedData = base64Encode(encrypter.encryptBytes(fileBytes, iv: _iv).bytes);

      String message = jsonEncode({
        "fileName": fileName,
        "data": encryptedData,
      });

      if (_dataChannel != null) {
        await _waitForDataChannelOpen();
        _dataChannel!.send(RTCDataChannelMessage(message));
        _log("File sent: $fileName");
        _log("Data channel state: ${_dataChannel!.state}");
        _log("UUID: $_peerCode");
      } else {
        _log("Data channel is not open.");
      }
    }
  }

  Future<void> _waitForDataChannelOpen() async {
    int retries = 10;
    while (_dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen && retries > 0) {
      await Future.delayed(const Duration(seconds: 1));
      retries--;
    }
  }

  void _receiveFile(String message) async {
    try {
      var decodedData = jsonDecode(message);
      String fileName = decodedData["fileName"];
      String fileData = decodedData["data"];

      var encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey));
      List<int> decryptedFileBytes = encrypter.decryptBytes(encrypt.Encrypted(base64Decode(fileData)), iv: _iv);

      Directory? downloadsDir = await getExternalStorageDirectory();
      if (downloadsDir != null) {
        String filePath = '${downloadsDir.path}/$fileName';
        File receivedFile = File(filePath);
        await receivedFile.writeAsBytes(decryptedFileBytes);
        _log("File received: $fileName");
      } else {
        _log("Downloads directory not found.");
      }
    } catch (e) {
      _log("Error receiving file: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF054640),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _peerCode == null
                  ? CircularProgressIndicator()
                  : Text(
                      "Your Peer Code: $_peerCode",
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
              const SizedBox(height: 20),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _fetchReceiverIP,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                child: const Text("SEND FILE"),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _initializePeerConnection,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                child: const Text("RECEIVE FILE"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}