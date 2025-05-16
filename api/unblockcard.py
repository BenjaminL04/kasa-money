from flask import Flask, request, jsonify
import mysql.connector
from dotenv import load_dotenv
import os

load_dotenv()
API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

def block_card_for_email(email):
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

        # Check if the email exists in the "cards" table
        query_cards = "SELECT * FROM cards WHERE email = %s"
        cursor.execute(query_cards, (email,))
        card_result = cursor.fetchone()

        if card_result:
            # If the email exists in the "cards" table, update the "is_card_blocked" variable to '1'
            query_update_card = "UPDATE cards SET is_card_blocked = '0' WHERE email = %s"
            cursor.execute(query_update_card, (email,))
            connection.commit()
            return True

    except mysql.connector.Error as err:
        print(f"Error: {err}")

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

    return False

def get_email_for_token(token):
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

        # Execute the query to get email for the given token
        query = "SELECT email FROM tokens WHERE token = %s"
        cursor.execute(query, (token,))

        # Fetch the result
        result = cursor.fetchone()

        # Check if the token exists
        if result:
            email = result[0]

            # Check and block the card for the email (if applicable)
            if block_card_for_email(email):
                return True

    except mysql.connector.Error as err:
        print(f"Error: {err}")

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

    return False

@app.route('/unblockcard', methods=['POST'])
def block_card():
    try:
        # Parse the JSON request
        data = request.get_json()
        token = data.get('token')

        if not token:
            return jsonify({"error": "Token not provided"}), 400

        # Check if the token exists and block the card if applicable
        if get_email_for_token(token):
            return jsonify({"status": "unblocked"}), 200
        else:
            return jsonify({"status": "still blocked"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    # Run the Flask app on port 5027
    app.run(port=5027)
