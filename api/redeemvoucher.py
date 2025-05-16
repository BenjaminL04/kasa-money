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

def is_signature_used(signature):
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }
    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()
        cursor.execute("SELECT COUNT(*) FROM used_signatures WHERE signature = %s", (signature,))
        result = cursor.fetchone()
        return result[0] > 0
    except mysql.connector.Error as err:
        print(f"Error checking used signature: {err}")
        return True  # Assume used if there's an error
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

def record_used_signature(email, signature):
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }
    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()
        cursor.execute("INSERT INTO used_signatures (email, signature) VALUES (%s, %s)", (email, signature))
        connection.commit()
    except mysql.connector.Error as err:
        print(f"Error inserting used signature: {err}")
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

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
        query = "SELECT admin_key FROM creds WHERE phone_number = %s"
        cursor.execute(query, (phone_number,))
        result = cursor.fetchone()
        return result[0] if result else None
    except mysql.connector.Error as err:
        return None
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

def post_payment_request(admin_key, amount, lnurl_callback):
    url = "API_BASE_URL/api/v1/payments"
    headers = {'X-API-KEY': admin_key, 'Content-Type': 'application/json'}
    payload = {"unit": "sat", "out": False, "amount": amount, "memo": "voucher", "lnurl_callback": lnurl_callback}
    try:
        response = requests.post(url, headers=headers, json=payload)
        return response.json()
    except requests.exceptions.RequestException as e:
        return None

def get_email_for_token(token):
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }
    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()
        query = "SELECT email, x, y FROM tokens WHERE token = %s"
        cursor.execute(query, (token,))
        result = cursor.fetchone()
        if not result:
            return None
        email, x_base64, y_base64 = result
        return email, x_base64, y_base64
    except mysql.connector.Error as err:
        return None
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
        query = "SELECT phone_number FROM users WHERE email = %s"
        cursor.execute(query, (email,))
        result = cursor.fetchone()
        return result[0] if result else None
    except mysql.connector.Error as err:
        return None
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/redeemvoucher', methods=['POST'])
def redeem_voucher():
    data = request.json
    if 'token' not in data or 'nonce' not in data or 'signature' not in data or 'amount' not in data or 'lnurl_callback' not in data:
        return jsonify({'error': 'Missing required parameters'}), 400

    token, nonce, signature = data['token'], data['nonce'], data['signature']
    amount, lnurl_callback = data['amount'], data['lnurl_callback']

    if is_signature_used(signature):
        return jsonify({'error': 'Signature already used'}), 400

    email_data = get_email_for_token(token)
    if email_data is None:
        return jsonify({'error': 'Token not found'}), 404
    email, x_base64, y_base64 = email_data

    if not verify_signature(token, nonce, signature, x_base64, y_base64):
        return jsonify({'error': 'Signature verification failed'}), 400

    record_used_signature(email, signature)

    phone_number = get_phone_number_for_user(email)
    if not phone_number:
        return jsonify({'error': 'Phone number not found for user'}), 404

    admin_key = get_admin_key_for_phone(phone_number)
    if not admin_key:
        return jsonify({'error': 'Admin key not found for phone number'}), 404

    response = post_payment_request(admin_key, amount, lnurl_callback)
    if not response:
        return jsonify({'error': 'Error processing payment request'}), 500

    return jsonify(response), 200

if __name__ == '__main__':
    app.run(port=5030)

