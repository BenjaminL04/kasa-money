from flask import Flask, jsonify
import mysql.connector
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

# MySQL database configuration
db_config = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

# Endpoint to get user data
@app.route('/get_users', methods=['GET'])
def get_users():
    try:
        # Connect to the database
        connection = mysql.connector.connect(**db_config)

        # Create a cursor
        cursor = connection.cursor(dictionary=True)

        # Execute the query to retrieve user data
        query = "SELECT first_name, last_name, phone_number, email FROM users"
        cursor.execute(query)

        # Fetch all the results
        users = cursor.fetchall()

        # Close the cursor and connection
        cursor.close()
        connection.close()

        # Return the user data as JSON
        return jsonify(users)

    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    # Run the Flask app
        app.run(debug=True, ssl_context='adhoc', port=5000)

