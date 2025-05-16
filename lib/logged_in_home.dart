import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/digests/sha256.dart';
import 'balances.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


const String authTokenKey = 'auth_token';
const String private = 'private_key';

class LoggedInHomePage extends StatefulWidget {
  @override
  _LoggedInHomePageState createState() => _LoggedInHomePageState();
}

class _LoggedInHomePageState extends State<LoggedInHomePage> {
  String satsBalance = '';
  String zarBalance = '';
  String zarpBalance = '';
  String totalBalance = '';
  String usernameError = '';
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

  TextEditingController usernameController = TextEditingController();
  GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _fetchBalance();
    _sendAdditionalRequest();
    FlutterCryptography.enable();  // Ensure native cryptography is initialized
  }

Future<void> _fetchBalance() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();  
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

    final fullUrl = '$baseUrl/check_balance';


  // Fetch balance
  final response = await http.post(
    Uri.parse(fullUrl),
    body: {
      'token': token,
      'nonce': nonceBase64,
      'signature': signatureBase64,
    },
  );

  if (response.statusCode == 200) {
    final Map<String, dynamic> data = json.decode(response.body);
      double zarValue = double.parse(data['zar_balance'].toString());
      double zarpValue = double.parse(data['zarp_balance'].toString());
      double totalValue = zarValue + zarpValue;

      setState(() {
        satsBalance = data['sats_balance'].toString();
        zarBalance = zarValue.toStringAsFixed(2); // Keep 2 decimal places
        zarpBalance = zarpValue.toStringAsFixed(2); // Keep 2 decimal places
        totalBalance = totalValue.toStringAsFixed(2); // Keep 2 decimal places
      });

    _checkLnurlCheck2Response(token);
  } else {
    // Handle error
  }
}

  Future<void> _sendAdditionalRequest() async {

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

    final fullUrl1 = '$baseUrl/lnurl_check1';


    final additionalResponse = await http.post(
      Uri.parse(fullUrl1),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'token': token,
        'signature': signatureBase64,
        'nonce': nonceBase64,
        }),
    );
    final Map<String, dynamic> data = json.decode(additionalResponse.body);
  }

  Future<void> _checkLnurlCheck2Response(String token) async {
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

    final fullUrl3 = '$baseUrl/lnurl_check2';

    final lnurlCheck2Response = await http.post(
      Uri.parse(fullUrl3),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'token': token,
        'signature': signatureBase64,
        'nonce': nonceBase64,
        }),
    );

    if (lnurlCheck2Response.statusCode == 200) {
      final Map<String, dynamic> lnurlCheck2Data =
          json.decode(lnurlCheck2Response.body);

      if (lnurlCheck2Data['message'] == 'none') {
        _showInputDialog(token);
      }
    } else {
      _showErrorSnackBar("Error checking Lnurl Check 2");
    }
  }

void _showInputDialog(String token) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Enter Username'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    hintText: 'Username',
                    errorText: usernameError,
                  ),
                  onFieldSubmitted: (value) async {
                    if (_isValidUsername(value)) {
                      await _createLnurl(token, value, setState);
                    } else {
                      setState(() {
                        usernameError =
                            'Invalid username. Please use lowercase letters without spaces.';
                      });
                    }
                  },
                ),
                SizedBox(height: 10),
                Text(
                  usernameError,
                  style: TextStyle(color: Colors.red),
                ),
                SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                    String username = usernameController.text;
                    if (_isValidUsername(username)) {
                      await _createLnurl(token, username, setState);
                    } else {
                      setState(() {
                        usernameError =
                            'Invalid username. Please use lowercase letters without spaces.';
                      });
                    }
                  },
                  child: Text('Submit'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  FocusScope.of(context).unfocus(); // Clear focus before dismissing
                  Navigator.of(context).pop(); // Dismiss dialog
                },
                child: Text('Cancel'),
              ),
            ],
          );
        },
      );
    },
  ).then((_) {
    // Ensure keyboard is dismissed after dialog closes
    FocusScope.of(context).unfocus();
  });
}

  bool _isValidUsername(String username) {
    if (username.isEmpty ||
        username.contains(' ') ||
        username != username.toLowerCase()) {
      setState(() {
        usernameError =
            'Invalid username. Please use lowercase letters without spaces.';
      });
      return false;
    } else {
      setState(() {
        usernameError = '';
      });
      return true;
    }
  }

  Future<void> _createLnurl(String token, String username, Function setState) async {
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

    final fullUrl2 = '$baseUrl/create_lnurl';


    final createLnurlResponse = await http.post(
      Uri.parse(fullUrl2),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'token': token,
        'username': username,
        'signature': signatureBase64,
        'nonce': nonceBase64,
      }),
    );

      final Map<String, dynamic> createLnurlData =
          json.decode(createLnurlResponse.body);
    
      if (createLnurlData['message'] == 'success') {
        Navigator.of(context).pop();
      } else {
        // Username is taken, update the UI to show the error
        setState(() {
          usernameError = "Username taken, please try again";
        });
      }

  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _goToCardSettingsPage() {
    Navigator.pushNamed(context, '/card_page');
  }

  Future<void> _handleRefresh() async {
    _fetchBalance();
    _sendAdditionalRequest();
    await Future.delayed(Duration(seconds: 1)); // Simulate a delay
  }

  void _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.remove(authTokenKey);
    prefs.remove(private);

    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  Future<void> _logoutPostRequest() async {
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

    final apiUrl = '$baseUrl/logout';

    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': token,
        'signature': signatureBase64,
        'nonce': nonceBase64,
      }),
    );

    if (response.statusCode == 200) {
      _logout();
    } else {
      print("Logout Failed");
    }
  }

@override
Widget build(BuildContext context) {
  return WillPopScope(
    onWillPop: () async => false, // Prevents back navigation
    child: Scaffold( // Added colon after 'child'
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: <Widget>[
          Container(
            color: Colors.black,
            height: 100, // Adjust this height as needed
          ),
          Expanded(
            child: RefreshIndicator(
              key: _refreshIndicatorKey,
              onRefresh: _handleRefresh,
              child: Container(
                height: double.infinity,
                color: Colors.black,
                child: SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Total Balance',
                              style: TextStyle(
                                fontSize: 36,
                                color: Color(0xFFE98B38),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 20),
                            Text(
                              '$totalBalance ZAR',
                              style: TextStyle(
                                fontSize: 36,
                                color: Color(0xFFE98B38),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 40),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pushNamed(context, '/send_page');
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white,
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Text('Send'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pushNamed(context, '/receive');
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white,
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Text('Receive'),
                                ),
                              ],
                            ),
                            SizedBox(height: 40),
                            ElevatedButton(
                            onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => BalancesPage(
                                      satsBalance: satsBalance,
                                      zarBalance: zarBalance,
                                      zarpBalance: zarpBalance,
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white,
                                  width: 1.0,
                                ),
                              ),
                              child: Text('Balances'),
                            ),
                            SizedBox(height: 40),
                            // ElevatedButton(
                            //   onPressed: _goToCardSettingsPage,
                            //   style: ElevatedButton.styleFrom(
                            //     primary: Colors.white,
                            //     onPrimary: Color(0xFFFF9B29),
                            //   ),
                            //   child: Text('Card Settings'),
                            // ),
                            SizedBox(height: 40),
                            ElevatedButton(
                              onPressed: _logoutPostRequest,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white,
                                  width: 1.0,
                                ),
                              ),
                              child: Text('Logout'),
                            ),
                            SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}