from flask import Flask, request, jsonify
import mysql.connector
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

# Database configuration
db_config = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

# Endpoint for email check
@app.route('/email_check', methods=['POST'])
def email_check():
    try:
        # Connect to the database
        connection = mysql.connector.connect(**db_config)

        # Create a cursor object
        cursor = connection.cursor()

        # Get email from the POST request
        email_to_check = request.json.get('email')

        # Query to check if the email exists in the 'users' table
        query = "SELECT * FROM users WHERE email = %s"
        cursor.execute(query, (email_to_check,))

        # Fetch the result
        result = cursor.fetchone()

        if result:
            response = {"message": f"exists"}
        else:
            response = {"message": f"does not exist"}

    except mysql.connector.Error as err:
        response = {"error": f"Error: {err}"}

    finally:
        # Close the cursor and connection
        if 'cursor' in locals() and cursor:
            cursor.close()
        if 'connection' in locals() and connection.is_connected():
            connection.close()

    return jsonify(response)

if __name__ == '__main__':
    app.run(port=5004)
