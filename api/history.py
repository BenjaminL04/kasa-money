from flask import Flask, request, jsonify
import mysql.connector
import requests
import base64
import hashlib
from ecdsa import VerifyingKey, NIST256p
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

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

def search_token_in_db(token, nonce, signature):
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }
    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        cursor.execute("SELECT email, x, y FROM tokens WHERE token = %s", (token,))
        result = cursor.fetchone()
        if not result:
            return {"error": "Token not found."}
        email, x_base64, y_base64 = result

        cursor.execute("SELECT signature FROM used_signatures WHERE email = %s AND signature = %s", (email, signature))
        if cursor.fetchone():
            return {"error": "Signature has already been used."}

        if not verify_signature(token, nonce, signature, x_base64, y_base64):
            return {"error": "Signature verification failed."}

        cursor.execute("INSERT INTO used_signatures (email, signature) VALUES (%s, %s)", (email, signature))
        connection.commit()

        cursor.execute("SELECT phone_number FROM users WHERE email = %s", (email,))
        user_result = cursor.fetchone()
        if not user_result:
            return {"error": "Phone number not found for the given email."}
        phone_number = user_result[0]

        cursor.execute("SELECT read_key FROM creds WHERE phone_number = %s", (phone_number,))
        read_key_result = cursor.fetchone()
        if not read_key_result:
            return {"error": "read_key not found for the given phone number."}
        read_key = read_key_result[0]

        url = "API_BASE_URL/api/v1/payments"
        headers = {
            "X-API-KEY": read_key,
            "Content-Type": "application/json"
        }
        payload = {"limit": 20, "direction": "desc"}

        response = requests.get(url, headers=headers, params=payload)
        data = response.json()

        filtered_data = [
            {
                "amount": item.get("amount", "N/A"),
                "memo": item.get("memo", "N/A"),
                "time": item.get("time", "N/A"),
                "bolt11": item.get("bolt11", "N/A"),
            }
            for item in data if not item.get("pending", True)
        ]

        return filtered_data
    except mysql.connector.Error as err:
        return {"error": f"Database error: {err}"}
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/history', methods=['POST'])
def get_payment_history():
    try:
        data = request.get_json()
        if 'token' not in data or 'nonce' not in data or 'signature' not in data:
            return jsonify({"error": "Missing required parameters."}), 400

        token = data['token']
        nonce = data['nonce']
        signature = data['signature']

        result = search_token_in_db(token, nonce, signature)
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(port=5015)

