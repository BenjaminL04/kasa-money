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

def send_post_request(admin_key, first_name, username):
    api_url = "API_BASE_URL/lnurlp/api/v1/links"
    headers = {
        "X-Api-Key": admin_key,
        "Content-Type": "application/json"
    }
    body = {
        "description": f"Payment to {first_name}",
        "min": 1,
        "max": 1000000000000,
        "comment_chars": 32,
        "fiat_base_multiplier": 100,
        "username": username,
        "zaps": False
    }
    try:
        response = requests.post(api_url, headers=headers, json=body)
        response_data = response.json()
        
        if response.status_code == 201 and "id" in response_data:
            return {"message": "success"}, 200


        return response.json(), response.status_code
    except requests.exceptions.RequestException as err:
        return {"error": f"Error sending POST request: {err}"}, 500

def get_email_for_token(token, nonce, signature, username):
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
            return {"error": "Token not found."}, 404
        email, x_base64, y_base64 = result

        # Check if the signature was previously used
        cursor.execute("SELECT signature FROM used_signatures WHERE email = %s AND signature = %s", (email, signature))
        if cursor.fetchone():
            return {"error": "Signature has already been used."}, 400

        # Verify the signature
        if not verify_signature(token, nonce, signature, x_base64, y_base64):
            return {"error": "Signature verification failed."}, 400

        # Insert the new signature into used_signatures table
        cursor.execute("INSERT INTO used_signatures (email, signature) VALUES (%s, %s)", (email, signature))
        connection.commit()

        return get_phone_number_for_email(email, username)
    except mysql.connector.Error as err:
        return {"error": f"Error: {err}"}, 500
    finally:
        if 'cursor' in locals() and cursor is not None:
            cursor.close()
        if 'connection' in locals() and connection.is_connected():
            connection.close()

def get_phone_number_for_email(email, username):
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
        if result:
            phone_number = result[0]
            return get_read_key_and_first_name_for_phone_number(phone_number, username)
        else:
            return {"error": "Email not found in the 'users' table"}, 404
    except mysql.connector.Error as err:
        return {"error": f"Error: {err}"}, 500
    finally:
        if 'cursor' in locals() and cursor is not None:
            cursor.close()
        if 'connection' in locals() and connection.is_connected():
            connection.close()

def get_read_key_and_first_name_for_phone_number(phone_number, username):
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
        if result:
            admin_key = result[0]
            return send_post_request(admin_key, "User", username)
        else:
            return {"error": "Phone number not found in the 'creds' table"}, 404
    except mysql.connector.Error as err:
        return {"error": f"Error: {err}"}, 500
    finally:
        if 'cursor' in locals() and cursor is not None:
            cursor.close()
        if 'connection' in locals() and connection.is_connected():
            connection.close()

@app.route('/create_lnurl', methods=['POST'])
def create_lnurl():
    try:
        token = request.json.get('token')
        nonce = request.json.get('nonce')
        signature = request.json.get('signature')
        username = request.json.get('username')
        response, status_code = get_email_for_token(token, nonce, signature, username)
        return jsonify(response), status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(port=5014)

