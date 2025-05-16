import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'forgot_password_page.dart';
import 'logged_in_home.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'keypair.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class LoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: Colors.white), // Make back button white
        title: Text(
          'Login',
          style: TextStyle(color: Color(0xFFE98B38)),
        ),        backgroundColor: Colors.black,
        centerTitle: true,
      ),
      body: Container(
        color: Colors.black,
        padding: EdgeInsets.all(16.0),
        child: LoginForm(),
      ),
    );
  }
}

class LoginForm extends StatefulWidget {
  @override
  _LoginFormState createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  TextEditingController otpController = TextEditingController();
  String loginMessage = '';
  int otpAttempts = 0;
  int maxOtpAttempts = 3;
  bool isButtonDisabled = false;
  String hashedSerial = "";
  String signature = ""; // Declare globally
  final baseUrl = dotenv.env['API_BASE_URL'];

  
    @override
  void initState() {
    super.initState();
    printDeviceSerial(); // Runs when the Login Page is opened
    final keys = ECDSAKeyGenerator.generateECDSAP256KeyPair();
}



Future<void> printDeviceSerial() async {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  String deviceSerial;

  if (Platform.isAndroid) {
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    deviceSerial = androidInfo.id; // Unique Android ID
  } else if (Platform.isIOS) {
    IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
    deviceSerial = iosInfo.identifierForVendor ?? "Unknown iOS Device ID";
  } else if (Platform.isWindows) {
    WindowsDeviceInfo windowsInfo = await deviceInfo.windowsInfo;
    deviceSerial = windowsInfo.computerName;
  } else if (Platform.isMacOS) {
    MacOsDeviceInfo macInfo = await deviceInfo.macOsInfo;
    deviceSerial = macInfo.computerName;
  } else if (Platform.isLinux) {
    LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
    deviceSerial = linuxInfo.machineId ?? "Unknown Linux ID";
  } else {
    deviceSerial = "Unknown Device";
  }

  // Convert to SHA-256 hash
  setState(() {
    hashedSerial = sha256.convert(utf8.encode(deviceSerial)).toString();
  });

}

Future<void> loginUser(BuildContext context) async {
  if (isButtonDisabled) {
    return;
  }

  setState(() {
    isButtonDisabled = true;
  });

  final apiUrl = '$baseUrl/password_check';

  String email = emailController.text;
  String password = passwordController.text;

  Map<String, String> requestData = {
    'email': email,
    'password': password,
  };

  String requestBody = jsonEncode(requestData);

  try {
    http.Response response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
      },
      body: requestBody,
    );



    if (response.statusCode == 200) {
      dynamic responseBody = jsonDecode(response.body);
      
      if (responseBody.containsKey('signature')) {
        setState(() {
          signature = responseBody['signature']; // Update the global signature variable
        });
      }

      handleApiResponse(context, responseBody);
    } else {
    }
  } catch (error) {
  }
 finally {
    Future.delayed(Duration(seconds: 5), () {
      setState(() {
        isButtonDisabled = false;
      });
    });
  }
}

  int generateRandomOTP() {
    Random random = Random();
    return random.nextInt(900000) + 100000;
  }

  Future<void> handleApiResponse(BuildContext context, dynamic response) async {
    if (response is Map<String, dynamic> && response.containsKey('message')) {
      String message = response['message'].toString();

      if (message == 'Password correct') {
        int otp = generateRandomOTP();

        await sendOtpRequest(emailController.text, otp.toString());

        showDialog(
          context: context,
          builder: (BuildContext context) {
            return WillPopScope(
              onWillPop: () async => false,
              child: AlertDialog(
                title: Text('Enter OTP'),
                content: Column(
                  children: [
                    Text('An OTP has been sent to your email.'),
                    YourWidget(
                      otpController: otpController,
                      onSubmit: () {
                        if (otpController.text == otp.toString()) {
                          sendLoginRequest(emailController.text, hashedSerial);
                        } else {
                          setState(() {
                            otpAttempts++;
                            if (otpAttempts >= maxOtpAttempts) {
                              Navigator.pop(context);
                            } else {
                              loginMessage = 'Wrong code inputted';
                            }
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      } else if (message == 'User doesn\'t exist') {
        setLoginMessage('User doesn\'t exist');
      } else if (message == 'Password incorrect') {
        setLoginMessage('Password incorrect');
      } else {
        setLoginMessage('Unexpected response from the server');
      }
    } else {
      setLoginMessage('Invalid response format');
    }
  }

  Future<void> sendOtpRequest(String email, String otp) async {
    final apiUrl = '$baseUrl/otp';

    Map<String, String> requestData = {
      'recipient_email': email,
      'otp': otp,
    };

    String requestBody = jsonEncode(requestData);
    print (requestBody);

    try {
      http.Response response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: requestBody,
      );
      print (response);

      if (response.statusCode == 200) {
        dynamic responseBody = jsonDecode(response.body);
                              print (responseBody);

      } else {
                dynamic responseBody = jsonDecode(response.body);
                                      print (responseBody);


      }
    } catch (error) {
    }
  }


Future<void> sendLoginRequest(String email, String hashedSerial) async {
  String publicKeyXBase64;
  String publicKeyYBase64;
  String privateKeyBase64;

  // Platform-based logic
  if (Platform.isAndroid) {
    // ✅ Use Android logic from test.dart
    final keyPair = ECDSAKeyGenerator.generateECDSAP256KeyPair();

    publicKeyXBase64 = keyPair['publicKeyX']!;
    publicKeyYBase64 = keyPair['publicKeyY']!;
    privateKeyBase64 = keyPair['privateKey']!;
  } else if (Platform.isIOS) {
    // ✅ iOS logic using flutter_ecdsa
    final algorithm = FlutterEcdsa.p256(Sha256());
    final EcKeyPair keyPair = await algorithm.newKeyPair();

    final EcKeyPairData privateKeyData = await keyPair.extract();
    privateKeyBase64 = base64Encode(privateKeyData.d); // Extract private key

    final EcPublicKey publicKey = privateKeyData.publicKey;
    publicKeyXBase64 = base64Encode(publicKey.x); // X coordinate
    publicKeyYBase64 = base64Encode(publicKey.y); // Y coordinate
  } else {
    throw UnsupportedError("Unsupported platform.");
  }

  // Save private key to SharedPreferences
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setString('private_key', privateKeyBase64);

  // API details
  final apiUrl = '$baseUrl/login';
  int currentUnixTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  int expiryTimestamp = currentUnixTimestamp + (180 * 24 * 60 * 60); // 180 days

  // Prepare request data
  Map<String, dynamic> requestData = {
    'email': email,
    'serial': hashedSerial,
    'expiry': expiryTimestamp,
    'x': publicKeyXBase64,
    'y': publicKeyYBase64,
    'signature': signature,
  };

  // Convert to JSON
  String requestBody = jsonEncode(requestData);

  // Send HTTP POST request
  try {
    http.Response response = await http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: requestBody,
    );
    print(response);

    if (response.statusCode == 200) {
      dynamic responseBody = jsonDecode(response.body);
      handleLoginApiResponse(responseBody); // Handle API response
    } else {
    }
  } catch (error) {
  }
}

  Future<void> handleLoginApiResponse(dynamic response) async {

    if (response is Map<String, dynamic> && response.containsKey('token')) {
      String authToken = response['token'].toString();
      await saveTokenInSharedPreferences(authToken);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => LoggedInHomePage(),
          fullscreenDialog: true, // This prevents the back swipe gesture on iOS
        ),
      );
    } else {
    }
  }

  Future<void> saveTokenInSharedPreferences(String token) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('auth_token', token);
  }

  void setLoginMessage(String message) {
    setState(() {
      loginMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: Colors.white), // Set inputted text color to white
          decoration: InputDecoration(
            labelText: 'Email',
            labelStyle: TextStyle(color: Colors.white), // Set label text color to white
            filled: true, // Make the input field filled
            fillColor: Colors.black, // Set background color to black
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Set border color to white
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Set enabled border color to white
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Set focused border color to white
            ),
         ),
        ),
        SizedBox(height: 16.0),
        TextField(
          controller: passwordController,
          obscureText: true, 
          style: TextStyle(color: Colors.white), // Set inputted text color to white
          decoration: InputDecoration(
            labelText: 'Password',
            labelStyle: TextStyle(color: Colors.white), // Set label text color to white
            filled: true, // Make the input field filled
            fillColor: Colors.black, // Set background color to black
            border: OutlineInputBorder(
             borderSide: BorderSide(color: Colors.white), // Set border color to white
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Set enabled border color to white
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Set focused border color to white
            ),
          ),
        ),
        SizedBox(height: 16.0),
        ElevatedButton(
          onPressed: isButtonDisabled ? null : () => loginUser(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            side: BorderSide(
              color: Colors.white,
              width: 1.0,
            ),
          ),          
         child: Text('Login'),
        ),
        SizedBox(height: 8.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ForgotPasswordPage(),
                  ),
                );
              },
              child: Text(
                'Forgot Password?',
                style: TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.0),
        if (loginMessage.isNotEmpty)
          Text(
            loginMessage,
            style: TextStyle(
              color: Colors.red,
              fontSize: 16.0,
            ),
          ),
      ],
    );
  }
}

class YourWidget extends StatelessWidget {
  final TextEditingController otpController;
  final Function onSubmit;

  YourWidget({
    required this.otpController,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: otpController,
          decoration: InputDecoration(labelText: 'OTP'),
          keyboardType: TextInputType.number,
        ),
        SizedBox(height: 16.0),
        ElevatedButton(
          onPressed: () {
            onSubmit();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFFFF9B29),
            foregroundColor: Colors.white,
          ),
          child: Text('Submit'),
        ),
      ],
    );
  }
}
