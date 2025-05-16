import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:clipboard/clipboard.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/api.dart' hide Padding;
import 'package:pointycastle/digests/sha256.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';




class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HistoryPage(),
    );
  }
}

class HistoryPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'History Page',
          style: TextStyle(color: Color(0xFFE98B38)), // Set text color to 0xFFE98B38         
          ),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white), // Make back button white
      ),
      body: Container(
        color: Colors.black, // Set the background color of the entire page
        child: FutureBuilder<String?>(
          future: getAuthToken(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (snapshot.hasData) {
              return PaymentHistory(authToken: snapshot.data!);
            } else {
              return Center(child: Text('No data available'));
            }
          },
        ),
      ),
    );
  }

  Future<String?> getAuthToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }
}

class PaymentHistory extends StatefulWidget {
  final String authToken;

  const PaymentHistory({required this.authToken});

  @override
  _PaymentHistoryState createState() => _PaymentHistoryState();
}

class _PaymentHistoryState extends State<PaymentHistory> {
  List<Map<String, dynamic>> paymentHistory = [];
  final baseUrl = dotenv.env['API_BASE_URL'];

  @override
  void initState() {
    super.initState();
    fetchPaymentHistory();
  }

  String formatDateForCoingecko(int unixTime) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(unixTime * 1000);
    final formattedDate = DateFormat('dd-MM-yyyy').format(dateTime);
    return formattedDate;
  }

  String formatUnixTime(int unixTime) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(unixTime * 1000);
    final formattedTime = DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
    return formattedTime;
  }

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



  Future<void> fetchPaymentHistory() async {

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
    final fullUrl = '$baseUrl/history';
    final url = Uri.parse(fullUrl);

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'signature': signatureBase64,
          'nonce': nonceBase64,
          }),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        for (final item in data) {
          final date = formatDateForCoingecko(item['time']);
          final zarValue = await fetchZarValue(date);

          // Divide "amount" by 1000
          final amountInSats = item['amount'] / 1000;

          // Calculate amount in Rands
          final amountInRands = (amountInSats / 100000000) * zarValue;

          paymentHistory.add({
            'amount': amountInSats,
            'memo': item['memo'],
            'time': formatUnixTime(item['time']),
            'zarValue': amountInRands.toStringAsFixed(2),
            'bolt11': item['bolt11'],
          });
        }

        setState(() {});
      } else {
        print('Failed to load payment history');
      }
    } catch (error) {
      print('Error: $error');
    }
  }

  Future<double> fetchZarValue(String date) async {
    final coingeckoUrl =
        'https://api.coingecko.com/api/v3/coins/bitcoin/history?date=$date&localization=false';

    try {
      final coingeckoResponse = await http.get(Uri.parse(coingeckoUrl));

      if (coingeckoResponse.statusCode == 200) {
        final Map<String, dynamic> coingeckoData = jsonDecode(coingeckoResponse.body);

        // Extract ZAR value from market price
        final zarValue = coingeckoData['market_data']['current_price']['zar'];

        return zarValue;
      } else {
        print('Failed to fetch Coingecko data');
        return 0;
      }
    } catch (error) {
      print('Error: $error');
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ListView.builder(
        itemCount: paymentHistory.length,
        itemBuilder: (context, index) {
          final payment = paymentHistory[index];

          return GestureDetector(
            onTap: () {
              // Copy "bolt11" to clipboard
              FlutterClipboard.copy(payment['bolt11']);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Reference number copied to clipboard')),
              );
            },
            child: Container(
              margin: EdgeInsets.all(10.0),
              padding: EdgeInsets.all(15.0),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white),
                borderRadius: BorderRadius.circular(10.0),
                color: Colors.black,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display "amount" in SATS
                  Text(
                    'Amount: ${payment['amount']} SATS',
                    style: TextStyle(color: Colors.white),
                  ),
                  // Display "amount" in ZAR
                  Text(
                    'Amount in ZAR: ${payment['zarValue']}',
                    style: TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Memo: ${payment['memo']}',
                    style: TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Time: ${payment['time']}',
                    style: TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Tap on the box to copy the reference number',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
