import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;

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
  final double _progress = 0.0;
  final String serverUrl = "https://burrowspace.onrender.com";
  final encrypt.Key _encryptionKey = encrypt.Key.fromLength(32);
  final encrypt.IV _iv = encrypt.IV.fromLength(16);

  @override
  void initState() {
    super.initState();
    _initializePeerConnection();
  }

  Future<void> _initializePeerConnection() async {
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
    String publicIP = jsonDecode(response.body)["ip"];
    await http.post(
      Uri.parse("$serverUrl/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"peerCode": _peerCode, "ip": publicIP}),
    );
    debugPrint(
        "Registered receiver at IP: $publicIP with Peer Code: $_peerCode");
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
              onPressed: () =>
                  Navigator.of(context).pop(peerCodeController.text),
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

    var response =
        await http.get(Uri.parse("$serverUrl/lookup/$enteredPeerCode"));
    var jsonData = jsonDecode(response.body);
    if (jsonData is Map<String, dynamic> && jsonData.containsKey("ip")) {
      String receiverIP = jsonData["ip"];
      debugPrint("Resolved receiver IP: $receiverIP");
      // Proceed with sending the file
    } else {
      debugPrint("Error: Unexpected response format: $jsonData");
    }
  }

  void _receiveFile(String message) async {
    var decodedData = jsonDecode(message);
    String fileName = decodedData["fileName"];
    String fileData = decodedData["data"];

    var encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey));
    List<int> decryptedFileBytes = encrypter
        .decryptBytes(encrypt.Encrypted(base64Decode(fileData)), iv: _iv);

    Directory? downloadsDir = await getExternalStorageDirectory();
    File receivedFile = File('${downloadsDir!.path}/$fileName');
    await receivedFile.writeAsBytes(decryptedFileBytes);
    debugPrint("File successfully saved at: ${receivedFile.path}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF054640),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Your Peer Code: $_peerCode",
                style: const TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 20),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _fetchReceiverIP,
              child: const Text("SEND FILE",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _initializePeerConnection,
              child: const Text("RECEIVE FILE",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
