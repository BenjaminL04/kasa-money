from flask import Flask, request, jsonify
import mysql.connector
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

def check_token_exists(token):
    try:
        db_config = {
            'host': os.getenv('DB_HOST'),
            'user': os.getenv('DB_USER'),
            'password': os.getenv('DB_PASSWORD'),
            'database': os.getenv('DB_NAME')
        }

        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        query = "SELECT COUNT(*) FROM tokens WHERE token = %s"
        cursor.execute(query, (token,))
        result = cursor.fetchone()[0]

        cursor.close()
        connection.close()

        return result > 0

    except Exception as e:
        print(f"Error: {e}")
        return False

@app.route('/check_token', methods=['POST'])
def check_token():
    token_to_check = request.headers.get('token')

    if not token_to_check:
        return jsonify({'error': 'Token not provided in the header'}), 400

    result = check_token_exists(token_to_check)
    
    response_data = {'result': 'true' if result else 'false'}
    return jsonify(response_data)

if __name__ == '__main__':
    app.run(port=5008)
