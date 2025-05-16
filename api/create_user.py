from flask import Flask, request, jsonify
import mysql.connector
import hashlib
import base64
import ecdsa
from dotenv import load_dotenv
import os
import base58
import json
from solders.keypair import Keypair

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

# Function to hash the password using SHA-256
def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()

# Function to generate an ECDSA signature
def generate_signature(private_key_b64, nonce):
    private_key_bytes = base64.b64decode(private_key_b64)
    sk = ecdsa.SigningKey.from_string(private_key_bytes, curve=ecdsa.NIST256p)
    signature = sk.sign(nonce.encode())
    return base64.b64encode(signature).decode('utf-8')

# Endpoint to create a user
@app.route('/create_user', methods=['POST'])
def create_user():
    try:
        # Get user data from the POST request
        user_data = request.json

        # Hash the password
        user_data['password'] = hash_password(user_data['password'])

        # Connect to the MySQL server
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        # Insert user data into the users table
        insert_user_query = """
            INSERT INTO users (first_name, last_name, email, phone_number, password)
            VALUES (%s, %s, %s, %s, %s)
        """
        cursor.execute(insert_user_query, (user_data['first_name'], user_data['last_name'], user_data['email'], user_data['phone_number'], user_data['password']))

        # Insert into zarp_balances table with balance = 0.00
        insert_balance_query = """
            INSERT INTO zarp_balances (phone_number, balance)
            VALUES (%s, %s)
        """
        cursor.execute(insert_balance_query, (user_data['phone_number'], 0.00))

        # Generate a Solana keypair
        keypair = Keypair()
        pubkey = str(keypair.pubkey())
        secret_key_bytes = bytes(keypair)
        bs58_private_key = base58.b58encode(secret_key_bytes).decode()
        uint8_array = list(secret_key_bytes)
        uint8_json = json.dumps(uint8_array)

        # Insert into solana_addresses table
        insert_solana_query = """
            INSERT INTO solana_addresses (phone_number, pubkey, BS58, unit8)
            VALUES (%s, %s, %s, %s)
        """
        cursor.execute(insert_solana_query, (user_data['phone_number'], pubkey, bs58_private_key, uint8_json))

        # Retrieve private key from database
        cursor.execute("SELECT private_key FROM login_keys LIMIT 1")
        key_result = cursor.fetchone()

        if key_result:
            private_key_b64 = key_result[0]
            nonce = base64.b64encode(os.urandom(16)).decode('utf-8')
            signature = generate_signature(private_key_b64, nonce)

            # Insert signature, email, and nonce into used_login_signatures with used = 0
            insert_signature_query = """
                INSERT INTO used_login_signatures (email, signature, nonce, used)
                VALUES (%s, %s, %s, %s)
            """
            cursor.execute(insert_signature_query, (user_data['email'], signature, nonce, 0))

            response = {"message": "User Created", "signature": signature}
        else:
            response = {"message": "User Created, but no private key found"}

        # Commit all changes
        connection.commit()

        cursor.close()
        connection.close()
        return jsonify(response)

    except Exception as e:
        print(f"Error: {e}", flush=True)
        return jsonify({"error": f"Error: {e}"}), 500

if __name__ == '__main__':
    app.run(port=5002)
