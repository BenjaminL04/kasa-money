from flask import Flask, request, jsonify
import mysql.connector
import base64
from ecdsa import VerifyingKey, NIST256p
import hashlib
from decimal import Decimal
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

# Database configuration
db_config = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

def verify_signature(token, nonce, signature_base64, x_base64, y_base64):
    try:
        x_bytes = base64.b64decode(x_base64)
        y_bytes = base64.b64decode(y_base64)
        public_key_bytes = x_bytes + y_bytes
        verifying_key = VerifyingKey.from_string(public_key_bytes, curve=NIST256p)
        message_with_nonce = f"{token}:{nonce}"
        message_hash = hashlib.sha256(message_with_nonce.encode()).digest()
        signature_bytes = base64.b64decode(signature_base64)
        return verifying_key.verify(signature_bytes, message_hash, hashfunc=hashlib.sha256)
    except Exception as e:
        print(f"Error verifying signature: {e}")
        return False

@app.route('/send_zarp', methods=['POST'])
def send_zarp():
    connection = None
    cursor = None
    try:
        # Get data from request
        data = request.get_json()
        token = data.get('token')
        nonce = data.get('nonce')
        signature = data.get('signature')
        receiver_phone_number = data.get('receiver_phone_number')
        amount = Decimal(str(data.get('amount')))  # Convert to Decimal
        transaction_type = data.get('type', 'transfer')
        sender_reference = data.get('sender_reference')
        receiver_reference = data.get('receiver_reference')

        # Validate amount is positive and not zero
        if amount <= 0:
            return jsonify({"error": "Amount must be greater than zero."}), 400

        # Database connection
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        # Verify token and get sender info
        cursor.execute("SELECT email, x, y FROM tokens WHERE token = %s", (token,))
        result = cursor.fetchone()
        if not result:
            return jsonify({"error": "Token not found."}), 400
        email, x_base64, y_base64 = result

        # Verify signature
        if not verify_signature(token, nonce, signature, x_base64, y_base64):
            return jsonify({"error": "Signature verification failed."}), 400

        # Check if signature was used before
        cursor.execute("SELECT signature FROM used_signatures WHERE email = %s AND signature = %s", 
                      (email, signature))
        if cursor.fetchone():
            return jsonify({"error": "Signature already used."}), 400

        # Get sender phone number and verify existence
        cursor.execute("SELECT phone_number FROM users WHERE email = %s", (email,))
        sender_phone_result = cursor.fetchone()
        if not sender_phone_result:
            return jsonify({"error": "Sender phone number not found."}), 400
        sender_phone_number = sender_phone_result[0]

        # Check if receiver exists in users table
        cursor.execute("SELECT phone_number FROM users WHERE phone_number = %s", 
                      (receiver_phone_number,))
        receiver_exists = cursor.fetchone()
        if not receiver_exists:
            return jsonify({"error": "Receiver not found in users table."}), 400

        # Start transaction
        cursor.execute("START TRANSACTION")

        # Check sender balance
        cursor.execute("SELECT balance FROM zarp_balances WHERE phone_number = %s FOR UPDATE", 
                      (sender_phone_number,))
        sender_balance_result = cursor.fetchone()
        if not sender_balance_result or sender_balance_result[0] < amount:
            cursor.execute("ROLLBACK")
            return jsonify({"error": "Insufficient funds."}), 400
        sender_balance = sender_balance_result[0]

        # Check receiver exists in balances
        cursor.execute("SELECT balance FROM zarp_balances WHERE phone_number = %s FOR UPDATE", 
                      (receiver_phone_number,))
        receiver_balance_result = cursor.fetchone()
        if not receiver_balance_result:
            cursor.execute("ROLLBACK")
            return jsonify({"error": "Receiver account not found in balances."}), 400
        receiver_balance = receiver_balance_result[0]

        # Record transaction with optional references
        cursor.execute("""
            INSERT INTO zarp_transactions 
            (sender_phone_number, amount, receiver_phone_number, type, signature, sender_reference, receiver_reference)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (sender_phone_number, amount, receiver_phone_number, transaction_type, signature, 
              sender_reference, receiver_reference))

        # Update balances
        cursor.execute("UPDATE zarp_balances SET balance = %s WHERE phone_number = %s",
                      (sender_balance - amount, sender_phone_number))
        cursor.execute("UPDATE zarp_balances SET balance = %s WHERE phone_number = %s",
                      (receiver_balance + amount, receiver_phone_number))

        # Record used signature
        cursor.execute("INSERT INTO used_signatures (email, signature) VALUES (%s, %s)", 
                      (email, signature))

        # Commit transaction
        connection.commit()
        return jsonify({"message": "payment_complete"}), 200

    except mysql.connector.Error as db_err:
        if connection:
            connection.rollback()
        return jsonify({"error": f"Database error: {str(db_err)}"}), 500
    except Exception as e:
        if connection:
            connection.rollback()
        return jsonify({"error": f"Server error: {str(e)}"}), 500
    finally:
        if cursor:
            cursor.close()
        if connection:
            connection.close()

if __name__ == '__main__':
    app.run(port=5035)
