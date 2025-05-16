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

        # Make API request
        api_url = 'API_BASE_URL/lnurlp/api/v1/links'
        headers = {'X-API-KEY': read_key}
        response = requests.get(api_url, headers=headers)

        # Parse response
        lnurls = []
        try:
            data = response.json()
            for item in data:
                username = item.get('username', '')
                lnurl = item.get('lnurl', '')
                lnurls.append({'username': username, 'lnurl': lnurl})
        except ValueError:
            print("Invalid JSON response from the API.")
            return None

        return lnurls
    except mysql.connector.Error as err:
        return {"error": f"Database error: {err}"}
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/get_lnurls', methods=['POST'])
def get_lnurls_route():
    try:
        # Get request parameters
        token = request.json.get('token')
        nonce = request.json.get('nonce')
        signature = request.json.get('signature')

        if not token or not nonce or not signature:
            return jsonify({"error": "Missing required parameters."})

        # Perform the search and get lnurls
        lnurls = search_token_in_db(token, nonce, signature)

        if lnurls is not None:
            return jsonify(lnurls)
        else:
            return jsonify({'error': 'Error retrieving lnurls'})
    except Exception as e:
        return jsonify({'error': str(e)})

if __name__ == "__main__":
    app.run(port=5010)

