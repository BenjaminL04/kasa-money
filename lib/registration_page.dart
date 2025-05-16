import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'logged_in_home.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'keypair.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LogInPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Logged In Home'),
        backgroundColor: Color(0xFFFF9B29),
        iconTheme: IconThemeData(color: Colors.white),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Container(
        color: Color(0xFFFF9B29),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Welcome to the Logged In Home Page!',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, 'logout');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Color(0xFFFF9B29),
                  ),
                  child: Text('Log Out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RegistrationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (Navigator.of(context).canPop()) {
          return true;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Image.asset('assets/logo.png', height: 30.0),
          backgroundColor: Colors.black,
          iconTheme: IconThemeData(color: Colors.white),
          automaticallyImplyLeading: true,
        ),
        body: RegistrationForm(),
      ),
    );
  }
}

class RegistrationForm extends StatefulWidget {
  @override
  _RegistrationFormState createState() => _RegistrationFormState();
}

class _RegistrationFormState extends State<RegistrationForm> {
  TextEditingController firstNameController = TextEditingController();
  TextEditingController lastNameController = TextEditingController();
  TextEditingController phoneNumberController = TextEditingController();
  TextEditingController emailAddressController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  TextEditingController otpController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  int otpAttempts = 0;
  int maxOtpAttempts = 3;
  bool otpVerified = false;
  late int otp;
  String hashedSerial = "";
  String signature = "";
  String selectedCountryCode = "+27";
  bool isCheckboxChecked = false;
  bool isLoading = false; // Track loading state

  final baseUrl = dotenv.env['API_BASE_URL'];

  @override
  void initState() {
    super.initState();
    printDeviceSerial();
    FlutterCryptography.enable();
  }

  Future<void> printDeviceSerial() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String deviceSerial;

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      deviceSerial = androidInfo.id;
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

    var bytes = utf8.encode(deviceSerial);
    var digest = sha256.convert(bytes);
    setState(() {
      hashedSerial = digest.toString();
    });
  }

  Future<void> registerUser(BuildContext context) async {
    await printDeviceSerial();
    final createUserUrl = '$baseUrl/create_user';
    final createCredsUrl = '$baseUrl/create_creds';

    try {
      final phoneNumber = "${selectedCountryCode.substring(1)}${phoneNumberController.text}";
      final createUserResponse = await http.post(
        Uri.parse(createUserUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'first_name': firstNameController.text,
          'last_name': lastNameController.text,
          'phone_number': phoneNumber,
          'email': emailAddressController.text,
          'password': passwordController.text,
        }),
      );

      if (createUserResponse.statusCode == 200) {
        if (createUserResponse.body.contains('User Created')) {
          await Future.delayed(Duration(seconds: 2));
          var responseData = jsonDecode(createUserResponse.body);
          setState(() {
            signature = responseData['signature'];
          });

          final createCredsResponse = await http.post(
            Uri.parse(createCredsUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone_number': phoneNumber}),
          );

          if (createCredsResponse.statusCode == 200) {
            dynamic createCredsResponseBody = jsonDecode(createCredsResponse.body);

            if (createCredsResponseBody['message'] == 'success') {
              String publicKeyXBase64;
              String publicKeyYBase64;
              String privateKeyBase64;

              if (Platform.isAndroid) {
                final keyPair = ECDSAKeyGenerator.generateECDSAP256KeyPair();
                publicKeyXBase64 = keyPair['publicKeyX']!;
                publicKeyYBase64 = keyPair['publicKeyY']!;
                privateKeyBase64 = keyPair['privateKey']!;
              } else if (Platform.isIOS) {
                final algorithm = FlutterEcdsa.p256(Sha256());
                final EcKeyPair keyPair = await algorithm.newKeyPair();

                final EcKeyPairData privateKeyData = await keyPair.extract();
                privateKeyBase64 = base64Encode(privateKeyData.d);

                final EcPublicKey publicKey = privateKeyData.publicKey;
                publicKeyXBase64 = base64Encode(publicKey.x);
                publicKeyYBase64 = base64Encode(publicKey.y);
              } else {
                throw UnsupportedError("Unsupported platform.");
              }

              final SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.setString('private_key', privateKeyBase64);

              String email = emailAddressController.text;
              int currentUnixTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              int expiryTimestamp = currentUnixTimestamp + (180 * 24 * 60 * 60);
              final fullUrl = '$baseUrl/login';

              Map<String, dynamic> requestBody = {
                'email': email,
                'serial': hashedSerial,
                'expiry': expiryTimestamp,
                'x': publicKeyXBase64,
                'y': publicKeyYBase64,
                'signature': signature,
              };

              var loginResponse = await http.post(
                Uri.parse(fullUrl),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(requestBody),
              );

              if (loginResponse.statusCode == 200) {
                dynamic loginResponseBody = jsonDecode(loginResponse.body);
                String authToken = loginResponseBody['token'];

                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setString('auth_token', authToken);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => LoggedInHomePage()),
                );
              } else {
                throw Exception('Login failed: ${loginResponse.statusCode}');
              }
            } else {
              throw Exception('Credentials creation failed');
            }
          } else {
            throw Exception('Error: ${createCredsResponse.statusCode}');
          }
        } else {
          throw Exception('Registration failed');
        }
      } else {
        throw Exception('Error: ${createUserResponse.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      setState(() {
        isLoading = false; // Stop loading on error
      });
    }
  }

  Future<void> sendOtpRequest(String email, String otp) async {
    final apiUrl = '$baseUrl/otp';

    Map<String, String> requestData = {
      'recipient_email': email,
      'otp': otp,
    };

    String requestBody = jsonEncode(requestData);

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: requestBody,
      );

      if (response.statusCode == 200) {
        dynamic responseBody = jsonDecode(response.body);
      } else {
        throw Exception('OTP request failed: ${response.statusCode}');
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending OTP: $error')),
      );
    }
  }

  void verifyOtp(String enteredOtp) {
    if (enteredOtp == otp.toString()) {
      setState(() {
        otpVerified = true;
        isLoading = true; // Start loading
      });

      Navigator.of(context).pop(); // Close OTP dialog

      if (otpVerified) {
        registerUser(context).then((_) {
          setState(() {
            isLoading = false; // Stop loading after registration
          });
        });
      }
    } else {
      setState(() {
        otpAttempts++;
      });

      if (otpAttempts >= maxOtpAttempts) {
        Navigator.of(context).pop();
        setState(() {
          otpAttempts = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Maximum OTP attempts reached')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid OTP. ${maxOtpAttempts - otpAttempts} attempts remaining')),
        );
      }
    }
  }

  int generateRandomOTP() {
    final Random random = Random();
    return random.nextInt(900000) + 100000;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.black,
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextFormField(
                      controller: firstNameController,
                      decoration: InputDecoration(
                        labelText: 'First Name',
                        labelStyle: TextStyle(color: Colors.white),
                        filled: true,
                        fillColor: Colors.black,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      style: TextStyle(color: Colors.white),
                      validator: (value) {
                        if (value?.isEmpty ?? true) {
                          return 'Please enter your first name';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16.0),
                    TextFormField(
                      controller: lastNameController,
                      decoration: InputDecoration(
                        labelText: 'Last Name',
                        labelStyle: TextStyle(color: Colors.white),
                        filled: true,
                        fillColor: Colors.black,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      style: TextStyle(color: Colors.white),
                      validator: (value) {
                        if (value?.isEmpty ?? true) {
                          return 'Please enter your last name';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16.0),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            value: selectedCountryCode,
                            isExpanded: true,
                            items: [
                              DropdownMenuItem(
                                value: "+27",
                                child: Text("South Africa (+27)", overflow: TextOverflow.ellipsis),
                              ),
                              DropdownMenuItem(
                                value: "+264",
                                child: Text("Namibia (+264)", overflow: TextOverflow.ellipsis),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedCountryCode = value!;
                              });
                            },
                            style: TextStyle(color: Color(0xFFFF9B29)),
                            decoration: InputDecoration(
                              labelText: 'Country',
                              labelStyle: TextStyle(color: Colors.white),
                              hintText: "Select Country",
                              hintStyle: TextStyle(color: Colors.white),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          flex: 5,
                          child: TextFormField(
                            controller: phoneNumberController,
                            decoration: InputDecoration(
                              labelText: 'Phone Number',
                              hintText: '123456789',
                              labelStyle: TextStyle(color: Colors.white),
                              hintStyle: TextStyle(color: Colors.white),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                            keyboardType: TextInputType.phone,
                            validator: (value) {
                              if (value?.isEmpty ?? true) {
                                return 'Please enter your phone number';
                              } else if (value!.startsWith('0')) {
                                return 'Phone number cannot start with 0';
                              } else if (value.length != 9) {
                                return 'Phone number must be 9 digits';
                              }
                              return null;
                            },
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.0),
                    TextFormField(
                      controller: emailAddressController,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Email Address',
                        labelStyle: TextStyle(color: Colors.white),
                        filled: true,
                        fillColor: Colors.black,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      validator: (value) {
                        if (value?.isEmpty ?? true || !(value?.contains('@') ?? false)) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16.0),
                    TextFormField(
                      controller: passwordController,
                      obscureText: true,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: TextStyle(color: Colors.white),
                        filled: true,
                        fillColor: Colors.black,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      validator: (value) {
                        if (value?.isEmpty ?? true || (value?.length ?? 0) < 6) {
                          return 'Password must be at least 6 characters long';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16.0),
                    Row(
                      children: [
                        Checkbox(
                          value: isCheckboxChecked,
                          onChanged: (value) {
                            setState(() {
                              isCheckboxChecked = value!;
                            });
                          },
                        ),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              text: 'By ticking this checkbox you are agreeing to the ',
                              style: TextStyle(color: Colors.white),
                              children: [
                                TextSpan(
                                  text: 'Terms and Conditions, Privacy Policy, and Anti-Money Laundering Policy (AML) ',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                TextSpan(
                                  text: 'for Kasa wallet. ',
                                  style: TextStyle(color: Colors.white),
                                ),
                                TextSpan(
                                  text: 'Click here to access these policies',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      launch('https://wallet.btckhaya.com/policy.pdf');
                                    },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.0),
                    ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() ?? false) {
                          if (!isCheckboxChecked) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Please agree to the terms and conditions')),
                            );
                            return;
                          }

                          otp = generateRandomOTP();
                          sendOtpRequest(emailAddressController.text, otp.toString());

                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (BuildContext context) {
                              return WillPopScope(
                                onWillPop: () async => false,
                                child: AlertDialog(
                                  title: Text('Enter OTP'),
                                  content: YourWidget(
                                    otpController: otpController,
                                    onSubmit: (enteredOtp) {
                                      verifyOtp(enteredOtp);
                                    },
                                  ),
                                ),
                              );
                            },
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white,
                          width: 1.0,
                        ),
                      ),
                      child: Text('Register'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isLoading)
          AbsorbPointer(
            child: Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9B29)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class YourWidget extends StatelessWidget {
  final TextEditingController otpController;
  final Function(String) onSubmit;

  YourWidget({
    required this.otpController,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: otpController,
          decoration: InputDecoration(labelText: 'OTP'),
          keyboardType: TextInputType.number,
        ),
        SizedBox(height: 16.0),
        ElevatedButton(
          onPressed: () {
            onSubmit(otpController.text);
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