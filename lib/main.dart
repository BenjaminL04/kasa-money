import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'login_page.dart';
import 'registration_page.dart';
import 'logged_in_home.dart';
import 'send_page.dart';
import 'receive_page.dart';
import 'history_page.dart';
import 'send_number.dart';
import 'send_any.dart';
import 'dart:convert';
import 'card.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/api.dart' hide Padding;
import 'package:pointycastle/digests/sha256.dart';
import 'receive.dart';
import 'receive_zarp.dart';
import 'send.dart';
import 'send_zarp.dart';
import 'receive_zarp_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';



void main() async {
    await dotenv.load(fileName: ".env");
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
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // String authToken = prefs.getString('auth_token') ?? '';


    // Retrieve private key and auth token from SharedPreferences
    String? privateKeyBase64 = prefs.getString('private_key');
    String? token = prefs.getString('auth_token');

    if (token == null || token.isEmpty || token == "0") {
      runApp(MyApp(loggedIn: false));
    }

    if (privateKeyBase64 == null) {
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
  
    final fullUrl = '$baseUrl/logincheck';

    // Token is present in shared preferences, make a POST request
    Uri apiUrl = Uri.parse(fullUrl);
    http.Response response = await http.post(
      apiUrl,
      headers: {'Content-Type': 'application/json'}, // Specify the content type
      body: jsonEncode({
        'token': token,
        'signature': signatureBase64,
        'nonce': nonceBase64,
      }),
    );    
    if (response.statusCode == 200) {
      Map<String, dynamic> jsonResponse = json.decode(response.body);

      // Check the response for the desired result
    if (jsonResponse['result'] == 'exists') {
        runApp(MyApp(loggedIn: true));
        return;
      } else {
        print(response.body);
        runApp(MyApp(loggedIn: false));
      }
    }
  

  runApp(MyApp(loggedIn: false));
}

class MyApp extends StatelessWidget {
  final bool loggedIn;

  const MyApp({Key? key, required this.loggedIn}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: loggedIn ? LoggedInHomePage() : HomePage(),
      routes: {
        '/home': (context) => HomePage(),
        '/login': (context) => LoginPage(),
        '/registration': (context) => RegistrationPage(),
        '/logged_in_home': (context) => LoggedInHomePage(),
        '/send_btc_page': (context) => SendBTCPage(),
        '/receive_btc_page': (context) => ReceiveBTCPage(),
        '/history_page': (context) => HistoryPage(),
        '/send_number': (context) => SendNumber(),
        '/send_any': (context) => SendAnyPage(),
        '/card_page': (context) => CardPage(),
        '/receive': (context) => ReceivePage(),
        '/receive_zarp': (context) => ReceiveZARPPage(),
        '/send_page': (context) => SendPage(),
        '/send_zarp_page': (context) => SendZarpPage(),
      },
    );
  }
}

// The rest of your existing code remains unchanged.

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: null,
        backgroundColor: Colors.black,
        centerTitle: true,
      ),
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.all(20.0),
                child: Image.asset(
                  'assets/logo.png',
                  height: 100.0,
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: 140.0),
                  ElevatedButton(
                    onPressed: () async {
                      // Navigate to the login page and wait for a result
                      final result = await Navigator.pushNamed(context, '/login');

                      // Check the result, if it's 'success', navigate to the logged_in_home page
                      if (result == 'success') {
                        Navigator.pushReplacementNamed(context, '/logged_in_home');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black, // Replaces primary
                      foregroundColor: Colors.white, // Replaces onPrimary
                      side: BorderSide(
                        color: Colors.white,
                        width: 2.0,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                    ),
                    child: Text(
                      'Login',
                      style: TextStyle(fontSize: 24.0),
                    ),
                  ),
                  SizedBox(height: 20.0),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/registration');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black, // Replaces primary
                      foregroundColor: Colors.white, // Replaces onPrimary
                      side: BorderSide(
                        color: Colors.white,
                        width: 2.0,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                    ),
                    child: Text(
                      'Register',
                      style: TextStyle(fontSize: 24.0),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
