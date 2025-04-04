import tkinter as tk
from tkinter import ttk, messagebox
import sqlite3
from datetime import datetime

# Creazione del database e tabella se non esistono
def crea_database():
    conn = sqlite3.connect('prenotazioni.db')
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(ombrelloni)")
    columns = [column[1] for column in cursor.fetchall()]
    if "settore" not in columns:
        cursor.execute("DROP TABLE IF EXISTS ombrelloni")
        cursor.execute('''CREATE TABLE ombrelloni (
                            numero INTEGER,
                            settore TEXT,
                            nome TEXT,
                            cognome TEXT,
                            data_inizio TEXT,
                            data_fine TEXT,
                            mese INTEGER,
                            anno INTEGER,
                            PRIMARY KEY (numero, settore, data_inizio, data_fine, mese, anno))''')
    conn.commit()
    conn.close()

# Funzione per aggiungere una prenotazione nel database
def aggiungi_prenotazione(identificatore, settore, nome, cognome, data_inizio, data_fine, mese, anno):
    try:
        conn = sqlite3.connect('prenotazioni.db')
        cursor = conn.cursor()
        # Verifica la sovrapposizione delle date
        cursor.execute('''SELECT * FROM ombrelloni 
                          WHERE numero = ? AND settore = ? AND (
                              (data_inizio <= ? AND data_fine >= ?) OR
                              (data_inizio <= ? AND data_fine >= ?) OR
                              (data_inizio >= ? AND data_fine <= ?)
                          )''', 
                       (identificatore, settore, data_inizio, data_inizio, data_fine, data_fine, data_inizio, data_fine))
        if cursor.fetchone():
            messagebox.showerror("Errore", f"L'ombrellone {identificatore} nel settore {settore} è già prenotato nel periodo selezionato.")
            return
        # Inserisci la nuova prenotazione
        cursor.execute("INSERT INTO ombrelloni (numero, settore, nome, cognome, data_inizio, data_fine, mese, anno) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", 
                       (identificatore, settore, nome, cognome, data_inizio, data_fine, mese, anno))
        conn.commit()
        messagebox.showinfo("Successo", f"Prenotazione per l'ombrellone {identificatore} nel settore {settore} aggiunta con successo.")
    except sqlite3.IntegrityError:
        messagebox.showerror("Errore", f"L'ombrellone {identificatore} nel settore {settore} è già prenotato per il periodo selezionato.")
    except sqlite3.Error as e:
        messagebox.showerror("Errore", f"Errore nel database: {e}")
    finally:
        conn.close()
    aggiorna_mappa()  # Aggiorna la mappa dopo l'aggiunta

# Funzione per cancellare una prenotazione
def cancella_prenotazione(numero, settore, data_inizio, data_fine, mese, anno):
    try:
        conn = sqlite3.connect('prenotazioni.db')
        cursor = conn.cursor()
        cursor.execute("DELETE FROM ombrelloni WHERE numero = ? AND settore = ? AND data_inizio = ? AND data_fine = ? AND mese = ? AND anno = ?", 
                       (numero, settore, data_inizio, data_fine, mese, anno))
        conn.commit()
        messagebox.showinfo("Successo", f"Prenotazione per l'ombrellone {numero} nel settore {settore} cancellata con successo.")
    except sqlite3.Error as e:
        messagebox.showerror("Errore", f"Errore nel database: {e}")
    finally:
        conn.close()
    aggiorna_mappa()  # Aggiorna la mappa dopo la cancellazione

# Funzione per gestire un ombrellone (prenotazione o cancellazione)
def gestisci_ombrellone(numero, settore, stato, identificatore, testo):
    if stato == "green" or stato == "yellow":  # Gli ombrelloni gialli devono essere prenotabili
        prenota_ombrellone(identificatore, settore)  # Passa l'identificatore interno
    elif stato == "red":
        try:
            righe = testo.split("\n")
            periodo = righe[2]  # Il periodo è nella terza riga
            data_inizio, data_fine = periodo.split(" - ")
        except (IndexError, ValueError):
            messagebox.showerror("Errore", "Impossibile estrarre il periodo di prenotazione.")
            return

        mese = mese_iniziale_selezione.get()
        mese_dict = {
            "Gennaio": 1, "Febbraio": 2, "Marzo": 3, "Aprile": 4,
            "Maggio": 5, "Giugno": 6, "Luglio": 7, "Agosto": 8,
            "Settembre": 9, "Ottobre": 10, "Novembre": 11, "Dicembre": 12
        }
        mese_numero = mese_dict[mese]
        anno_corrente = datetime.now().year

        try:
            giorno_inizio, mese_inizio = map(int, data_inizio.split("/"))
            giorno_fine, mese_fine = map(int, data_fine.split("/"))
            data_inizio = f"{anno_corrente}-{mese_inizio:02d}-{giorno_inizio:02d}"
            data_fine = f"{anno_corrente}-{mese_fine:02d}-{giorno_fine:02d}"
        except ValueError:
            messagebox.showerror("Errore", "Formato delle date non valido.")
            return

        risposta = messagebox.askyesno("Conferma", f"Vuoi cancellare la prenotazione per l'ombrellone {numero} nel settore {settore}?")
        if risposta:
            cancella_prenotazione(identificatore, settore, data_inizio, data_fine, mese_numero, anno_corrente)

# Funzione per prenotare un ombrellone
def prenota_ombrellone(identificatore, settore):
    nome = entry_nome.get()
    cognome = entry_cognome.get()
    giorno_inizio = entry_giorno_inizio.get()
    giorno_fine = entry_giorno_fine.get()

    if not nome or not cognome or not giorno_inizio or not giorno_fine:
        messagebox.showerror("Errore", "Compila tutti i campi per prenotare un ombrellone.")
        return

    try:
        giorno_inizio = int(giorno_inizio)
        giorno_fine = int(giorno_fine)
    except ValueError:
        messagebox.showerror("Errore", "Inserisci un valore numerico valido per i giorni.")
        return

    mese_iniziale = mese_iniziale_selezione.get()
    mese_finale = mese_finale_selezione.get()
    mese_dict = {
        "Gennaio": 1, "Febbraio": 2, "Marzo": 3, "Aprile": 4,
        "Maggio": 5, "Giugno": 6, "Luglio": 7, "Agosto": 8,
        "Settembre": 9, "Ottobre": 10, "Novembre": 11, "Dicembre": 12
    }

    anno_corrente = datetime.now().year
    mese_iniziale_numero = mese_dict[mese_iniziale]
    mese_finale_numero = mese_dict[mese_finale]
    data_inizio = f"{anno_corrente}-{mese_iniziale_numero:02d}-{giorno_inizio:02d}"
    data_fine = f"{anno_corrente}-{mese_finale_numero:02d}-{giorno_fine:02d}"

    aggiungi_prenotazione(identificatore, settore, nome, cognome, data_inizio, data_fine, mese_iniziale_numero, anno_corrente)

def aggiorna_mappa():
    for widget in mappa_frame.winfo_children():
        widget.destroy()

    mese_iniziale = mese_iniziale_selezione.get()
    mese_finale = mese_finale_selezione.get()
    settore = settore_selezione.get()
    giorno_inizio = entry_giorno_inizio.get()
    giorno_fine = entry_giorno_fine.get()

    mese_dict = {
        "Gennaio": 1, "Febbraio": 2, "Marzo": 3, "Aprile": 4,
        "Maggio": 5, "Giugno": 6, "Luglio": 7, "Agosto": 8,
        "Settembre": 9, "Ottobre": 10, "Novembre": 11, "Dicembre": 12
    }
    mese_iniziale_numero = mese_dict.get(mese_iniziale, 0)
    mese_finale_numero = mese_dict.get(mese_finale, 0)
    anno_corrente = datetime.now().year

    data_inizio = f"{anno_corrente}-{mese_iniziale_numero:02d}-{int(giorno_inizio):02d}" if giorno_inizio.isdigit() else None
    data_fine = f"{anno_corrente}-{mese_finale_numero:02d}-{int(giorno_fine):02d}" if giorno_fine.isdigit() else None

    conn = sqlite3.connect('prenotazioni.db')
    cursor = conn.cursor()
    if data_inizio and data_fine:
        cursor.execute('''SELECT * FROM ombrelloni 
                          WHERE settore = ? AND (
                              (data_inizio <= ? AND data_fine >= ?) OR
                              (data_inizio <= ? AND data_fine >= ?) OR
                              (data_inizio >= ? AND data_fine <= ?)
                          )''', (settore, data_inizio, data_inizio, data_fine, data_fine, data_inizio, data_fine))
    else:
        cursor.execute("SELECT * FROM ombrelloni WHERE settore = ?", (settore,))
    prenotazioni = cursor.fetchall()
    conn.close()

    if settore == "Mare":
        numero = 1
        for riga in range(7, 0, -1):  # Dalla riga 7 alla riga 1
            for colonna in range(10, 5, -1):  # Da colonna 10 a colonna 6
                crea_bottone_ombrellone(numero, settore, riga, colonna, prenotazioni)
                numero += 1

            tk.Label(mappa_frame, text="", width=2).grid(row=riga, column=5)

            for colonna in range(4, 0, -1):  # Da colonna 4 a colonna 1
                crea_bottone_ombrellone(numero, settore, riga, colonna, prenotazioni)
                numero += 1

    elif settore == "Tende":
        for riga in range(2, 0, -1):  # Dalla riga 2 alla riga 1
            numero = 1  # Riparte da 1 per ogni riga
            # Parte destra: 6 colonne (da 1 a 6)
            for colonna in range(12, 6, -1):  # Da colonna 12 a colonna 7
                crea_bottone_ombrellone(numero, settore, riga, colonna, prenotazioni)
                numero += 1

            tk.Label(mappa_frame, text="", width=2).grid(row=riga, column=6)

            # Parte sinistra: 5 colonne (da 7 a 11)
            for colonna in range(5, 0, -1):  # Da colonna 5 a colonna 1
                crea_bottone_ombrellone(numero, settore, riga, colonna, prenotazioni)
                numero += 1
                
    elif settore == "Dietro":
     numero = 1  # Unico contatore per la numerazione continua
     # Ciclo per 7 righe
     for riga in range(1, 8):  # Dalla riga 1 alla riga 7
         # Parte destra: 5 colonne
         for colonna in range(10, 5, -1):  # Da colonna 10 a colonna 6
             if numero == 61 or numero == 62:  # Salta i numeri 61 e 62
                 numero += 1
                 continue
             # Rinomina il 63 come 61
             numero_visualizzato = numero - 2 if numero > 62 else numero
             crea_bottone_ombrellone(numero_visualizzato, settore, riga, colonna, prenotazioni)
             numero += 1
         # Spazio bianco tra destra e sinistra
         tk.Label(mappa_frame, text="", width=2).grid(row=riga, column=5)
         # Parte sinistra: 4 colonne
         for colonna in range(4, 0, -1):  # Da colonna 4 a colonna 1
             if numero == 61 or numero == 62:  # Salta i numeri 61 e 62
                 numero += 1
                 continue
             # Rinomina il 63 come 61
             numero_visualizzato = numero - 2 if numero > 62 else numero
             crea_bottone_ombrellone(numero_visualizzato, settore, riga, colonna, prenotazioni)
             numero += 1
             

def crea_bottone_ombrellone(numero, settore, riga, colonna, prenotazioni):
    # Imposta un identificatore unico per ogni ombrellone
    identificatore = f"{numero}-{riga}"  # Combina il numero con la riga

    # Imposta il colore di default
    stato = "green"  # Verde per ombrelloni disponibili
    testo_ombrellone = f"{numero}\nDisponibile"
    tooltip_testo = ""

    # Cambia il colore in giallo per i numeri specificati solo nel settore "Dietro"
    if settore == "Dietro" and numero in [51, 52, 53, 42, 43, 44]:
        stato = "yellow"
        tooltip_testo = "Disponibile con restrizioni"

    # Raccogli tutte le prenotazioni per l'ombrellone
    prenotazioni_ombrellone = [
        prenotazione for prenotazione in prenotazioni
        if prenotazione[0] == identificatore and prenotazione[1] == settore
    ]

    if prenotazioni_ombrellone:
        stato = "red"  # Rosso per ombrelloni prenotati
        testo_ombrellone = f"{numero}\nPrenotato"
        tooltip_testo = "Prenotazioni:\n"
        for prenotazione in prenotazioni_ombrellone:
            nome = prenotazione[2]
            cognome = prenotazione[3]
            data_inizio = prenotazione[4]
            data_fine = prenotazione[5]
            tooltip_testo += f"{nome} {cognome}: {data_inizio} - {data_fine}\n"
            # Estrai giorno e mese dalle date
            giorno_inizio, mese_inizio = data_inizio.split("-")[2], data_inizio.split("-")[1]
            giorno_fine, mese_fine = data_fine.split("-")[2], data_fine.split("-")[1]
            periodo = f"{giorno_inizio}/{mese_inizio} - {giorno_fine}/{mese_fine}"

        # Aggiorna il testo del bottone
        testo_ombrellone = f"{numero}\n{nome} {cognome}\n{periodo}"
    # Crea il bottone per l'ombrellone
    bottone_ombrellone = tk.Button(
        mappa_frame,
        text=testo_ombrellone,
        bg=stato,
        width=10,
        height=5,
        command=lambda numero=numero, settore=settore, stato=stato, identificatore=identificatore, testo=testo_ombrellone: gestisci_ombrellone(numero, settore, stato, identificatore, testo)
    )
    bottone_ombrellone.grid(row=riga, column=colonna, padx=5, pady=5)

    # Aggiungi eventi per mostrare e nascondere il tooltip
    if prenotazioni_ombrellone:  # Mostra il popup solo se ci sono prenotazioni
          bottone_ombrellone.bind("<Enter>", lambda event: mostra_popup_prenotazioni(event, prenotazioni_ombrellone))
          bottone_ombrellone.bind("<Leave>", lambda event: chiudi_popup(event))

# Funzione per mostrare un popup con i dettagli delle prenotazioni
def mostra_popup_prenotazioni(event, prenotazioni_ombrellone):
    global popup  # Usa una variabile globale per il popup
    popup = tk.Toplevel()
    popup.wm_overrideredirect(True)  # Rimuove il bordo della finestra

    # Posiziona il popup a destra di tutti gli ombrelloni e sempre dall'alto
    x_offset = mappa_frame.winfo_rootx() + mappa_frame.winfo_width() + 20  # Spazio a destra della mappa
    y_offset = mappa_frame.winfo_rooty()  # Parte sempre dall'alto del frame
    popup.geometry(f"+{x_offset}+{y_offset}")

    # Intestazioni della tabella
    tk.Label(popup, text="Nome", font=("Arial", 10, "bold")).grid(row=0, column=0, padx=5, pady=5)
    tk.Label(popup, text="Cognome", font=("Arial", 10, "bold")).grid(row=0, column=1, padx=5, pady=5)
    tk.Label(popup, text="Inizio", font=("Arial", 10, "bold")).grid(row=0, column=2, padx=5, pady=5)
    tk.Label(popup, text="Fine", font=("Arial", 10, "bold")).grid(row=0, column=3, padx=5, pady=5)

    # Aggiungi le prenotazioni alla tabella
    for i, prenotazione in enumerate(prenotazioni_ombrellone, start=1):
        nome = prenotazione[2]
        cognome = prenotazione[3]
        data_inizio = prenotazione[4]
        data_fine = prenotazione[5]

        # Estrai giorno e mese dalle date
        giorno_inizio, mese_inizio = data_inizio.split("-")[2], data_inizio.split("-")[1]
        giorno_fine, mese_fine = data_fine.split("-")[2], data_fine.split("-")[1]
        data_inizio_formattata = f"{giorno_inizio}-{mese_inizio}"
        data_fine_formattata = f"{giorno_fine}-{mese_fine}"

        # Aggiungi i dati alla tabella
        tk.Label(popup, text=nome).grid(row=i, column=0, padx=5, pady=5)
        tk.Label(popup, text=cognome).grid(row=i, column=1, padx=5, pady=5)
        tk.Label(popup, text=data_inizio_formattata).grid(row=i, column=2, padx=5, pady=5)
        tk.Label(popup, text=data_fine_formattata).grid(row=i, column=3, padx=5, pady=5)


# Funzione per chiudere il popup
def chiudi_popup(event):
    global popup
    if popup:
        popup.destroy()
        popup = None



# Interfaccia grafica
root = tk.Tk()
root.title("Gestione Prenotazioni Ombrelloni")

frame_sinistra = tk.Frame(root)
frame_sinistra.grid(row=0, column=0, padx=10, pady=10, sticky="n")

frame_destra = tk.Frame(root)
frame_destra.grid(row=0, column=1, padx=10, pady=10, sticky="n")

tk.Label(frame_sinistra, text="Nome:").grid(row=0, column=0, sticky="w")
entry_nome = tk.Entry(frame_sinistra)
entry_nome.grid(row=0, column=1)

tk.Label(frame_sinistra, text="Cognome:").grid(row=1, column=0, sticky="w")
entry_cognome = tk.Entry(frame_sinistra)
entry_cognome.grid(row=1, column=1)

tk.Label(frame_sinistra, text="Settore:").grid(row=2, column=0, sticky="w")
settore_selezione = ttk.Combobox(frame_sinistra, values=["Mare", "Tende", "Dietro"])
settore_selezione.grid(row=2, column=1)
settore_selezione.set("Mare")
settore_selezione.bind("<<ComboboxSelected>>", lambda event: aggiorna_mappa())

tk.Label(frame_sinistra, text="Mese Iniziale:").grid(row=3, column=0, sticky="w")
mese_iniziale_selezione = ttk.Combobox(frame_sinistra, values=["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno", "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"])
mese_iniziale_selezione.grid(row=3, column=1)
mese_iniziale_selezione.set("Giugno")

tk.Label(frame_sinistra, text="Mese Finale:").grid(row=4, column=0, sticky="w")
mese_finale_selezione = ttk.Combobox(frame_sinistra, values=["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno", "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"])
mese_finale_selezione.grid(row=4, column=1)
mese_finale_selezione.set("Luglio")

tk.Label(frame_sinistra, text="Giorno Inizio:").grid(row=5, column=0, sticky="w")
entry_giorno_inizio = tk.Entry(frame_sinistra)
entry_giorno_inizio.grid(row=5, column=1)

tk.Label(frame_sinistra, text="Giorno Fine:").grid(row=6, column=0, sticky="w")
entry_giorno_fine = tk.Entry(frame_sinistra)
entry_giorno_fine.grid(row=6, column=1)

tk.Button(frame_sinistra, text="Aggiorna", command=aggiorna_mappa).grid(row=7, column=0, columnspan=2, pady=10)

mappa_frame = tk.Frame(frame_destra)
mappa_frame.grid(row=0, column=0, padx=5, pady=5)

crea_database()
aggiorna_mappa()

entry_nome.focus_set()  # Imposta il focus iniziale sul campo "Nome"

root.mainloop()































#import tkinter as tk
#from tkinter import ttk, messagebox
#import sqlite3
#from datetime import datetime
#
## Creazione del database e tabella se non esistono
#def crea_database():
#    conn = sqlite3.connect('prenotazioni.db')
#    cursor = conn.cursor()
#    cursor.execute("PRAGMA table_info(ombrelloni)")
#    columns = [column[1] for column in cursor.fetchall()]
#    if "settore" not in columns:
#        cursor.execute("DROP TABLE IF EXISTS ombrelloni")
#        cursor.execute('''CREATE TABLE ombrelloni (
#                            numero INTEGER,
#                            settore TEXT,
#                            nome TEXT,
#                            cognome TEXT,
#                            data_inizio TEXT,
#                            data_fine TEXT,
#                            mese INTEGER,
#                            anno INTEGER,
#                            PRIMARY KEY (numero, settore, data_inizio, data_fine, mese, anno))''')
#    conn.commit()
#    conn.close()
#
## Funzione per aggiungere una prenotazione nel database
#def aggiungi_prenotazione(numero, settore, nome, cognome, data_inizio, data_fine, mese, anno):
#    try:
#        conn = sqlite3.connect('prenotazioni.db')
#        cursor = conn.cursor()
#        # Verifica la sovrapposizione delle date
#        cursor.execute('''SELECT * FROM ombrelloni 
#                          WHERE numero = ? AND settore = ? AND (
#                              (data_inizio <= ? AND data_fine >= ?) OR
#                              (data_inizio <= ? AND data_fine >= ?) OR
#                              (data_inizio >= ? AND data_fine <= ?) OR
#                              (data_inizio <= ? AND data_fine >= ?)
#                          )''', 
#                       (numero, settore, data_inizio, data_inizio, data_fine, data_fine, data_inizio, data_fine, data_inizio, data_fine))
#        if cursor.fetchone():
#            messagebox.showerror("Errore", f"L'ombrellone {numero} nel settore {settore} è già prenotato nel periodo selezionato.")
#            return
#        # Inserisci la nuova prenotazione
#        cursor.execute("INSERT INTO ombrelloni (numero, settore, nome, cognome, data_inizio, data_fine, mese, anno) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", 
#                       (numero, settore, nome, cognome, data_inizio, data_fine, mese, anno))
#        conn.commit()
#        messagebox.showinfo("Successo", f"Prenotazione per l'ombrellone {numero} nel settore {settore} aggiunta con successo.")
#    except sqlite3.IntegrityError:
#        messagebox.showerror("Errore", f"L'ombrellone {numero} nel settore {settore} è già prenotato per il periodo selezionato.")
#    except sqlite3.Error as e:
#        messagebox.showerror("Errore", f"Errore nel database: {e}")
#    finally:
#        conn.close()
#    aggiorna_mappa()  # Aggiorna la mappa dopo l'aggiunta
#
## Funzione per cancellare una prenotazione
#def cancella_prenotazione(numero, settore, data_inizio, data_fine, mese, anno):
#    try:
#        conn = sqlite3.connect('prenotazioni.db')
#        cursor = conn.cursor()
#        cursor.execute("DELETE FROM ombrelloni WHERE numero = ? AND settore = ? AND data_inizio = ? AND data_fine = ? AND mese = ? AND anno = ?", 
#                       (numero, settore, data_inizio, data_fine, mese, anno))
#        conn.commit()
#        messagebox.showinfo("Successo", f"Prenotazione per l'ombrellone {numero} nel settore {settore} cancellata con successo.")
#    except sqlite3.Error as e:
#        messagebox.showerror("Errore", f"Errore nel database: {e}")
#    finally:
#        conn.close()
#    aggiorna_mappa()  # Aggiorna la mappa dopo la cancellazione
#
## Funzione per gestire un ombrellone (prenotazione o cancellazione)
#def gestisci_ombrellone(numero, settore, stato, testo):
#    if stato == "green":
#        prenota_ombrellone(numero, settore)  # Passa anche il settore
#    elif stato == "red":
#        try:
#            righe = testo.split("\n")
#            periodo = righe[2]  # Il periodo è nella terza riga
#            data_inizio, data_fine = periodo.split(" - ")
#        except (IndexError, ValueError):
#            messagebox.showerror("Errore", "Impossibile estrarre il periodo di prenotazione.")
#            return
#
#        mese = mese_iniziale_selezione.get()
#        mese_dict = {
#            "Gennaio": 1, "Febbraio": 2, "Marzo": 3, "Aprile": 4,
#            "Maggio": 5, "Giugno": 6, "Luglio": 7, "Agosto": 8,
#            "Settembre": 9, "Ottobre": 10, "Novembre": 11, "Dicembre": 12
#        }
#        mese_numero = mese_dict[mese]
#        anno_corrente = datetime.now().year
#
#        try:
#            giorno_inizio, mese_inizio = map(int, data_inizio.split("/"))
#            giorno_fine, mese_fine = map(int, data_fine.split("/"))
#            data_inizio = f"{anno_corrente}-{mese_inizio:02d}-{giorno_inizio:02d}"
#            data_fine = f"{anno_corrente}-{mese_fine:02d}-{giorno_fine:02d}"
#        except ValueError:
#            messagebox.showerror("Errore", "Formato delle date non valido.")
#            return
#
#        risposta = messagebox.askyesno("Conferma", f"Vuoi cancellare la prenotazione per l'ombrellone {numero} nel settore {settore}?")
#        if risposta:
#            cancella_prenotazione(numero, settore, data_inizio, data_fine, mese_numero, anno_corrente)
#
## Funzione per prenotare un ombrellone
#def prenota_ombrellone(numero, settore):
#    nome = entry_nome.get()
#    cognome = entry_cognome.get()
#    giorno_inizio = entry_giorno_inizio.get()
#    giorno_fine = entry_giorno_fine.get()
#
#    if not nome or not cognome or not giorno_inizio or not giorno_fine:
#        messagebox.showerror("Errore", "Compila tutti i campi per prenotare un ombrellone.")
#        return
#
#    try:
#        giorno_inizio = int(giorno_inizio)
#        giorno_fine = int(giorno_fine)
#    except ValueError:
#        messagebox.showerror("Errore", "Inserisci un valore numerico valido per i giorni.")
#        return
#
#    mese_iniziale = mese_iniziale_selezione.get()
#    mese_finale = mese_finale_selezione.get()
#    mese_dict = {
#        "Gennaio": 1, "Febbraio": 2, "Marzo": 3, "Aprile": 4,
#        "Maggio": 5, "Giugno": 6, "Luglio": 7, "Agosto": 8,
#        "Settembre": 9, "Ottobre": 10, "Novembre": 11, "Dicembre": 12
#    }
#
#    anno_corrente = datetime.now().year
#    mese_iniziale_numero = mese_dict[mese_iniziale]
#    mese_finale_numero = mese_dict[mese_finale]
#    data_inizio = f"{anno_corrente}-{mese_iniziale_numero:02d}-{giorno_inizio:02d}"
#    data_fine = f"{anno_corrente}-{mese_finale_numero:02d}-{giorno_fine:02d}"
#
#    aggiungi_prenotazione(numero, settore, nome, cognome, data_inizio, data_fine, mese_iniziale_numero, anno_corrente)
#
#def aggiorna_mappa():
#    for widget in mappa_frame.winfo_children():
#        widget.destroy()
#
#    mese_iniziale = mese_iniziale_selezione.get()
#    mese_finale = mese_finale_selezione.get()
#    settore = settore_selezione.get()
#    giorno_inizio = entry_giorno_inizio.get()
#    giorno_fine = entry_giorno_fine.get()
#
#    mese_dict = {
#        "Gennaio": 1, "Febbraio": 2, "Marzo": 3, "Aprile": 4,
#        "Maggio": 5, "Giugno": 6, "Luglio": 7, "Agosto": 8,
#        "Settembre": 9, "Ottobre": 10, "Novembre": 11, "Dicembre": 12
#    }
#    mese_iniziale_numero = mese_dict.get(mese_iniziale, 0)
#    mese_finale_numero = mese_dict.get(mese_finale, 0)
#    anno_corrente = datetime.now().year
#
#    data_inizio = f"{anno_corrente}-{mese_iniziale_numero:02d}-{int(giorno_inizio):02d}" if giorno_inizio.isdigit() else None
#    data_fine = f"{anno_corrente}-{mese_finale_numero:02d}-{int(giorno_fine):02d}" if giorno_fine.isdigit() else None
#
#    conn = sqlite3.connect('prenotazioni.db')
#    cursor = conn.cursor()
#    if data_inizio and data_fine:
#        cursor.execute('''SELECT * FROM ombrelloni 
#                          WHERE settore = ? AND (
#                              (data_inizio <= ? AND data_fine >= ?) OR
#                              (data_inizio <= ? AND data_fine >= ?) OR
#                              (data_inizio >= ? AND data_fine <= ?)
#                          )''', (settore, data_inizio, data_inizio, data_fine, data_fine, data_inizio, data_fine))
#    else:
#        cursor.execute("SELECT * FROM ombrelloni WHERE settore = ?", (settore,))
#    prenotazioni = cursor.fetchall()
#    conn.close()
#
#    if settore == "Mare":
#        numero = 1
#        for riga in range(7, 0, -1):  # Dalla riga 7 alla riga 1
#            for colonna in range(10, 5, -1):  # Da colonna 10 a colonna 6
#                crea_bottone_ombrellone(numero, settore, riga, colonna, prenotazioni)
#                numero += 1
#
#            tk.Label(mappa_frame, text="", width=2).grid(row=riga, column=5)
#
#            for colonna in range(4, 0, -1):  # Da colonna 4 a colonna 1
#                crea_bottone_ombrellone(numero, settore, riga, colonna, prenotazioni)
#                numero += 1
#
#    elif settore == "Tende":
#        for riga in range(2, 0, -1):  # Dalla riga 2 alla riga 1
#            numero = 1  # Riparte da 1 per ogni riga
#            # Parte destra: 6 colonne (da 1 a 6)
#            for colonna in range(12, 6, -1):  # Da colonna 12 a colonna 7
#                crea_bottone_ombrellone(numero, settore, riga, colonna, prenotazioni)
#                numero += 1
#    
#            tk.Label(mappa_frame, text="", width=2).grid(row=riga, column=6)
#    
#            # Parte sinistra: 5 colonne (da 7 a 11)
#            for colonna in range(5, 0, -1):  # Da colonna 5 a colonna 1
#                crea_bottone_ombrellone(numero, settore, riga, colonna, prenotazioni)
#                numero += 1
#                
#    elif settore == "Dietro":
#     numero = 1  # Unico contatore per la numerazione continua
#     # Ciclo per 7 righe
#     for riga in range(1, 8):  # Dalla riga 1 alla riga 7
#         # Parte destra: 5 colonne
#         for colonna in range(10, 5, -1):  # Da colonna 10 a colonna 6
#             if numero == 61 or numero == 62:  # Salta i numeri 61 e 62
#                 numero += 1
#                 continue
#             # Rinomina il 63 come 61
#             numero_visualizzato = numero - 2 if numero > 62 else numero
#             crea_bottone_ombrellone(numero_visualizzato, settore, riga, colonna, prenotazioni)
#             numero += 1
#         # Spazio bianco tra destra e sinistra
#         tk.Label(mappa_frame, text="", width=2).grid(row=riga, column=5)
#         # Parte sinistra: 4 colonne
#         for colonna in range(4, 0, -1):  # Da colonna 4 a colonna 1
#             if numero == 61 or numero == 62:  # Salta i numeri 61 e 62
#                 numero += 1
#                 continue
#             # Rinomina il 63 come 61
#             numero_visualizzato = numero - 2 if numero > 62 else numero
#             crea_bottone_ombrellone(numero_visualizzato, settore, riga, colonna, prenotazioni)
#             numero += 1
#
#
## Funzione per creare un bottone per un ombrellone
#def crea_bottone_ombrellone(numero, settore, riga, colonna, prenotazioni):
#    stato = "green"
#    testo_ombrellone = f"{numero}\nDisponibile"
#    tooltip_testo = ""
#
#    for prenotazione in prenotazioni:
#        if prenotazione[0] == numero:
#            stato = "red"
#            nome = prenotazione[2]
#            cognome = prenotazione[3]
#            data_inizio = prenotazione[4]
#            data_fine = prenotazione[5]
#            giorno_inizio = data_inizio[8:10]
#            mese_inizio = data_inizio[5:7]
#            giorno_fine = data_fine[8:10]
#            mese_fine = data_fine[5:7]
#            nome_completo = f"{nome} {cognome}"
#            if len(nome_completo) > 15:
#                nome_completo = nome_completo[:12] + "..."
#            testo_ombrellone = f"{numero}\n{nome_completo}\n{giorno_inizio}/{mese_inizio} - {giorno_fine}/{mese_fine}"
#            tooltip_testo = f"Nome completo: {nome} {cognome}\nPeriodo: {giorno_inizio}/{mese_inizio} - {giorno_fine}/{mese_fine}"
#            break
#
#    bottone_ombrellone = tk.Button(
#        mappa_frame,
#        text=testo_ombrellone,
#        bg=stato,
#        width=10,
#        height=5,
#        command=lambda numero=numero, settore=settore, stato=stato, testo=testo_ombrellone: gestisci_ombrellone(numero, settore, stato, testo)
#    )
#    bottone_ombrellone.grid(row=riga, column=colonna, padx=5, pady=5)
#
#    # Aggiungi eventi per mostrare e nascondere il tooltip
#    if tooltip_testo:  # Mostra il tooltip solo se c'è una prenotazione
#        bottone_ombrellone.bind("<Enter>", lambda event, testo=tooltip_testo: mostra_tooltip(event, testo))
#        bottone_ombrellone.bind("<Leave>", nascondi_tooltip)
#
## Funzione per mostrare un tooltip
#def mostra_tooltip(event, testo):
#    tooltip = tk.Toplevel()
#    tooltip.wm_overrideredirect(True)  # Rimuove il bordo della finestra
#    tooltip.geometry(f"+{event.x_root + 10}+{event.y_root + 10}")  # Posiziona il tooltip vicino al mouse
#    label = tk.Label(tooltip, text=testo, bg="yellow", relief="solid", borderwidth=1, padx=5, pady=2)
#    label.pack()
#    event.widget.tooltip = tooltip  # Salva il riferimento al tooltip nell'oggetto widget
#
## Funzione per nascondere il tooltip
#def nascondi_tooltip(event):
#    if hasattr(event.widget, "tooltip"):
#        event.widget.tooltip.destroy()  # Distrugge il tooltip
#        del event.widget.tooltip  # Rimuove il riferimento al tooltip
#
## Interfaccia grafica
#root = tk.Tk()
#root.title("Gestione Prenotazioni Ombrelloni")
#
#frame_sinistra = tk.Frame(root)
#frame_sinistra.grid(row=0, column=0, padx=10, pady=10, sticky="n")
#
#frame_destra = tk.Frame(root)
#frame_destra.grid(row=0, column=1, padx=10, pady=10, sticky="n")
#
#tk.Label(frame_sinistra, text="Nome:").grid(row=0, column=0, sticky="w")
#entry_nome = tk.Entry(frame_sinistra)
#entry_nome.grid(row=0, column=1)
#
#tk.Label(frame_sinistra, text="Cognome:").grid(row=1, column=0, sticky="w")
#entry_cognome = tk.Entry(frame_sinistra)
#entry_cognome.grid(row=1, column=1)
#
#tk.Label(frame_sinistra, text="Settore:").grid(row=2, column=0, sticky="w")
#settore_selezione = ttk.Combobox(frame_sinistra, values=["Mare", "Tende", "Dietro"])
#settore_selezione.grid(row=2, column=1)
#settore_selezione.set("Mare")
#settore_selezione.bind("<<ComboboxSelected>>", lambda event: aggiorna_mappa())
#
#tk.Label(frame_sinistra, text="Mese Iniziale:").grid(row=3, column=0, sticky="w")
#mese_iniziale_selezione = ttk.Combobox(frame_sinistra, values=["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno", "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"])
#mese_iniziale_selezione.grid(row=3, column=1)
#mese_iniziale_selezione.set("Giugno")
#
#tk.Label(frame_sinistra, text="Mese Finale:").grid(row=4, column=0, sticky="w")
#mese_finale_selezione = ttk.Combobox(frame_sinistra, values=["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno", "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"])
#mese_finale_selezione.grid(row=4, column=1)
#mese_finale_selezione.set("Luglio")
#
#tk.Label(frame_sinistra, text="Giorno Inizio:").grid(row=5, column=0, sticky="w")
#entry_giorno_inizio = tk.Entry(frame_sinistra)
#entry_giorno_inizio.grid(row=5, column=1)
#
#tk.Label(frame_sinistra, text="Giorno Fine:").grid(row=6, column=0, sticky="w")
#entry_giorno_fine = tk.Entry(frame_sinistra)
#entry_giorno_fine.grid(row=6, column=1)
#
#tk.Button(frame_sinistra, text="Aggiorna", command=aggiorna_mappa).grid(row=7, column=0, columnspan=2, pady=10)
#
#mappa_frame = tk.Frame(frame_destra)
#mappa_frame.grid(row=0, column=0, padx=5, pady=5)
#
#crea_database()
#aggiorna_mappa()
#
#entry_nome.focus_set()  # Imposta il focus iniziale sul campo "Nome"
#
#root.mainloop()








































