from flask import Flask, request, jsonify
import mysql.connector
import requests
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

@app.route('/create_creds', methods=['POST'])
def create_creds():
    try:
        # Get phone_number from the request
        phone_number = request.json.get('phone_number')

        # Log the request body and headers
        print("Request Body:", request.json)

        # Connect to the database
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        # Check if phone_number already exists in the creds table
        query = "SELECT COUNT(*) FROM creds WHERE phone_number = %s"
        cursor.execute(query, (phone_number,))
        result = cursor.fetchone()
        
        if result and result[0] > 0:
            cursor.close()
            connection.close()
            return jsonify({"error": "Phone number already exists."}), 400

        # Proceed with API request if phone number does not exist
        api_url = 'API_BASE_URL/api/v1/wallet'
        api_key = 'ecefc0dfbea747b2a2f3ad682b703b0a'
        headers = {
            'accept': 'application/json',
            'X-API-KEY': api_key,
            'Content-Type': 'application/json'
        }
        payload = {"name": "test"}

        response = requests.post(api_url, headers=headers, json=payload)
        
        # Log the API response
        print("API Response:", response.text)

        # Check if "id" is present in the JSON response
        response_json = response.json()
        if 'id' in response_json:
            # Extract wallet information
            admin_key = response_json.get('adminkey')
            in_key = response_json.get('inkey')
            wallet_id = response_json.get('id')

            # Data to insert
            data_to_insert = {
                'phone_number': phone_number,
                'read_key': in_key,
                'admin_key': admin_key,
                'wallet_id': wallet_id
            }

            # SQL query to insert data into the 'creds' table
            insert_query = """
                INSERT INTO creds (phone_number, read_key, admin_key, wallet_id)
                VALUES (%(phone_number)s, %(read_key)s, %(admin_key)s, %(wallet_id)s)
            """

            # Execute the query with the data
            cursor.execute(insert_query, data_to_insert)

            # Commit the changes to the database
            connection.commit()

            # Close the database connection
            cursor.close()
            connection.close()

            return jsonify({"message": "success"}), 200

        else:
            return jsonify({"message": "Wallet information not found in the API response."}), 500

    except mysql.connector.Error as err:
        return jsonify({"error": str(err)}), 500

    except requests.RequestException as req_err:
        return jsonify({"error": f"API Request Error: {req_err}"}), 500

if __name__ == '__main__':
    app.run(port=5006)
