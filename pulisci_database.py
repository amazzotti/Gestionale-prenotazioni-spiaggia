import sqlite3

def pulisci_database():
    conn = sqlite3.connect("ombrelloni.db")
    cursor = conn.cursor()

    # Elimina tutti i dati nella tabella ombrelloni
    cursor.execute("DELETE FROM ombrelloni")
    conn.commit()
    conn.close()
    print("Database ripulito!")

# Chiamata alla funzione per pulire il database
pulisci_database()
