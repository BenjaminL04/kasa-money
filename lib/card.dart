import 'logged_in_home.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class CardPage extends StatefulWidget {
  @override
  _CardPageState createState() => _CardPageState();
}

class _CardPageState extends State<CardPage> {
  Future<String>? _cardStatusFuture;
  final baseUrl = dotenv.env['API_BASE_URL'];

  @override
  void initState() {
    super.initState();
    _loadCardStatus();
  }

  Future<void> _loadCardStatus() async {
    _cardStatusFuture = _sendBlockCheckRequest();
    await _cardStatusFuture;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Card Settings'),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: FutureBuilder<String>(
          future: _cardStatusFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return CircularProgressIndicator();
            } else if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            } else if (snapshot.hasData) {
              final cardStatus = snapshot.data!.toLowerCase();
              switch (cardStatus) {
                case 'unblocked':
                return ElevatedButton(
                  onPressed: () {
                    _blockCard();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, // Replaces primary
                    foregroundColor: Colors.black, // Replaces onPrimary
                  ),
                  child: Text('Block Card'),
                );
                case 'blocked':
                return ElevatedButton(
                  onPressed: () {
                    _unblockCard();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, // Replaces primary
                    foregroundColor: Colors.black, // Replaces onPrimary
                  ),
                  child: Text('Unblock Card'),
                );
                case 'card not found':
                  return Text('You don\'t have a card.');
                default:
                  return Text('Unknown card status: $cardStatus');
              }
            }

            return Text('Unknown state');
          },
        ),
      ),
      backgroundColor: Colors.black,
    );
  }

  Future<String> _sendBlockCheckRequest() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String authToken = prefs.getString('auth_token') ?? "";

      final fullUrl = '$baseUrl/blockcheck';

      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token': authToken}),
      );

      print('Block Check Response: ${response.statusCode}');
      print('Block Check Body: ${response.body}');

      if (response.statusCode == 200) {
        final String blockCheckData = response.body.toLowerCase();

        if (blockCheckData.contains('unblocked')) {
          return 'unblocked';
        } else if (blockCheckData.contains('blocked')) {
          return 'blocked';
        } else if (blockCheckData.contains('card information not found')) {
          _showCardNotFoundPopup(context);
          return 'card not found';
        }
      }

      return 'unknown';
    } catch (e) {
      print('Block Check Error: $e');
      throw Exception('Failed to fetch card status');
    }
  }

  Future<void> _blockCard() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String authToken = prefs.getString('auth_token') ?? "";

      final fullUrl2 = '$baseUrl/blockcard';

      final response = await http.post(
        Uri.parse(fullUrl2),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token': authToken}),
      );

      print('Block Card Response: ${response.statusCode}');
      print('Block Card Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> blockCardData = jsonDecode(response.body);

        if (blockCardData['status'] == 'blocked') {
          _showCardBlockedPopup(context);
          _navigateToLoggedInHomePageAfterDelay();
        }
      }
    } catch (e) {
      print('Block Card Error: $e');
    }
  }

  Future<void> _unblockCard() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String authToken = prefs.getString('auth_token') ?? "";

      final fullUrl3 = '$baseUrl/unblockcard';

      final response = await http.post(
        Uri.parse(fullUrl3),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token': authToken}),
      );

      print('Unblock Card Response: ${response.statusCode}');
      print('Unblock Card Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> unblockCardData = jsonDecode(response.body);

        if (unblockCardData['status'] == 'unblocked') {
          _showCardUnblockedPopup(context);
          _navigateToLoggedInHomePageAfterDelay();
        }
      }
    } catch (e) {
      print('Unblock Card Error: $e');
    }
  }

  void _showCardBlockedPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Card Blocked'),
          content: Text('Your card is now blocked.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showCardUnblockedPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Card Unblocked'),
          content: Text('Your card is now unblocked.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showCardNotFoundPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Card Not Found'),
          content: Text('You don\'t have a card.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _navigateToLoggedInHomePageAfterDelay() {
    Future.delayed(Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoggedInHomePage()), // Replace with your actual LoggedInHomePage widget
      );
    });
  }
}
