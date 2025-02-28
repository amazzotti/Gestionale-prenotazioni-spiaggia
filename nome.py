import sqlite3

def aggiorna_schema_db():
    conn = sqlite3.connect("ombrelloni.db")
    cursor = conn.cursor()

    try:
        # Aggiungi le colonne "nome" e "cognome" se non esistono
        cursor.execute("ALTER TABLE ombrelloni ADD COLUMN nome TEXT")
        cursor.execute("ALTER TABLE ombrelloni ADD COLUMN cognome TEXT")
        conn.commit()
        print("Schema aggiornato con successo.")
    except sqlite3.OperationalError:
        print("Le colonne 'nome' e 'cognome' esistono già.")
    finally:
        conn.close()

# Esegui questa funzione una sola volta
aggiorna_schema_db()
