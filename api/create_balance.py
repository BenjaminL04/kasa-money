import mysql.connector
from mysql.connector import Error
from dotenv import load_dotenv
import os

load_dotenv()

try:
    # Establish connection to MySQL
    connection = mysql.connector.connect(
        host=os.getenv('DB_HOST'),
        user=os.getenv('DB_USER'),
        password=os.getenv('DB_PASSWORD'),
        database=os.getenv('DB_NAME')
    )

    if connection.is_connected():
        cursor = connection.cursor()
        
        # Select all phone numbers from users table
        select_query = "SELECT phone_number FROM btckhaya.users"
        cursor.execute(select_query)
        
        # Fetch all phone numbers
        phone_numbers = cursor.fetchall()
        
        # Prepare insert query for zarp_balances
        insert_query = "INSERT INTO btckhaya.zarp_balances (phone_number, balance) VALUES (%s, %s)"
        
        # Insert each phone number with balance 0
        for phone in phone_numbers:
            phone_number = phone[0]  # Extract phone number from tuple
            values = (phone_number, 0.00)
            cursor.execute(insert_query, values)
        
        # Commit the transaction
        connection.commit()
        print(f"Successfully inserted {cursor.rowcount} records into zarp_balances")

except Error as e:
    print(f"Error connecting to MySQL: {e}")

finally:
    # Clean up resources
    if 'connection' in locals() and connection.is_connected():
        cursor.close()
        connection.close()
        print("MySQL connection closed")
