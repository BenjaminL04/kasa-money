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

def search_token_in_db(token, amount, nonce, signature):
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

        # Check if the signature was previously used
        cursor.execute("SELECT signature FROM used_signatures WHERE email = %s AND signature = %s", (email, signature))
        if cursor.fetchone():
            return {"error": "Signature has already been used."}

        # Verify the signature
        if not verify_signature(token, nonce, signature, x_base64, y_base64):
            return {"error": "Signature verification failed."}

        # Insert the new signature into used_signatures table
        cursor.execute("INSERT INTO used_signatures (email, signature) VALUES (%s, %s)", (email, signature))
        connection.commit()

        # Fetch phone number and first name
        cursor.execute("SELECT phone_number, first_name FROM users WHERE email = %s", (email,))
        user_result = cursor.fetchone()
        if not user_result:
            return {"error": "Phone number not found for the given email."}
        phone_number, first_name = user_result

        # Fetch read_key
        cursor.execute("SELECT read_key FROM creds WHERE phone_number = %s", (phone_number,))
        read_key_result = cursor.fetchone()
        if not read_key_result:
            return {"error": "read_key not found for the given phone number."}
        read_key = read_key_result[0]

        # Prepare API request payload
        payload = {
            "out": False,
            "amount": amount,
            "memo": f"Payment to {first_name}",
            "expiry": 86400,
            "unit": "sat",
            "webhook": "https://wallet.btckhaya.com/webhook",
            "internal": False
        }
        headers = {"X-Api-Key": read_key}

        # Make the API request
        response = requests.post("API_BASE_URL/api/v1/payments", json=payload, headers=headers)

        if 'bolt11' in response.json():
            return response.json()['bolt11']
        else:
            return {"error": "Payment request not found in the response."}
    except mysql.connector.Error as err:
        return {"error": f"Database error: {err}"}
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/create_invoice', methods=['POST'])
def create_invoice():
    data = request.get_json()
    if 'token' in data and 'amount' in data and 'nonce' in data and 'signature' in data:
        token = data['token']
        amount = data['amount']
        nonce = data['nonce']
        signature = data['signature']

        payment_request = search_token_in_db(token, amount, nonce, signature)
        return jsonify({"payment_request": payment_request})
    else:
        return jsonify({"error": "Missing required parameters."})

if __name__ == '__main__':
    app.run(port=5011)

