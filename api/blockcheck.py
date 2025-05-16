from flask import Flask, request, jsonify
import mysql.connector
from dotenv import load_dotenv
import os

load_dotenv()
API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

def get_card_status_for_email(email):
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

        # Execute query to get card information based on email
        card_query = "SELECT is_card_blocked FROM cards WHERE email = %s"
        cursor.execute(card_query, (email,))
        card_result = cursor.fetchone()

        # Check if card information exists
        if card_result:
            is_card_blocked = card_result[0]

            # Return card status based on the value of is_card_blocked
            if is_card_blocked == 1:
                return {"status": "blocked"}
            elif is_card_blocked == 0:
                return {"status": "unblocked"}
            else:
                return {"status": "invalid card status"}

        else:
            return {"status": "card information not found"}

    except mysql.connector.Error as err:
        return {"status": f"error: {err}"}

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/blockcheck', methods=['POST'])
def block_check():
    # Get JSON data from the request
    request_data = request.get_json()

    # Check if the 'token' variable is present in the JSON data
    if 'token' in request_data:
        token = request_data['token']

        # Get email based on token
        email = get_email_for_token(token)

        if email:
            # Check card status based on email
            card_status = get_card_status_for_email(email)
            return jsonify(card_status)

        else:
            return jsonify({"status": "token not found"})

    else:
        return jsonify({"status": "token not provided"})

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

        # Execute query to get email based on token
        token_query = "SELECT email FROM tokens WHERE token = %s"
        cursor.execute(token_query, (token,))
        token_result = cursor.fetchone()

        # Check if the token exists
        if token_result:
            return token_result[0]
        else:
            return None

    except mysql.connector.Error as err:
        return None

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

if __name__ == '__main__':
    # Run the Flask app
    app.run(port=5025)
