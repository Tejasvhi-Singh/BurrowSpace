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
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _peerCode;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  double _progress = 0.0;
  final String serverUrl = "https://burrowspace.onrender.com";
  final encrypt.Key _encryptionKey = encrypt.Key.fromLength(32);
  final encrypt.IV _iv = encrypt.IV.fromLength(16);

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _initializePeerConnection();
  }

  Future<void> _requestPermissions() async {
    while (true) {
      if (await Permission.storage.request().isGranted) {
        // Permissions are granted, proceed with file operations
        Directory? downloadsDir = await getExternalStorageDirectory();
        if (downloadsDir != null) {
          Directory burrowSpaceDir = Directory('${downloadsDir.path}/Burrow_Space_files');
          if (!await burrowSpaceDir.exists()) {
            await burrowSpaceDir.create(recursive: true);
            debugPrint("Folder created: ${burrowSpaceDir.path}");
          } else {
            debugPrint("Folder already exists: ${burrowSpaceDir.path}");
          }
        } else {
          debugPrint("Error: Unable to access downloads directory.");
        }
        break;
      } else if (await Permission.storage.isPermanentlyDenied) {
        // Handle the case when permissions are permanently denied
        debugPrint("Storage permission permanently denied.");
        openAppSettings();
        break;
      } else {
        // Handle the case when permissions are denied but not permanently
        debugPrint("Storage permission not granted. Asking again...");
      }
    }
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
        debugPrint("Connection state changed: $state");
      };

      _dataChannel = await _peerConnection!
          .createDataChannel("fileTransfer", RTCDataChannelInit());
      _dataChannel!.onMessage = (RTCDataChannelMessage message) {
        _receiveFile(message.text);
      };

      setState(() {
        _peerCode = Uuid().v4().substring(0, 8);
      });
      debugPrint("Generated Peer Code: $_peerCode");

      var response =
      await http.get(Uri.parse("https://api64.ipify.org?format=json"));
      if (response.statusCode == 200) {
        String publicIP = jsonDecode(response.body)["ip"];
        await http.post(
          Uri.parse("$serverUrl/register"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"peerCode": _peerCode, "ip": publicIP}),
        );
        debugPrint(
            "Registered receiver at IP: $publicIP with Peer Code: $_peerCode");
      } else {
        debugPrint("Failed to fetch public IP: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error initializing peer connection: $e");
    }
  }

  Future<void> _fetchReceiverIP() async {
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
      debugPrint("No peer code entered.");
      return;
    }

    var response = await http.get(Uri.parse("$serverUrl/lookup/$enteredPeerCode"));
    var jsonData = jsonDecode(response.body);
    if (jsonData is Map<String, dynamic> && jsonData.containsKey("ip")) {
      String receiverIP = jsonData["ip"];
      debugPrint("Resolved receiver IP: $receiverIP");
      await _pickAndSendFile(receiverIP);
    } else {
      debugPrint("Error: Unexpected response format: $jsonData");
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
        _dataChannel!.send(RTCDataChannelMessage(message));
        debugPrint("File sent: $fileName");
      } else {
        debugPrint("Data channel is not initialized.");
      }
    } else {
      debugPrint("File selection canceled.");
    }
  }

  void _receiveFile(String message) async {
    debugPrint("Received message: $message");
    try {
      var decodedData = jsonDecode(message);
      String fileName = decodedData["fileName"];
      String fileData = decodedData["data"];

      var encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey));
      List<int> decryptedFileBytes = encrypter
          .decryptBytes(encrypt.Encrypted(base64Decode(fileData)), iv: _iv);

      Directory? downloadsDir = await getExternalStorageDirectory();
      if (downloadsDir != null) {
        String filePath = '${downloadsDir.path}/$fileName';
        File receivedFile = File(filePath);
        await receivedFile.writeAsBytes(decryptedFileBytes);
        debugPrint("File successfully saved at: $filePath");
        debugPrint("File received: $fileName");
      } else {
        debugPrint("Error: Unable to access downloads directory.");
      }
    } catch (e) {
      debugPrint("Error receiving file: $e");
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
              Text(
                "Your Peer Code: $_peerCode",
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _fetchReceiverIP,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32.0, vertical: 16.0),
                  textStyle: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                child: const Text("SEND FILE"),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _initializePeerConnection,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32.0, vertical: 16.0),
                  textStyle: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
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