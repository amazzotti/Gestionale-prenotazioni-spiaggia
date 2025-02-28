#import tkinter as tk
#from tkinter import ttk
#import sqlite3
#from tkinter import messagebox
#from datetime import datetime, timedelta
#
## Creazione del database e tabella se non esistono
#def crea_database():
#    conn = sqlite3.connect('prenotazioni.db')
#    cursor = conn.cursor()
#    cursor.execute('''
#    CREATE TABLE IF NOT EXISTS ombrelloni (
#        numero INTEGER PRIMARY KEY,
#        nome TEXT,
#        cognome TEXT,
#        data_inizio TEXT,
#        data_fine TEXT
#    )
#    ''')
#    conn.commit()
#    conn.close()
#
## Aggiungi la prenotazione nel database
#def aggiungi_prenotazione(numero, nome, cognome, data_inizio, data_fine):
#    conn = sqlite3.connect('prenotazioni.db')
#    cursor = conn.cursor()
#    cursor.execute("INSERT INTO ombrelloni (numero, nome, cognome, data_inizio, data_fine) VALUES (?, ?, ?, ?, ?)", 
#                   (numero, nome, cognome, data_inizio, data_fine))
#    conn.commit()
#    conn.close()
#
## Controlla se l'ombrellone è disponibile per le date selezionate
#def verifica_disponibilita(numero, data_inizio, data_fine):
#    conn = sqlite3.connect('prenotazioni.db')
#    cursor = conn.cursor()
#    cursor.execute("SELECT * FROM ombrelloni WHERE numero = ? AND ((? BETWEEN data_inizio AND data_fine) OR (? BETWEEN data_inizio AND data_fine))", 
#                   (numero, data_inizio, data_fine))
#    result = cursor.fetchone()
#    conn.close()
#    return result is None
#
## Funzione per visualizzare la mappa aggiornata
#def aggiorna_mappa():
#    for widget in mappa_frame.winfo_children():
#        widget.destroy()
#
#    # Verifica che i campi giorno inizio e fine non siano vuoti
#    try:
#        giorno_inizio = int(entry_giorno_inizio.get()) if entry_giorno_inizio.get() else 1
#        giorno_fine = int(entry_giorno_fine.get()) if entry_giorno_fine.get() else 1
#    except ValueError:
#        messagebox.showerror("Errore", "Inserisci una data valida")
#        return
#
#    mese = mese_selezione.get()
#    mese_dict = {
#        "Gennaio": 1, "Febbraio": 2, "Marzo": 3, "Aprile": 4,
#        "Maggio": 5, "Giugno": 6, "Luglio": 7, "Agosto": 8,
#        "Settembre": 9, "Ottobre": 10, "Novembre": 11, "Dicembre": 12
#    }
#
#    anno_corrente = datetime.now().year
#    data_inizio = f"{anno_corrente}-{mese_dict[mese]:02d}-{giorno_inizio:02d}"
#    data_fine = f"{anno_corrente}-{mese_dict[mese]:02d}-{giorno_fine:02d}"
#
#    conn = sqlite3.connect('prenotazioni.db')
#    cursor = conn.cursor()
#    cursor.execute("SELECT * FROM ombrelloni WHERE (data_inizio BETWEEN ? AND ?) OR (data_fine BETWEEN ? AND ?)", 
#                   (data_inizio, data_fine, data_inizio, data_fine))
#    prenotazioni = cursor.fetchall()
#    conn.close()
#
#    for i in range(1, 26):
#        stato = "green"  # Impostiamo il colore verde di default
#        nome_occupante = ""
#        cognome_occupante = ""
#        data_prenotazione = ""
#
#        for prenotazione in prenotazioni:
#            if prenotazione[0] == i:
#                stato = "red"  # Cambiamo il colore in rosso se prenotato
#                nome_occupante = prenotazione[1]
#                cognome_occupante = prenotazione[2]
#                data_inizio_prenotazione = prenotazione[3]
#                data_fine_prenotazione = prenotazione[4]
#                data_prenotazione = f"{data_inizio_prenotazione[5:10]} - {data_fine_prenotazione[5:10]}"
#                break
#
#        bottone_ombrellone = tk.Button(mappa_frame, text=f"{i}\n{nome_occupante} {cognome_occupante}\n{data_prenotazione}",
#                                       bg=stato, width=10, height=5, command=lambda i=i: prenota_ombrellone(i))
#        bottone_ombrellone.grid(row=(i-1)//5, column=(i-1)%5, padx=5, pady=5)
#
## Funzione per prenotare un ombrellone
#def prenota_ombrellone(numero):
#    nome = entry_nome.get()
#    cognome = entry_cognome.get()
#    giorno_inizio = int(entry_giorno_inizio.get())
#    giorno_fine = int(entry_giorno_fine.get())
#
#    mese = mese_selezione.get()
#
#    mese_dict = {
#        "Gennaio": 1, "Febbraio": 2, "Marzo": 3, "Aprile": 4,
#        "Maggio": 5, "Giugno": 6, "Luglio": 7, "Agosto": 8,
#        "Settembre": 9, "Ottobre": 10, "Novembre": 11, "Dicembre": 12
#    }
#
#    anno_corrente = datetime.now().year
#    data_inizio = f"{anno_corrente}-{mese_dict[mese]:02d}-{giorno_inizio:02d}"
#    data_fine = f"{anno_corrente}-{mese_dict[mese]:02d}-{giorno_fine:02d}"
#
#    if verifica_disponibilita(numero, data_inizio, data_fine):
#        aggiungi_prenotazione(numero, nome, cognome, data_inizio, data_fine)
#        aggiorna_mappa()
#    else:
#        messagebox.showerror("Errore", "L'ombrellone è già prenotato per il periodo selezionato.")
#
## Funzione per fare il refresh della mappa
#def refresh_mappa():
#    aggiorna_mappa()
#
## Interfaccia grafica
#root = tk.Tk()
#root.title("Prenotazione Ombrelloni")
#
## Definizione dei campi di input
#tk.Label(root, text="Nome:").grid(row=0, column=0)
#entry_nome = tk.Entry(root)
#entry_nome.grid(row=0, column=1)
#
#tk.Label(root, text="Cognome:").grid(row=1, column=0)
#entry_cognome = tk.Entry(root)
#entry_cognome.grid(row=1, column=1)
#
#tk.Label(root, text="Mese:").grid(row=2, column=0)
#mese_selezione = ttk.Combobox(root, values=["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno", "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"])
#mese_selezione.grid(row=2, column=1)
#mese_selezione.set("Giugno")
#
#tk.Label(root, text="Giorno Inizio:").grid(row=3, column=0)
#entry_giorno_inizio = tk.Entry(root)
#entry_giorno_inizio.grid(row=3, column=1)
#
#tk.Label(root, text="Giorno Fine:").grid(row=4, column=0)
#entry_giorno_fine = tk.Entry(root)
#entry_giorno_fine.grid(row=4, column=1)
#
## Bottone per aggiornare la mappa
#tk.Button(root, text="Aggiorna", command=aggiorna_mappa).grid(row=5, column=0, columnspan=2, pady=10)
#
## Bottone per fare il refresh
#tk.Button(root, text="Refresh", command=refresh_mappa).grid(row=5, column=2, pady=10)
#
#mappa_frame = tk.Frame(root)
#mappa_frame.grid(row=6, column=0, columnspan=3, padx=5, pady=5)
#
#crea_database()
#aggiorna_mappa()
#
#root.mainloop()


