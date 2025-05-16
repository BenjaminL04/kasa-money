import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/api.dart' hide Padding;
import 'package:pointycastle/digests/sha256.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class DetailsPage extends StatefulWidget {
  @override
  _DetailsPageState createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  String lnurl = '';
  String username27 = '';
  String otherUsername = '';
  final baseUrl = dotenv.env['API_BASE_URL'];


  SecureRandom getSecureRandom() {
    final secureRandom = SecureRandom('Fortuna')
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => Random.secure().nextInt(256)))));
    return secureRandom;
  }

  Uint8List bigIntToBytes(BigInt number, int byteLength) {
    final byteList = number.toRadixString(16).padLeft(byteLength * 2, '0');
    return Uint8List.fromList(List.generate(byteLength, (i) {
      return int.parse(byteList.substring(i * 2, i * 2 + 2), radix: 16);
    }));
  }


  @override
  void initState() {
    super.initState();
    _sendPostRequest();
  }

  Future<void> _sendPostRequest() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
     // String authToken = prefs.getString('auth_token') ?? '';


      // Retrieve private key and auth token from SharedPreferences
      String? privateKeyBase64 = prefs.getString('private_key');
      String? token = prefs.getString('auth_token');

      if (privateKeyBase64 == null || token == null) {
        return;
      }

      // Generate a random nonce (16 bytes)
      final nonce = List<int>.generate(16, (i) => Random.secure().nextInt(256));
      String nonceBase64 = base64Encode(nonce);

      // Append nonce to the message
      String messageWithNonce = "$token:$nonceBase64";

      // Hash the message using SHA-256
      final messageHash = SHA256Digest().process(utf8.encode(messageWithNonce));

      // Decode private key from Base64
      Uint8List privateKeyBytes = base64Decode(privateKeyBase64);

      // Convert private key bytes to BigInt
      BigInt privateKeyInt = BigInt.parse(privateKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(), radix: 16);

      // Create ECDSA P-256 private key
      final privateKey = ECPrivateKey(privateKeyInt, ECDomainParameters('secp256r1'));

      // Initialize secure random generator
      final secureRandom = getSecureRandom();

      // Initialize ECDSA signer with SecureRandom
      final signer = Signer('SHA-256/ECDSA')
        ..init(true, ParametersWithRandom(PrivateKeyParameter<ECPrivateKey>(privateKey), secureRandom));

      // Sign the hashed message
      ECSignature signature = signer.generateSignature(Uint8List.fromList(messageHash)) as ECSignature;

      // Convert signature to Base64
      String signatureBase64 = base64Encode(
        bigIntToBytes(signature.r, 32) + bigIntToBytes(signature.s, 32)
      );

      final fullUrl = '$baseUrl/get_lnurls';

      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'signature': signatureBase64,
          'nonce': nonceBase64,
        }),
      );

      if (response.statusCode == 200) {

        final List<dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          // Search for username starting with '27'
          for (var item in data) {
            String currentUsername = item['username'];
            if (currentUsername.startsWith('27') || currentUsername.startsWith('264')) {
              setState(() {
                username27 = currentUsername;
              });
            } else {
              setState(() {
                otherUsername = currentUsername;
              });
            }
          }

          setState(() {
            lnurl = data[0]['lnurl'];
          });
        }
      } else {
      }
    } catch (e) {
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: lnurl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied to clipboard'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white), // Make back button white
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        automaticallyImplyLeading: false,
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Tap on the QR code to copy',
              style: TextStyle(color: Color(0xFFE98B38), 
              fontSize: 18.0),
            ),
            SizedBox(height: 16.0),
            GestureDetector(
              onTap: _copyToClipboard,
              child: lnurl.isNotEmpty
                  ? QrImageView(
                      data: lnurl,
                      version: QrVersions.auto,
                      size: 200.0,
                      backgroundColor: Colors.white,
                    )
                  : CircularProgressIndicator(),
            ),
            SizedBox(height: 16.0),
            Text(
              'Number linked to account: +$username27',
              style: TextStyle(color: Color(0xFFE98B38), fontSize: 16.0),
            ),
            Text(
              'Email: $otherUsername@bitcoinkhaya.com',
              style: TextStyle(color: Color(0xFFE98B38), fontSize: 16.0),
            ),
          ],
        ),
      ),
    );
  }
}
