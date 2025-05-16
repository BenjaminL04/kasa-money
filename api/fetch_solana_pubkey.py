from flask import Flask, request, jsonify
import mysql.connector
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

# MySQL database configuration
db_config = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

@app.route('/fetch_solana_pubkey', methods=['POST'])
def fetch_solana_pubkey():
    try:
        # Check if request is JSON
        if not request.is_json:
            return jsonify({"error": "Request must be application/json"}), 400

        # Get JSON data
        data = request.get_json()
        token = data.get('token')

        # Validate token
        if not token or not isinstance(token, str):
            return jsonify({"error": "Invalid or missing 'token' in JSON payload"}), 400

        # Connect to the MySQL database
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()

        # Step 1: Search tokens table for email
        cursor.execute("SELECT email FROM btckhaya.tokens WHERE token = %s", (token,))
        token_result = cursor.fetchone()
        if not token_result:
            return jsonify({"error": f"Token '{token}' not found in tokens table"}), 404

        email = token_result[0]

        # Step 2: Search users table for phone_number
        cursor.execute("SELECT phone_number FROM btckhaya.users WHERE email = %s", (email,))
        user_result = cursor.fetchone()
        if not user_result:
            return jsonify({"error": f"Email '{email}' not found in users table"}), 404

        phone_number = user_result[0]

        # Step 3: Search solana_addresses table for pubkey
        cursor.execute("SELECT pubkey FROM btckhaya.solana_addresses WHERE phone_number = %s", (phone_number,))
        address_result = cursor.fetchone()
        if not address_result:
            return jsonify({"error": f"Phone number '{phone_number}' not found in solana_addresses table"}), 404

        pubkey = address_result[0]
        return jsonify({"pubkey": pubkey}), 200

    except mysql.connector.Error as err:
        return jsonify({"error": f"Database error: {err}"}), 500
    except Exception as e:
        return jsonify({"error": f"Server error: {e}"}), 500
    finally:
        if 'cursor' in locals():
            cursor.close()
        if 'conn' in locals() and conn.is_connected():
            conn.close()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5039, debug=False)
