from flask import Flask, request, jsonify
import mysql.connector
import requests
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

def get_admin_key_for_matching_phone_number(pin, card_hex):
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

        # Check if the card_hex exists and is not blocked
        card_query = "SELECT * FROM cards WHERE card_hex = %s"
        cursor.execute(card_query, (card_hex,))
        card_row = cursor.fetchone()

        # Check if the card_hex exists
        if card_row:
            is_card_blocked = card_row[4]  # Assuming 'is_card_blocked' is in the fifth column of the cards table

            # Check if the card is not blocked
            if is_card_blocked == 0:
                # Assuming pin is in the fourth column of the cards table
                stored_pin = card_row[3]  # Adjust the index based on your table structure

                # Check if the pin matches
                if stored_pin == pin:
                    # If the PIN matches, get the corresponding 'email' variable
                    email = card_row[1]  # Assuming 'email' is in the second column of the cards table

                    # Search for the email in the 'users' table and get the corresponding 'phone_number'
                    user_query = "SELECT phone_number FROM users WHERE email = %s"
                    cursor.execute(user_query, (email,))
                    phone_number_row = cursor.fetchone()

                    # Check if the email exists in the 'users' table
                    if phone_number_row:
                        phone_number = phone_number_row[0]  # Assuming 'phone_number' is in the first column of the users table

                        # Search for the phone_number in the 'creds' table and get the corresponding 'admin_key'
                        creds_query = "SELECT admin_key FROM creds WHERE phone_number = %s"
                        cursor.execute(creds_query, (phone_number,))
                        admin_key_row = cursor.fetchone()

                        # Check if the phone_number exists in the 'creds' table
                        if admin_key_row:
                            admin_key = admin_key_row[0]  # Assuming 'admin_key' is in the first column of the creds table
                            return admin_key

    except mysql.connector.Error as err:
        print(f"Error: {err}")

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

    return None

def send_payment_request(admin_key, bolt11):
    # Define the API endpoint
    api_url = "API_BASE_URL/api/v1/payments"

    # Define the headers with the admin key
    headers = {
        "X-API-KEY": admin_key,
        "Content-Type": "application/json"
    }

    # Define the payload (body) with the bolt11 variable
    payload = {
        "bolt11": bolt11
    }

    try:
        # Send the POST request
        response = requests.post(api_url, headers=headers, json=payload)
        return response.text

    except requests.exceptions.RequestException as e:
        return f"Error: {e}"

@app.route('/pincheck', methods=['POST'])
def pincheck():
    # Receive data from the user's POST request
    token = request.json.get('token')
    pin = request.json.get('pin')
    card_hex = request.json.get('card_hex')
    bolt11 = request.json.get('bolt11')

    # Check if the token exists in the tokens table
    if not token_exists(token):
        return jsonify({"error": "Invalid token"})

    # Check the PIN and Card Hex, get the Admin Key
    admin_key = get_admin_key_for_matching_phone_number(pin, card_hex)

    if admin_key:
        # Send payment request and return the response
        payment_response = send_payment_request(admin_key, bolt11)
        return jsonify({"response_from_bitcoinkhaya": payment_response})

    return jsonify({"error": "Invalid PIN or Card Hex"})

def token_exists(token):
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
        return cursor.fetchone() is not None

    except mysql.connector.Error as err:
        print(f"Error: {err}")

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

if __name__ == '__main__':
    app.run(port=5023)
