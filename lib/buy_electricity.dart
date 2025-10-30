import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/api.dart' hide Padding;
import 'package:pointycastle/digests/sha256.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BuyElectricityPage extends StatefulWidget {
  @override
  _BuyElectricityPageState createState() => _BuyElectricityPageState();
}

class _BuyElectricityPageState extends State<BuyElectricityPage> {
  List<Map<String, String>> meters = [];
  int _selectedIndex = 0;

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
    _fetchPowertimeToken();
    _fetchMeters();
  }

  Future<void> _fetchPowertimeToken() async {
    try {
      final response = await http.post(
        Uri.parse('https://db.btckhaya.com/powertime_login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token']?.toString();
        if (token != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('powertime_token', token);
          print('Powertime token saved: $token');
        } else {
          print('No token found in response');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No token received from server')),
          );
        }
      } else {
        print('Failed to fetch powertime token: ${response.statusCode}');
        print('Powertime login response: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch token: ${response.body}')),
        );
      }
    } catch (e) {
      print('Error fetching powertime token: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching token: ${e.toString()}')),
      );
    }
  }

  Future<void> _fetchMeters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localToken = prefs.getString('auth_token');

      if (localToken == null) {
        print('No auth token found');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No auth token found')),
        );
        return;
      }

      final response = await http.post(
        Uri.parse('https://db.btckhaya.com/register_meter'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'request',
          'local_token': localToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['meters'] != null && data['meters'] is List) {
          setState(() {
            meters = List<Map<String, String>>.from(
              data['meters'].map((meter) => {
                    'name': meter['meter_name'].toString(),
                    'number': meter['meter_number'].toString(),
                    'meter_id': meter['meter_id'].toString(),
                  }),
            );
          });
        } else {
          print('No meters found in response');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No meters found in response')),
          );
        }
      } else {
        print('Failed to fetch meters: ${response.statusCode}');
        print('Register meter response: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch meters: ${response.body}')),
        );
      }
    } catch (e) {
      print('Error fetching meters: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching meters: ${e.toString()}')),
      );
    }
  }

  Future<List<Map<String, String>>> _fetchPurchaseHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localToken = prefs.getString('auth_token');

      if (localToken == null) {
        print('No auth token found');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No auth token found')),
        );
        return [];
      }

      final response = await http.post(
        Uri.parse('https://db.btckhaya.com/register_meter'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'history',
          'token': localToken,
        }),
      );

      print('Purchase history response status: ${response.statusCode}');
      print('Purchase history response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['history'] != null && data['history'] is List) {
          return data['history'].map<Map<String, String>>((item) {
            final voucher = item['sender_reference']?.toString().trim() ?? '';
            final formattedVoucher = voucher.length == 20
                ? voucher.replaceAllMapped(RegExp(r'.{4}'), (match) => '${match.group(0)!}-').substring(0, 24)
                : voucher;
            return {
              'amount': item['amount']?.toString() ?? '0.0',
              'sender_reference': formattedVoucher,
            };
          }).toList();
        } else {
          print('Invalid history response format');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid history response format')),
          );
          return [];
        }
      } else {
        print('Failed to fetch purchase history: ${response.statusCode}');
        print('Purchase history response: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch purchase history: ${response.body}')),
        );
        return [];
      }
    } catch (e) {
      print('Error fetching purchase history: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching purchase history: ${e.toString()}')),
      );
      return [];
    }
  }

  void _showRegisterMeterDialog() {
    String? meterName;
    String? meterNumber;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          title: Text('Register New Meter', style: TextStyle(color: Colors.white)),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      keyboardType: TextInputType.text,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Meter Name',
                        labelStyle: TextStyle(color: Colors.white),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      onChanged: (val) {
                        setDialogState(() => meterName = val);
                      },
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Meter Number',
                        labelStyle: TextStyle(color: Colors.white),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      onChanged: (val) {
                        setDialogState(() => meterNumber = val);
                      },
                    ),
                    SizedBox(height: 20),
                    isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              side: BorderSide(color: Colors.white, width: 2),
                              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                            ),
                            onPressed: () async {
                              if (meterName == null || meterName!.isEmpty || meterNumber == null || meterNumber!.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Please fill in both Meter Name and Meter Number')),
                                );
                                return;
                              }

                              setDialogState(() => isLoading = true);

                              try {
                                final prefs = await SharedPreferences.getInstance();
                                final powertimeToken = prefs.getString('powertime_token');
                                final localToken = prefs.getString('auth_token');

                                if (powertimeToken == null || localToken == null) {
                                  setDialogState(() => isLoading = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Missing tokens in storage')),
                                  );
                                  return;
                                }

                                final response = await http.post(
                                  Uri.parse('https://db.btckhaya.com/register_meter'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode({
                                    'type': 'register',
                                    'powertime_token': powertimeToken,
                                    'local_token': localToken,
                                    'meter_name': meterName,
                                    'meter_number': meterNumber,
                                  }),
                                );

                                setDialogState(() => isLoading = false);

                                if (response.statusCode == 200 && response.body.trim() == '"success"') {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Meter registered successfully')),
                                  );
                                  _fetchMeters();
                                } else {
                                  print('Failed to register meter: ${response.statusCode}');
                                  print('Register meter response: ${response.body}');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed to register meter: ${response.body}')),
                                  );
                                }
                              } catch (e) {
                                setDialogState(() => isLoading = false);
                                print('Error registering meter: $e');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error registering meter: ${e.toString()}')),
                                );
                              }
                            },
                            child: Text('Submit'),
                          ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showBuyElectricityDialog(Map<String, String> meter) {
    String? amount;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          title: Text('Buy Electricity for ${meter['name']}', style: TextStyle(color: Colors.white)),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Amount (R)',
                        labelStyle: TextStyle(color: Colors.white),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      onChanged: (val) {
                        setDialogState(() => amount = val);
                      },
                    ),
                    SizedBox(height: 20),
                    isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              side: BorderSide(color: Colors.white, width: 2),
                              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                            ),
                            onPressed: () async {
                              if (amount == null || amount!.isEmpty || double.tryParse(amount!) == null || double.parse(amount!) <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Please enter a valid amount')),
                                );
                                return;
                              }

                              setDialogState(() => isLoading = true);

                              try {
                                final prefs = await SharedPreferences.getInstance();
                                final powertimeToken = prefs.getString('powertime_token');
                                final localToken = prefs.getString('auth_token');
                                final privateKeyBase64 = prefs.getString('private_key');

                                if (powertimeToken == null || localToken == null || privateKeyBase64 == null) {
                                  setDialogState(() => isLoading = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Missing tokens or private key in storage')),
                                  );
                                  return;
                                }

                                final nonce = List<int>.generate(16, (i) => Random.secure().nextInt(256));
                                String nonceBase64 = base64Encode(nonce);
                                String messageWithNonce = "$localToken:$nonceBase64";
                                final messageHash = SHA256Digest().process(utf8.encode(messageWithNonce));
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

                                final requestBody = {
                                  'amount': double.parse(amount!),
                                  'meter_id': meter['meter_id'],
                                  'powertime_token': powertimeToken,
                                  'local_token': localToken,
                                  'signature': signatureBase64,
                                  'nonce': nonceBase64,
                                };

                                print('Buy electricity request body: ${jsonEncode(requestBody)}');

                                final response = await http.post(
                                  Uri.parse('https://db.btckhaya.com/buy_electricity'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode(requestBody),
                                );

                                print('Buy electricity response status: ${response.statusCode}');
                                print('Buy electricity response body: ${response.body}');

                                setDialogState(() => isLoading = false);

                                if (response.statusCode == 200) {
                                  final data = jsonDecode(response.body);
                                  final voucherNumber = data['voucher_number']?.toString().trim();
                                  if (voucherNumber != null && voucherNumber.length == 20) {
                                    String formattedVoucher = voucherNumber.replaceAllMapped(
                                        RegExp(r'.{4}'), (match) => '${match.group(0)!}-');
                                    formattedVoucher = formattedVoucher.substring(0, formattedVoucher.length - 1);

                                    Navigator.pop(context);
                                    showDialog(
                                      context: context,
                                      builder: (context) {
                                        return AlertDialog(
                                          backgroundColor: Colors.black87,
                                          title: Text('Voucher Number', style: TextStyle(color: Colors.white)),
                                          content: Text(
                                            formattedVoucher,
                                            style: TextStyle(color: Colors.white, fontSize: 16),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: Text('OK', style: TextStyle(color: Colors.white)),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  } else {
                                    print('Invalid or missing voucher number: $voucherNumber');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Invalid or missing voucher number')),
                                    );
                                  }
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed to purchase electricity: ${response.body}')),
                                  );
                                }
                              } catch (e) {
                                setDialogState(() => isLoading = false);
                                print('Error purchasing electricity: $e');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error purchasing electricity: ${e.toString()}')),
                                );
                              }
                            },
                            child: Text('Buy'),
                          ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showHistoryDialog() async {
    bool isLoading = true;
    List<Map<String, String>> history = [];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.black87,
              title: Text('Purchase History', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: double.maxFinite,
                child: isLoading
                    ? Center(child: CircularProgressIndicator(color: Colors.white))
                    : history.isEmpty
                        ? Text('No purchase history found', style: TextStyle(color: Colors.white))
                        : SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: history.map((item) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Amount: R${item['amount']}',
                                          style: TextStyle(color: Colors.white, fontSize: 16),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          'Voucher: ${item['sender_reference']}',
                                          style: TextStyle(color: Colors.white, fontSize: 16),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Close', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    history = await _fetchPurchaseHistory();
    setState(() {
      isLoading = false;
    });
    if (mounted) {
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: Colors.black87,
            title: Text('Purchase History', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              child: history.isEmpty
                  ? Text('No purchase history found', style: TextStyle(color: Colors.white))
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: history.map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Amount: R${item['amount']}',
                                    style: TextStyle(color: Colors.white, fontSize: 16),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Voucher: ${item['sender_reference']}',
                                    style: TextStyle(color: Colors.white, fontSize: 16),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Close', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 1) {
      _showHistoryDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Buy Electricity'),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white, width: 2),
                    padding: EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                    textStyle: TextStyle(fontSize: 18),
                  ),
                  onPressed: _showRegisterMeterDialog,
                  child: Text('Register New Meter'),
                ),
              ),
              SizedBox(height: 20),
              ...meters.map((meter) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              meter['name']!,
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Meter: ${meter['number']}',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white, width: 2),
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        onPressed: () => _showBuyElectricityDialog(meter),
                        child: Text('Buy'),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.electric_bolt),
            label: 'Buy',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}