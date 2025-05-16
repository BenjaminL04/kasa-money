from flask import Flask, request, jsonify
import mysql.connector
import requests
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

def search_token_in_db(token, lnurl):
    # MySQL database configuration
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }

    # Connect to the database
    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        # Search for the email in the 'tokens' table
        query = "SELECT email FROM tokens WHERE token = %s"
        cursor.execute(query, (token,))
        result = cursor.fetchone()

        # If result is not None, proceed to search in 'users' table
        if result:
            email = result[0]

            # Search for the phone_number in the 'users' table
            query = "SELECT phone_number FROM users WHERE email = %s"
            cursor.execute(query, (email,))
            phone_number_result = cursor.fetchone()

            # If phone_number_result is not None, proceed to search in 'creds' table
            if phone_number_result:
                phone_number = phone_number_result[0]

                # Search for the read_key in the 'creds' table
                query = "SELECT read_key FROM creds WHERE phone_number = %s"
                cursor.execute(query, (phone_number,))
                read_key_result = cursor.fetchone()

                # If read_key_result is not None, proceed to make the API request
                if read_key_result:
                    read_key = read_key_result[0]

                    # Construct the API request URL
                    api_url = f'API_BASE_URL/api/v1/lnurlscan/{lnurl}?code={lnurl}'

                    # Set up headers with X-API-KEY
                    headers = {
                        'X-API-KEY': read_key
                    }

                    # Make the HTTP GET request
                    response = requests.get(api_url, headers=headers)

                    return response.text
                else:
                    return "read_key not found for the given phone number."
            else:
                return "Phone number not found for the given email."
        else:
            return "Token not found."

    except mysql.connector.Error as err:
        return f"Error: {err}"

    finally:
        # Close the database connection
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/decodelnurl', methods=['POST'])
def decode_lnurl():
    # Get the token and lnurl from the request body
    token = request.json.get('token')
    lnurl = request.json.get('lnurl')

    if not token or not lnurl:
        return jsonify({"error": "Both 'token' and 'lnurl' must be provided in the request body."}), 400

    # Perform the search and make the API request
    result = search_token_in_db(token, lnurl)

    return jsonify({"response": result})

if __name__ == "__main__":
    # Run the Flask app on port 5016
    app.run(port=5016)
