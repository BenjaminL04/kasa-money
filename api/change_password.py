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

@app.route('/change_password', methods=['POST'])
def change_password():
    try:
        # Connect to the database
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        # Get email, password, and signature from the request data
        email_to_search = request.json.get('email')
        new_password = request.json.get('password')
        signature = request.json.get('signature')

        # Check if the signature exists and is unused in used_password_signatures table
        cursor.execute("SELECT used FROM used_password_signatures WHERE email = %s AND signature = %s", (email_to_search, signature))
        record = cursor.fetchone()
        
        if not record:
            return jsonify({'message': 'Invalid signature'}), 403
        
        used_status = record[0]
        
        if used_status == 1:
            return jsonify({'message': 'Signature already used'}), 403

        # Search for the user with the given email
        cursor.execute("SELECT * FROM users WHERE email = %s", (email_to_search,))
        user = cursor.fetchone()

        if user:
            # Update the password for the found user
            update_query = "UPDATE users SET password = %s WHERE email = %s"
            cursor.execute(update_query, (new_password, email_to_search))

            # Mark the signature as used
            cursor.execute("UPDATE used_password_signatures SET used = 1 WHERE email = %s AND signature = %s", (email_to_search, signature))
            
            # Commit the changes to the database
            connection.commit()
            response = {'message': 'Password changed successfully'}
        else:
            response = {'message': 'User not found'}
    
    except mysql.connector.Error as err:
        response = {'message': f'Error: {err}'}
    
    finally:
        # Close the cursor and connection
        if 'cursor' in locals() and cursor is not None:
            cursor.close()

        if 'connection' in locals() and connection.is_connected():
            connection.close()

    return jsonify(response)

if __name__ == '__main__':
    app.run(port=5005)
