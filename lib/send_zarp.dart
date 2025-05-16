import 'package:flutter/material.dart';
import 'details.dart'; // Import your details.dart file
import 'send_user_zarp.dart'; // Import your invoice.dart file
import 'withdraw_zarp.dart';
import 'send_onchain.dart'; // Import the new send_onchain.dart file

class SendZarpPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white), // Make back button white
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => WithdrawZarpPage()),
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
              child: Text(
                'Withdraw to Bank account',
                style: TextStyle(color: Colors.white),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SendUserZarpPage()),
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
              child: Text(
                'Send Zarp',
                style: TextStyle(color: Colors.white),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SendOnChainPage()),
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
              child: Text(
                'Send On-Chain',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}