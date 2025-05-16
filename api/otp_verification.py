from flask import Flask, request, jsonify
import hashlib
import mysql.connector
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

# Function to generate an ECDSA signature
def generate_signature(private_key_b64, nonce):
    private_key_bytes = base64.b64decode(private_key_b64)
    sk = ecdsa.SigningKey.from_string(private_key_bytes, curve=ecdsa.NIST256p)
    signature = sk.sign(nonce.encode())
    return base64.b64encode(signature).decode('utf-8')

@app.route('/otp_verification', methods=['POST'])
def otp_verification():
    try:
        data = request.get_json()
        email = data.get('email')
        signature = data.get('signature')
        otp_sha256 = data.get('otp')

        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        # Check if the email and signature match
        cursor.execute("SELECT otp, used, attempts FROM otp_passwords WHERE email = %s AND signature = %s", (email, signature))
        record = cursor.fetchone()
        
        if not record:
            return jsonify({'message': 'Invalid email or signature'}), 400

        stored_otp, used, attempts = record

        # Check if OTP is already used
        if used == 1:
            return jsonify({'message': 'OTP already used'}), 400

        # Check if attempts are 3 or more
        if attempts >= 3:
            return jsonify({'message': 'No more attempts'}), 403

        # Verify the OTP
        if otp_sha256 != stored_otp:
            cursor.execute("UPDATE otp_passwords SET attempts = attempts + 1 WHERE email = %s AND signature = %s", (email, signature))
            connection.commit()
            return jsonify({'message': 'Wrong pin'}), 400

        # Mark OTP as used
        cursor.execute("UPDATE otp_passwords SET used = 1 WHERE email = %s AND signature = %s", (email, signature))
        
        # Retrieve private key to generate a new signature
        cursor.execute("SELECT private_key FROM login_keys LIMIT 1")
        key_result = cursor.fetchone()
        
        if not key_result:
            return jsonify({'message': 'No private key found'}), 500
        
        private_key_b64 = key_result[0]
        nonce = base64.b64encode(os.urandom(16)).decode('utf-8')
        new_signature = generate_signature(private_key_b64, nonce)
        
        # Insert new signature into used_password_signatures
        insert_query = """
        INSERT INTO used_password_signatures (email, signature, used)
        VALUES (%s, %s, %s)
        """
        cursor.execute(insert_query, (email, new_signature, 0))
        connection.commit()

        cursor.close()
        connection.close()

        return jsonify({'message': 'OTP verified successfully', 'signature': new_signature})
    
    except Exception as e:
        print(f"Error: {e}")
        return jsonify({'message': 'Error processing the request'}), 500

if __name__ == '__main__':
    app.run(port=5034)

