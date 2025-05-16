from flask import Flask, request, jsonify
import mysql.connector
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

def check_email_in_cards(email):
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
        query = "SELECT * FROM cards WHERE email = %s"
        cursor.execute(query, (email,))

        # Check if the email exists in the cards table
        if cursor.fetchone():
            return "exists"
        else:
            return "not"

    except mysql.connector.Error as err:
        return f"Database error: {err}"

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

            # Check if the email exists in the cards table
            return check_email_in_cards(email)
        else:
            return "Token not found."

    except mysql.connector.Error as err:
        return f"Database error: {err}"

    finally:
        # Close the connection
        if connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/cardcheck', methods=['POST'])
def cardcheck():
    data = request.get_json()

    # Check if the 'token' key exists in the JSON data
    if 'token' in data:
        search_token = data['token']

        # Get the result from the script
        result = get_email_for_token(search_token)

        return jsonify({'result': result})
    else:
        return jsonify({'error': 'Token not provided'})

if __name__ == "__main__":
    # Run the Flask app
    app.run(port=5024)
