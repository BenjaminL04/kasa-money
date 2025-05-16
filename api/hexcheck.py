from flask import Flask, request, jsonify
import mysql.connector
from dotenv import load_dotenv
import os

load_dotenv()
API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

def check_card_exists(token, card_hex):
    # Database credentials
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }

    try:
        # Connect to the database
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        # Check if the token exists
        token_query = "SELECT * FROM tokens WHERE token = %s"
        cursor.execute(token_query, (token,))
        if not cursor.fetchone():
            return False, False  # Token does not exist, no need to check hex

        # Token exists, now check if card_hex exists
        card_query = "SELECT * FROM cards WHERE card_hex = %s"
        cursor.execute(card_query, (card_hex,))

        # Check if the card_hex exists
        hex_exists = bool(cursor.fetchone())
        return True, hex_exists

    except mysql.connector.Error as err:
        print(f"Error: {err}")
        return False, False

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/hexcheck', methods=['POST'])
def hex_check():
    data = request.get_json()

    # Check if 'token' and 'hex' are in the JSON data
    if 'token' not in data or 'hex' not in data:
        return jsonify({'error': 'Invalid JSON format'}), 400

    token = data['token']
    hex_value = data['hex']

    # Check if the card_hex exists in the "cards" table
    token_exists, hex_exists = check_card_exists(token, hex_value)

    response_data = {
        'token_exists': token_exists,
        'hex_exists': hex_exists
    }

    return jsonify(response_data)

if __name__ == '__main__':
    # Run the Flask app on port 5022
    app.run(port=5022)
