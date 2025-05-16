from flask import Flask, request, jsonify
import mysql.connector
import requests
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

def make_api_request(read_key, bolt11):
    # API endpoint
    api_url = "API_BASE_URL/api/v1/payments"

    # Set up headers with X-API-KEY
    headers = {
        "X-API-KEY": read_key
    }

    # Set up the request body with 'bolt11'
    payload = {
        'bolt11': bolt11
    }

    try:
        # Make a GET request to the API
        response = requests.get(api_url, headers=headers, params=payload)

        # Parse the JSON response
        api_response = response.json()

        # Check if 'pending' is True or False
        if api_response and 'pending' in api_response[0] and api_response[0]['pending']:
            return "unpaid"
        else:
            return "paid"

    except requests.RequestException as e:
        return f"Error making API request: {e}"

def get_read_key_for_phone(phone_number):
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

        # Execute the query
        query = "SELECT read_key FROM creds WHERE phone_number = %s"
        cursor.execute(query, (phone_number,))

        # Fetch the result
        result = cursor.fetchone()

        # Check if the phone number exists in the "creds" table
        if result:
            read_key = result[0]
            # Return the read key
            return read_key
        else:
            return None

    except mysql.connector.Error as err:
        return f"Error: {err}"

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/checkinvoice', methods=['POST'])
def check_invoice():
    try:
        # Get the JSON data from the request
        data = request.get_json()

        # Check if 'bolt11' and 'token' are present in the request data
        if 'bolt11' not in data or 'token' not in data:
            return jsonify({'error': 'Missing required parameters'}), 400

        # Get the token and bolt11 values from the request data
        search_token = data['token']
        bolt11 = data['bolt11']

        # Database credentials
        db_config = {
            'host': os.getenv('DB_HOST'),
            'user': os.getenv('DB_USER'),
            'password': os.getenv('DB_PASSWORD'),
            'database': os.getenv('DB_NAME')
        }

        # Connect to the database
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        # Execute the query to get the email for the given token
        query = "SELECT email FROM tokens WHERE token = %s"
        cursor.execute(query, (search_token,))
        result = cursor.fetchone()

        # Check if the token exists
        if result:
            email = result[0]

            # Execute the query to get the phone number for the given email
            query = "SELECT phone_number FROM users WHERE email = %s"
            cursor.execute(query, (email,))
            result = cursor.fetchone()

            # Check if the user with the email exists
            if result:
                phone_number = result[0]

                # Get the read key for the phone number
                read_key = get_read_key_for_phone(phone_number)

                if read_key:
                    # Make an API request with the read key and bolt11
                    payment_status = make_api_request(read_key, bolt11)

                    # Return the payment status
                    return jsonify({'status': payment_status})
                else:
                    return jsonify({'error': 'Read key not found for the phone number'}), 400
            else:
                return jsonify({'error': 'User not found for the email'}), 400
        else:
            return jsonify({'error': 'Token not found'}), 400

    except Exception as e:
        return jsonify({'error': f'Internal Server Error: {str(e)}'}), 500

    finally:
        # Close the database connection
        if connection.is_connected():
            cursor.close()
            connection.close()

if __name__ == "__main__":
    # Run the Flask app on port 2021
    app.run(port=2021)
