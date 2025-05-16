import mysql.connector
import requests
from dotenv import load_dotenv
import os

load_dotenv()

def send_request_with_api_key(read_key):
    # API endpoint URL
    api_url = "API_BASE_URL/lnurlp/api/v1/links"

    # Request headers with the X-API-KEY
    headers = {
        "X-API-KEY": read_key,
        "Content-Type": "application/json"
    }

    # Request payload
    payload = {
        "all_wallets": False
    }

    try:
        # Make the HTTP POST request
        response = requests.post(api_url, headers=headers, json=payload)

        # Print the response
        print("API Response:")
        print(response.status_code)
        print(response.text)

    except requests.RequestException as e:
        print(f"Request Error: {e}")

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
            print(f"Phone number exists. Corresponding read key: {read_key}")
            
            # Check if the read key exists and make the API request
            if read_key:
                send_request_with_api_key(read_key)
            else:
                print("Read key not found.")

        else:
            print("Phone number not found.")

    except mysql.connector.Error as err:
        print(f"Database Error: {err}")

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

def check_creds_for_phone(phone_number):
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
        query = "SELECT * FROM creds WHERE phone_number = %s"
        cursor.execute(query, (phone_number,))

        # Check if the phone number exists in the "creds" table
        if cursor.fetchone():
            # Retrieve and print the read key for the phone number
            get_read_key_for_phone(phone_number)
        else:
            print("Phone number not found.")

    except mysql.connector.Error as err:
        print(f"Database Error: {err}")

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

def get_phone_number_for_user(email):
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
        query = "SELECT phone_number FROM users WHERE email = %s"
        cursor.execute(query, (email,))

        # Fetch the result
        result = cursor.fetchone()

        # Check if the user with the email exists
        if result:
            phone_number = result[0]
            print(f"User exists. Corresponding phone number: {phone_number}")
            # Check if the phone number exists in the "creds" table
            check_creds_for_phone(phone_number)
        else:
            print("User not found.")

    except mysql.connector.Error as err:
        print(f"Database Error: {err}")

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

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

        # Execute the query
        query = "SELECT email FROM tokens WHERE token = %s"
        cursor.execute(query, (token,))

        # Fetch the result
        result = cursor.fetchone()

        # Check if the token exists
        if result:
            email = result[0]
            print(f"Token exists. Corresponding email: {email}")
            # Check if the user with the email exists in the "users" table
            get_phone_number_for_user(email)
        else:
            print("Token not found.")

    except mysql.connector.Error as err:
        print(f"Database Error: {err}")

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

API_BASE_URL = os.getenv("API_BASE_URL")
if __name__ == "__main__":
    # Specify the token to search for
    search_token = "16fd9f5ccf8Cb63EcCeEc109D90B153cFDbFCF8734fFA13eEC6c398DC4BeE88c"

    # Get and print the corresponding email, phone number, read key, and make API request
    get_email_for_token(search_token)
