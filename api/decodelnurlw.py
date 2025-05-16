import mysql.connector
import requests
from flask import Flask, request, jsonify
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

def post_read_key_to_api(read_key, code):
    url = f"API_BASE_URL/api/v1/lnurlscan/{code}?api-key={read_key}"
    headers = {
        "X-API-KEY": read_key
    }

    try:
        response = requests.get(url, headers=headers)
        if response.status_code == 200:
            return response.json()  # Return the JSON response from the API
        else:
            return {"error": f"API Request failed with status code: {response.status_code}"}

    except requests.exceptions.RequestException as e:
        return {"error": f"Error making API request: {e}"}

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
            return read_key
        else:
            return None

    except mysql.connector.Error as err:
        return {"error": f"Error: {err}"}

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

def check_creds_for_phone(phone_number):
    read_key = get_read_key_for_phone(phone_number)
    if read_key:
        return post_read_key_to_api(read_key, request.json["code"])
    else:
        return {"error": "Phone number not found."}

def get_phone_number_for_user(email):
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
        query = "SELECT phone_number FROM users WHERE email = %s"
        cursor.execute(query, (email,))

        # Fetch the result
        result = cursor.fetchone()

        # Check if the user with the email exists
        if result:
            phone_number = result[0]
            return check_creds_for_phone(phone_number)
        else:
            return {"error": "User not found."}

    except mysql.connector.Error as err:
        return {"error": f"Error: {err}"}

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

def get_email_for_token(token):
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
        query = "SELECT email FROM tokens WHERE token = %s"
        cursor.execute(query, (token,))

        # Fetch the result
        result = cursor.fetchone()

        # Check if the token exists
        if result:
            email = result[0]
            return get_phone_number_for_user(email)
        else:
            return {"error": "Token not found."}

    except mysql.connector.Error as err:
        return {"error": f"Error: {err}"}

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/decodelnurlw', methods=['POST'])
def decode_lnurlw():
    data = request.json
    if "token" not in data or "code" not in data:
        return jsonify({"error": "Token and code are required."}), 400

    token = data["token"]
    response = get_email_for_token(token)
    
    if "error" in response:
        return jsonify(response), 500

    return jsonify(response)

if __name__ == "__main__":
    app.run(port=5029)
