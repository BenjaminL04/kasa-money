import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/api.dart' hide Padding;
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RequestPage extends StatefulWidget {
  @override
  _RequestPageState createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> {
  String lnurl = '';
  String username27 = '';
  String otherUsername = '';
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? '';

  @override
  void initState() {
    super.initState();
    _fetchLnurlData();
  }

  SecureRandom getSecureRandom() {
    final secureRandom = SecureRandom('Fortuna')
      ..seed(KeyParameter(Uint8List.fromList(
          List.generate(32, (i) => Random.secure().nextInt(256)))));
    return secureRandom;
  }

  Uint8List bigIntToBytes(BigInt number, int byteLength) {
    final byteList =
        number.toRadixString(16).padLeft(byteLength * 2, '0');
    return Uint8List.fromList(List.generate(byteLength, (i) {
      return int.parse(byteList.substring(i * 2, i * 2 + 2), radix: 16);
    }));
  }

  Future<void> _fetchLnurlData() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? privateKeyBase64 = prefs.getString('private_key');
      String? token = prefs.getString('auth_token');

      if (privateKeyBase64 == null || token == null || baseUrl.isEmpty) {
        return;
      }

      // Generate nonce
      final nonce = List<int>.generate(16, (i) => Random.secure().nextInt(256));
      String nonceBase64 = base64Encode(nonce);
      String messageWithNonce = "$token:$nonceBase64";

      // Hash message
      final messageHash = SHA256Digest().process(utf8.encode(messageWithNonce));

      // Decode private key
      Uint8List privateKeyBytes = base64Decode(privateKeyBase64);
      BigInt privateKeyInt = BigInt.parse(
          privateKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(),
          radix: 16);

      final privateKey = ECPrivateKey(privateKeyInt, ECDomainParameters('secp256r1'));
      final secureRandom = getSecureRandom();

      final signer = Signer('SHA-256/ECDSA')
        ..init(true, ParametersWithRandom(PrivateKeyParameter<ECPrivateKey>(privateKey), secureRandom));

      ECSignature signature = signer.generateSignature(Uint8List.fromList(messageHash)) as ECSignature;

      String signatureBase64 = base64Encode(
        bigIntToBytes(signature.r, 32) + bigIntToBytes(signature.s, 32),
      );

      final response = await http.post(
        Uri.parse('$baseUrl/get_lnurls'),
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
          String? foundPhoneUsername;
          String? foundEmailUsername;

          for (var item in data) {
            String username = item['username'];
            if (username.startsWith('27') || username.startsWith('264')) {
              foundPhoneUsername = username;
            } else {
              foundEmailUsername = username;
            }
          }

          setState(() {
            username27 = foundPhoneUsername ?? 'Not found';
            otherUsername = foundEmailUsername ?? 'Not found';
            lnurl = data[0]['lnurl'] ?? '';
          });
        }
      }
    } catch (e) {
      print('Error fetching LNURL: $e');
    }
  }

  void _copyToClipboard() {
    if (lnurl.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: otherUsername));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Request', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Username (Phone number) in large text
              Text(
                '@$otherUsername',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your Username',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFFE98B38),
                ),
              ),
              const SizedBox(height: 32),

              // QR Code (click to copy)
              GestureDetector(
                onTap: _copyToClipboard,
                child: lnurl.isNotEmpty
                    ? QrImageView(
                        data: otherUsername,
                        version: QrVersions.auto,
                        size: 240.0,
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.all(12),
                      )
                    : const CircularProgressIndicator(color: Colors.white),
              ),
              const SizedBox(height: 16),
              const Text(
                'Tap QR code to copy your Username',
                style: TextStyle(
                  color: Color(0xFFE98B38),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),

              // Phone number in small print
              Text(
                'Linked phone: +$username27',
                style: const TextStyle(
                  color: Color(0xFFAAAAAA),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}