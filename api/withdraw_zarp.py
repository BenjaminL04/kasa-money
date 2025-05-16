from flask import Flask, request, jsonify
import mysql.connector
import base64
import hashlib
from ecdsa import VerifyingKey, NIST256p
from ecdsa.util import string_to_number
import smtplib
from email.mime.text import MIMEText
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

# SMTP Configuration
SMTP_EMAIL = os.getenv("SMTP_EMAIL")
SMTP_SERVER = os.getenv("SMTP_SERVER")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD")
SMTP_PORT = int(os.getenv("SMTP_PORT", 587))


# Database Configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

def verify_signature(token, nonce, signature_base64, x_base64, y_base64):
    try:
        # Decode x and y coordinates from Base64
        x_bytes = base64.b64decode(x_base64)
        y_bytes = base64.b64decode(y_base64)

        # Concatenate x and y bytes for key reconstruction
        public_key_bytes = x_bytes + y_bytes
        
        # Create public key from raw bytes
        verifying_key = VerifyingKey.from_string(public_key_bytes, curve=NIST256p)

        # Create the message with nonce
        message_with_nonce = f"{token}:{nonce}"
        message_hash = hashlib.sha256(message_with_nonce.encode()).digest()

        # Decode the signature from Base64
        signature_bytes = base64.b64decode(signature_base64)

        # Verify the signature
        return verifying_key.verify(signature_bytes, message_hash, hashfunc=hashlib.sha256)
    except Exception as e:
        print(f"Error verifying signature: {e}")
        return False

def send_email(phone_number, email, first_name, last_name, amount, country, bank_name, account_number):
    body = f"""New withdrawal request:

Phone Number: {phone_number}
Email: {email}
First Name: {first_name}
Last Name: {last_name}
Amount: {amount} ZAR
Country: {country}
Bank Name: {bank_name}
Account Number: {account_number}
"""
    msg = MIMEText(body)
    msg['Subject'] = 'New Withdrawal'
    msg['From'] = SMTP_USER
    msg['To'] = 'benjamin@btckhaya.com'

    try:
        with smtplib.SMTP_SSL(SMTP_SERVER, SMTP_PORT) as server:
            server.login(SMTP_USER, SMTP_PASSWORD)
            server.send_message(msg)
        print("Email sent successfully")
    except Exception as e:
        print(f"Error sending email: {e}")

@app.route('/withdraw_zarp', methods=['POST'])
def withdraw_zarp():
    try:
        # Get POST data
        data = request.get_json()
        token = data.get('token')
        nonce = data.get('nonce')
        signature = data.get('signature')
        bank_name = data.get('bank_name')
        account_number = data.get('account_number')
        country = data.get('country')
        amount = float(data.get('amount'))  # Ensure amount is a float

        # Database connection
        connection = mysql.connector.connect(**DB_CONFIG)
        cursor = connection.cursor()

        # Fetch email, x, y from tokens table
        cursor.execute("SELECT email, x, y FROM tokens WHERE token = %s", (token,))
        result = cursor.fetchone()
        if not result:
            return jsonify({"error": "Token not found."}), 400
        email, x_base64, y_base64 = result

        # Verify signature
        if not verify_signature(token, nonce, signature, x_base64, y_base64):
            return jsonify({"error": "Signature verification failed."}), 401

        # Check if signature was used before
        cursor.execute("SELECT signature FROM used_signatures WHERE email = %s AND signature = %s", (email, signature))
        if cursor.fetchone():
            return jsonify({"error": "Signature already used."}), 400
        cursor.execute("INSERT INTO used_signatures (email, signature) VALUES (%s, %s)", (email, signature))

        # Fetch phone number, first_name, and last_name from users table
        cursor.execute("SELECT phone_number, first_name, last_name FROM users WHERE email = %s", (email,))
        user_result = cursor.fetchone()
        if not user_result:
            return jsonify({"error": "User details not found for the given email."}), 400
        phone_number, first_name, last_name = user_result

        # Check balance
        cursor.execute("SELECT balance FROM zarp_balances WHERE phone_number = %s", (phone_number,))
        balance_result = cursor.fetchone()
        if not balance_result or float(balance_result[0]) < amount:  # Convert Decimal to float
            return jsonify({"error": "Insufficient balance."}), 400
        current_balance = float(balance_result[0])  # Convert to float for arithmetic

        # Insert into zarp_withdrawals
        cursor.execute("""
            INSERT INTO zarp_withdrawals (phone_number, amount, country, bank_name, account_number, signature, completed)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (phone_number, amount, country, bank_name, account_number, signature, 0))

        # Insert into zarp_transactions
        cursor.execute("""
            INSERT INTO zarp_transactions (sender_phone_number, amount, receiver_phone_number, type, signature)
            VALUES (%s, %s, %s, %s, %s)
        """, (phone_number, amount, "27000000000", "withdrawal", signature))

        # Update balance
        new_balance = current_balance - amount  # Now both are floats
        cursor.execute("""
            UPDATE zarp_balances 
            SET balance = %s 
            WHERE phone_number = %s
        """, (new_balance, phone_number))

        # Commit all database changes
        connection.commit()

        # Send email notification with all details
        send_email(phone_number, email, first_name, last_name, amount, country, bank_name, account_number)

        return jsonify({"message": "withdrawal_complete"}), 200

    except mysql.connector.Error as db_err:
        print(f"Database error: {db_err}")
        return jsonify({"error": "Database error occurred."}), 500
    except ValueError as ve:
        print(f"Value error: {ve}")
        return jsonify({"error": "Invalid amount format."}), 400
    except Exception as e:
        print(f"Error: {e}")
        return jsonify({"error": "An error occurred."}), 500
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

if __name__ == '__main__':
    app.run(port=5036)
