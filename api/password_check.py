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

# Function to hash the password using SHA-256
def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()

# Function to generate an ECDSA signature
def generate_signature(private_key_b64, nonce):
    private_key_bytes = base64.b64decode(private_key_b64)
    sk = ecdsa.SigningKey.from_string(private_key_bytes, curve=ecdsa.NIST256p)
    signature = sk.sign(nonce.encode())
    return base64.b64encode(signature).decode('utf-8')

# Endpoint to check the password
@app.route('/password_check', methods=['POST'])
def password_check():
    try:
        data = request.get_json()
        email = data.get('email')
        password = data.get('password')

        # Connect to the database
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        # Search for the user by email
        query = "SELECT password FROM users WHERE email = %s"
        cursor.execute(query, (email,))
        result = cursor.fetchone()

        if result:
            stored_password = result[0]
            hashed_password = hash_password(password)

            # Check if the hashed password matches the stored password
            if hashed_password == stored_password:
                # Retrieve private key from database
                cursor.execute("SELECT private_key FROM login_keys LIMIT 1")
                key_result = cursor.fetchone()

                if key_result:
                    private_key_b64 = key_result[0]
                    nonce = base64.b64encode(os.urandom(16)).decode('utf-8')
                    signature = generate_signature(private_key_b64, nonce)
                    
                    # Insert signature, email, and nonce into btckhaya.used_login_signatures with used = 0
                    insert_query = """
                        INSERT INTO used_login_signatures (email, signature, nonce, used)
                        VALUES (%s, %s, %s, %s)
                    """
                    cursor.execute(insert_query, (email, signature, nonce, 0))
                    connection.commit()
                    
                    response = {'message': 'Password correct', 'signature': signature}
                else:
                    response = {'message': 'Password correct, but no private key found'}
            else:
                response = {'message': 'Password incorrect'}
        else:
            response = {'message': 'User doesn\'t exist'}

        cursor.close()
        connection.close()

        return jsonify(response)

    except Exception as e:
        print(f"Error: {e}", flush=True)
        return jsonify({'message': 'Error processing the request'})

if __name__ == '__main__':
    app.run(port=5001)

