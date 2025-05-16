from flask import Flask, request, jsonify
import mysql.connector
import requests
import base64
import hashlib
from ecdsa import VerifyingKey, NIST256p
from ecdsa.util import string_to_number
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

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

def calculate_balances(token, nonce, signature):
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }

    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        # Fetch email, x, y from tokens table
        cursor.execute("SELECT email, x, y FROM tokens WHERE token = %s", (token,))
        result = cursor.fetchone()
        if not result:
            return {"error": "Token not found."}
        email, x_base64, y_base64 = result

        # Verify the signature
        if not verify_signature(token, nonce, signature, x_base64, y_base64):
            return {"error": "Signature verification failed."}

        # Check if the signature was previously used
        cursor.execute("SELECT signature FROM used_signatures WHERE email = %s AND signature = %s", (email, signature))
        if not cursor.fetchone():
            cursor.execute("INSERT INTO used_signatures (email, signature) VALUES (%s, %s)", (email, signature))
            connection.commit()

        # Fetch phone number
        cursor.execute("SELECT phone_number FROM users WHERE email = %s", (email,))
        phone_number_result = cursor.fetchone()
        if not phone_number_result:
            return {"error": "Phone number not found for the given email."}
        phone_number = phone_number_result[0]

        # Fetch read_key
        cursor.execute("SELECT read_key FROM creds WHERE phone_number = %s", (phone_number,))
        read_key_result = cursor.fetchone()
        if not read_key_result:
            return {"error": "read_key not found for the given phone number."}
        read_key = read_key_result[0]

        # Fetch wallet balance
        response = requests.get('API_BASE_URL/api/v1/wallet', headers={'X-API-KEY': read_key})
        balance = response.json().get('balance', 0)
        sats_balance = round(balance / 1000)
        sats_balance_in_btc = sats_balance / 100000000

        # Fetch BTC to ZAR price
        binance_response = requests.get('https://api.binance.com/api/v3/ticker/price?symbol=BTCZAR')
        btc_to_zar_price = float(binance_response.json().get('price', 0))

        # Calculate ZAR balance
        zar_balance = round(sats_balance_in_btc * btc_to_zar_price, 2)

        # Fetch ZARP balance from zarp_balances table
        cursor.execute("SELECT balance FROM zarp_balances WHERE phone_number = %s", (phone_number,))
        zarp_balance_result = cursor.fetchone()
        if not zarp_balance_result:
            zarp_balance = 0.00  # Default to 0 if no balance found
        else:
            zarp_balance = float(zarp_balance_result[0])  # Convert to float for consistency

        return {
            'sats_balance': sats_balance,
            'zar_balance': zar_balance,
            'zarp_balance': zarp_balance
        }
    except mysql.connector.Error as err:
        return {"error": f"Database error: {err}"}
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/check_balance', methods=['POST'])
def check_balance():
    token = request.form.get('token')
    nonce = request.form.get('nonce')
    signature = request.form.get('signature')

    if token and nonce and signature:
        return jsonify(calculate_balances(token, nonce, signature))
    return jsonify({"error": "Missing required parameters."})

if __name__ == "__main__":
    app.run(port=5009)
