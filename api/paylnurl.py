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
        return email
    except mysql.connector.Error as err:
        return {"error": f"Database error: {err}"}
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

def send_post_request(admin_key, callback, amount, description_hash, description):
    url = "API_BASE_URL/api/v1/payments/lnurl"
    payload = {
        "description_hash": description_hash,
        "callback": callback,
        "amount": amount,
        "comment": "test",
        "description": description
    }
    headers = {'X-API-KEY': admin_key}
    try:
        response = requests.post(url, headers=headers, json=payload)
        return response.text

        print("Bitcoinkhaya API response:", response.text())

    except requests.RequestException as e:
        return f"Request error: {e}"

def get_admin_key_for_phone(phone_number):
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }
    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()
        cursor.execute("SELECT admin_key FROM creds WHERE phone_number = %s", (phone_number,))
        result = cursor.fetchone()
        return result[0] if result else None
    except mysql.connector.Error as err:
        return f"Error: {err}"
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

def get_phone_number_for_user(email):
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }
    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()
        cursor.execute("SELECT phone_number FROM users WHERE email = %s", (email,))
        result = cursor.fetchone()
        return result[0] if result else None
    except mysql.connector.Error as err:
        return f"Error: {err}"
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/paylnurl', methods=['POST'])
def pay_lnurl():
    data = request.get_json()
    if 'token' not in data or 'nonce' not in data or 'signature' not in data or 'callback' not in data or 'amount' not in data or 'description_hash' not in data or 'description' not in data:
        return jsonify({'error': 'Invalid request. Please provide all required variables.'}), 400

    token, nonce, signature = data['token'], data['nonce'], data['signature']
    callback, amount, description_hash, description = data['callback'], data['amount'], data['description_hash'], data['description']

    email = search_token_in_db(token, nonce, signature)
    if isinstance(email, dict) and "error" in email:
        return jsonify(email), 400

    phone_number = get_phone_number_for_user(email)
    if not phone_number:
        return jsonify({'error': 'User not found.'}), 404

    admin_key = get_admin_key_for_phone(phone_number)
    if not admin_key:
        return jsonify({'error': 'Admin key not found.'}), 404

    response = send_post_request(admin_key, callback, amount, description_hash, description)
    return jsonify({'response': response})

if __name__ == "__main__":
    app.run(port=5017)

