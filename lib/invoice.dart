import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:clipboard/clipboard.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/api.dart' hide Padding;
import 'package:pointycastle/digests/sha256.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class InvoicePage extends StatefulWidget {
  @override
  _InvoicePageState createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  TextEditingController amountController = TextEditingController();
  String authToken = '';
  String paymentRequest = '';
  double btcToZarExchangeRate = 0;
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
    // Retrieve 'auth_token' from shared preferences
    getAuthToken();
  }

  Future<void> getAuthToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String token = prefs.getString('auth_token') ?? '';
    setState(() {
      authToken = token;
    });
  }

  Future<void> fetchBtcToZarExchangeRate() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.binance.com/api/v3/ticker/price?symbol=BTCZAR'),
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> jsonResponse = json.decode(response.body);
        if (jsonResponse.containsKey('price')) {
          setState(() {
            btcToZarExchangeRate = double.parse(jsonResponse['price']);
          });

          // Perform calculations and send the API request
          calculateAndSendApiRequest();
        } else {
        }
      } else {
      }
    } catch (e) {
    }
  }

  Future<void> calculateAndSendApiRequest() async {
    // Ensure the user has entered an amount
    if (amountController.text.isEmpty) {
      // Show a snackbar or some UI indication that the amount is required
      return;
    }

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


    // Calculate the final amount using the exchange rate
    double inputAmount = double.parse(amountController.text);
    double finalAmount = (inputAmount / btcToZarExchangeRate) * 100000000;
    int roundedAmount = finalAmount.round();

    // API endpoint URL
    final fullUrl = '$baseUrl/create_invoice';


    // API request payload
    Map<String, dynamic> requestBody = {
      'token': token,
      'amount': roundedAmount,
      'signature': signatureBase64,
      'nonce': nonceBase64,
    };

    // Print the API request payload to the console for debugging

    // Send the API request
    sendApiRequest(fullUrl, requestBody);
  }

  Future<void> sendApiRequest(String apiUrl, Map<String, dynamic> requestBody) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      // Parse the payment request from the API response
      if (response.statusCode == 200) {
        Map<String, dynamic> jsonResponse = json.decode(response.body);
        if (jsonResponse.containsKey('payment_request')) {
          setState(() {
            paymentRequest = jsonResponse['payment_request'];
          });
        } else {
        }
      } else {
      }
    } catch (e) {
      // Handle the error (show a snackbar, display an error message, etc.)
    }
  }

  void copyToClipboard() {
    // Copy paymentRequest to the clipboard
    FlutterClipboard.copy(paymentRequest)
        .then((value) => showSnackBar('Copied to Clipboard'))
        .catchError((error) => print('Error copying to clipboard: $error'));
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white), // Make back button white
      ),
      body: Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Show input and button if paymentRequest is empty
                if (paymentRequest.isEmpty)
                  Column(
                    children: [
                      TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'Enter Amount'),
                        style: TextStyle(color: Colors.white), // Set typed text color to white
                      ),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          // Call the function to fetch the exchange rate
                          fetchBtcToZarExchangeRate();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black, // Set background color to white
                          foregroundColor: Colors.white, // Set text color
                          side: BorderSide(
                            color: Colors.white,
                            width: 1.0,
                          ),
                        ),
                        child: Text('Create Invoice'),
                      ),
                      SizedBox(height: 16),
                    ],
                  ),
                // Display header, QR code, and tap message if paymentRequest is available
                if (paymentRequest.isNotEmpty)
                  Column(
                    children: [
                      Text(
                        'Tap on the image to copy',
                        style: TextStyle(color: Color(0xFFE98B38)),
                      ),
                      SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          // Copy the paymentRequest to the clipboard and show snackbar
                          copyToClipboard();
                        },
                        child: QrImageView(
                          data: paymentRequest,
                          version: QrVersions.auto,
                          size: 200.0,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
