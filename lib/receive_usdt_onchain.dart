import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ReceiveUsdtOnchainPage extends StatefulWidget {
  @override
  _ReceiveUsdtOnchainPageState createState() => _ReceiveUsdtOnchainPageState();
}

class _ReceiveUsdtOnchainPageState extends State<ReceiveUsdtOnchainPage> {
  String pubkey = '';
  final baseUrl = dotenv.env['API_BASE_URL'];

  @override
  void initState() {
    super.initState();
    _sendPostRequest();
  }

  Future<void> _sendPostRequest() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('auth_token');

      if (token == null) {
        return;
      }

      final apiUrl = '$baseUrl/fetch_solana_pubkey';


      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          pubkey = data['pubkey'] ?? '';
        });
      } else {
        // Handle error
      }
    } catch (e) {
      // Handle exception
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: pubkey));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pubkey copied to clipboard'),
      ),
    );
  }

  String _getTruncatedPubkey() {
    if (pubkey.isEmpty) return 'Loading...';
    const int charsToShow = 4;
    return '${pubkey.substring(0, charsToShow)}...${pubkey.substring(pubkey.length - charsToShow)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
        title: Text('Receive USDT On-Chain', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Tap on the QR code to copy',
              style: TextStyle(color: Color(0xFFE98B38), fontSize: 18.0),
            ),
            SizedBox(height: 16.0),
            GestureDetector(
              onTap: _copyToClipboard,
              child: pubkey.isNotEmpty
                  ? QrImageView(
                      data: pubkey,
                      version: QrVersions.auto,
                      size: 200.0,
                      backgroundColor: Colors.white,
                    )
                  : CircularProgressIndicator(),
            ),
            SizedBox(height: 16.0),
            Text(
              'Solana Pubkey:',
              style: TextStyle(color: Color(0xFFE98B38), fontSize: 16.0),
            ),
            Text(
              _getTruncatedPubkey(),
              style: TextStyle(color: Color(0xFFE98B38), fontSize: 16.0),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}