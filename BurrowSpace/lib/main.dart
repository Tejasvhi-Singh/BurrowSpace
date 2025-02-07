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
  runApp(BurrowSpaceApp());
}

class BurrowSpaceApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Burrow Space',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _peerCode;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final String serverUrl = "https://burrowspace.onrender.com"; // Replace with actual discovery server
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
      print("Connection state changed: $state");
    };

    _dataChannel = await _peerConnection!.createDataChannel("fileTransfer", RTCDataChannelInit());
    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      _receiveFile(message.text);
    };
  }

  void _sendFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      String filePath = result.files.single.path!;
      String fileName = result.files.single.name;
      File file = File(filePath);
      List<int> fileBytes = await file.readAsBytes();

      var encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey));
      String encryptedFile = base64Encode(encrypter.encryptBytes(fileBytes, iv: _iv).bytes);

      _dataChannel?.send(RTCDataChannelMessage(jsonEncode({"fileName": fileName, "data": encryptedFile})));
      print("File sent successfully: $fileName");
    } else {
      print("No file selected");
    }
  }

  Future<void> _receiveFile(String message) async {
    var decodedData = jsonDecode(message);
    String fileName = decodedData["fileName"];
    String fileData = decodedData["data"];

    var encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey));
    List<int> decryptedFileBytes = encrypter.decryptBytes(encrypt.Encrypted(base64Decode(fileData)), iv: _iv);

    Directory? downloadsDir = Directory("/storage/emulated/0/Download");
    if (!downloadsDir.existsSync()) {
      downloadsDir = await getExternalStorageDirectory();
    }
    File receivedFile = File('${downloadsDir!.path}/$fileName');
    await receivedFile.writeAsBytes(decryptedFileBytes);
    print("File successfully saved at: ${receivedFile.path}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF054640), // Updated background color
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.height * 0.25,
              child: ElevatedButton(
                onPressed: _sendFile,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: Text("SEND FILE", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
            SizedBox(height: 20),
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.height * 0.25,
              child: ElevatedButton(
                onPressed: _initializePeerConnection,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text("RECEIVE FILE", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
