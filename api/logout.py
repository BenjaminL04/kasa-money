from flask import Flask, request, jsonify
import mysql.connector
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
        print(f"Error retrieving email for token: {err}")
        return None
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

def delete_user_data(email):
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }
    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()
        cursor.execute("DELETE FROM tokens WHERE email = %s", (email,))
        cursor.execute("DELETE FROM used_signatures WHERE email = %s", (email,))
        connection.commit()
        return True
    except mysql.connector.Error as err:
        print(f"Error deleting user data: {err}")
        return False
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/logout', methods=['POST'])
def logout():
    data = request.json
    if 'token' not in data or 'signature' not in data or 'nonce' not in data:
        return jsonify({'error': 'Missing required parameters'}), 400

    token, signature, nonce = data['token'], data['signature'], data['nonce']
    email_data = get_email_for_token(token)
    if email_data is None:
        return jsonify({'error': 'Token not found'}), 404

    email, x_base64, y_base64 = email_data

    if not verify_signature(token, nonce, signature, x_base64, y_base64):
        return jsonify({'error': 'Signature verification failed'}), 400

    if delete_user_data(email):
        return jsonify({'message': 'User successfully logged out and data deleted'}), 200
    else:
        return jsonify({'error': 'Error deleting user data'}), 500

if __name__ == '__main__':
    app.run(port=5032)

