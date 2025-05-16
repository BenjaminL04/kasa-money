from flask import Flask, request, jsonify
import mysql.connector
import random
import string
import hashlib
import base64
import ecdsa
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

# Function to generate a random 64-digit hex token
def generate_token():
    return ''.join(random.choices(string.hexdigits, k=64))

# Function to hash serial using SHA-256
def hash_serial(serial):
    return hashlib.sha256(serial.encode()).hexdigest()

# Function to verify ECDSA signature
def verify_signature(signature_b64, nonce, x_b64, y_b64):
    try:
        signature = base64.b64decode(signature_b64)
        nonce_bytes = nonce.encode()
        x_bytes = base64.b64decode(x_b64)
        y_bytes = base64.b64decode(y_b64)
        x_int = int.from_bytes(x_bytes, byteorder='big')
        y_int = int.from_bytes(y_bytes, byteorder='big')
        public_key = ecdsa.VerifyingKey.from_public_point(
            ecdsa.ellipticcurve.Point(ecdsa.NIST256p.curve, x_int, y_int), curve=ecdsa.NIST256p
        )
        return public_key.verify(signature, nonce_bytes)
    except Exception as e:
        print(f"Signature verification failed: {e}", flush=True)
        return False

# Endpoint for /login
@app.route('/login', methods=['POST'])
def login():
    try:
        # Get data from request
        email = request.json.get('email')
        serial = request.json.get('serial')
        expiry = request.json.get('expiry')
        signature = request.json.get('signature')
        x = request.json.get('x')  # Added x
        y = request.json.get('y')  # Added y

        # Validate required fields
        if not email or not serial or not expiry or not signature or not x or not y:
            return jsonify({'error': 'Missing required fields'}), 400

        # Validate expiry timestamp
        if not isinstance(expiry, int) or expiry <= 0:
            return jsonify({'error': 'Invalid expiry timestamp'}), 400

        # Connect to the database
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        # Retrieve nonce associated with the signature
        cursor.execute("""
            SELECT nonce, used FROM used_login_signatures WHERE email = %s AND signature = %s
        """, (email, signature))
        result = cursor.fetchone()

        if not result:
            return jsonify({'error': 'Signature not found'}), 403

        nonce, used = result

        if used == 1:  # If used = 1, return error
            return jsonify({'error': 'Signature has already been used'}), 403

        # Retrieve public key coordinates
        cursor.execute("SELECT x, y FROM login_keys LIMIT 1")
        key_result = cursor.fetchone()

        if not key_result:
            return jsonify({'error': 'Public key not found'}), 500

        x_b64, y_b64 = key_result

        # Verify the signature
        if not verify_signature(signature, nonce, x_b64, y_b64):
            return jsonify({'error': 'Signature verification failed'}), 403

        # Proceed with login logic
        serial_hash = hash_serial(serial)
        token = generate_token()

        # Insert into the tokens table, including x and y
        insert_query = """
            INSERT INTO tokens (email, token, expiry, serial, x, y)
            VALUES (%s, %s, %s, %s, %s, %s)
        """
        cursor.execute(insert_query, (email, token, expiry, serial_hash, x, y))
        connection.commit()

        # Update used_login_signatures table to mark used = 1
        update_signature_query = """
            UPDATE used_login_signatures SET used = 1 WHERE email = %s AND signature = %s
        """
        cursor.execute(update_signature_query, (email, signature))
        connection.commit()

        cursor.close()
        connection.close()

        response = {
            'token': token,
            'expiry': expiry,
            'serial': serial_hash,
            'x': x,
            'y': y
        }
        return jsonify(response)

    except Exception as e:
        print(f"Error: {e}", flush=True)
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(port=5007, debug=True)

