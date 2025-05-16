import base58
import mysql.connector
from solders.keypair import Keypair
import json
from dotenv import load_dotenv
import os

load_dotenv()

# MySQL database configuration
db_config = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

try:
    # Connect to the MySQL database
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor()

    # Select all phone numbers from the users table
    cursor.execute("SELECT phone_number FROM btckhaya.users")
    users = cursor.fetchall()

    # Process each user
    for user in users:
        phone_number = user[0]

        # Generate a new random keypair
        keypair = Keypair()

        # Extract public address
        pubkey = str(keypair.pubkey())

        # Extract secret key as bytes (64 bytes: 32 bytes private key + 32 bytes public key)
        secret_key_bytes = bytes(keypair)

        # Convert secret key to BS58 format
        bs58_private_key = base58.b58encode(secret_key_bytes).decode()

        # Convert secret key to Uint8Array format (list of integers) and store as JSON string
        uint8_array = list(secret_key_bytes)
        uint8_json = json.dumps(uint8_array)

        # Insert into solana_addresses table
        insert_query = """
        INSERT INTO btckhaya.solana_addresses (phone_number, pubkey, BS58, UNIT8)
        VALUES (%s, %s, %s, %s)
        """
        cursor.execute(insert_query, (phone_number, pubkey, bs58_private_key, uint8_json))

    # Commit the transaction
    conn.commit()
    print(f"Successfully generated and stored keypairs for {len(users)} users.")

except mysql.connector.Error as err:
    print(f"Database error: {err}")
except Exception as e:
    print(f"Error: {e}")
finally:
    if cursor:
        cursor.close()
    if conn and conn.is_connected():
        conn.close()
        print("Database connection closed.")
