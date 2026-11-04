// Test delle regole Firestore. Si eseguono sull'emulatore, dalla cartella principale del repo:
//   npx firebase-tools emulators:exec --only firestore --project demo-spiaggia "npm --prefix firestore-tests test"
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  Timestamp, collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where,
} from 'firebase/firestore';

let env;

const ts = (iso) => Timestamp.fromDate(new Date(iso));

const validBooking = (extra = {}) => ({
  umbrellaId: 'Mare-1',
  clientName: 'Rossi',
  startDate: ts('2027-07-01T00:00:00Z'),
  endDate: ts('2027-07-05T00:00:00Z'),
  notes: '',
  arrived: false,
  phone: '3331234567',
  price: 100,
  deposit: 20,
  paid: false,
  updatedBy: 'Telefono di mamma',
  ...extra,
});

/** Firestore come il telefono con questo codice (null = non entrato in Firebase). */
const as = (uid) => (uid
  ? env.authenticatedContext(uid, { firebase: { sign_in_provider: 'anonymous' } }).firestore()
  : env.unauthenticatedContext().firestore());

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-spiaggia',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'dispositivi/admin1'), { nome: 'Telefono di Ale', ruolo: 'admin' });
    await setDoc(doc(db, 'dispositivi/staff1'), { nome: 'Telefono di mamma', ruolo: 'staff' });
    await setDoc(doc(db, 'richieste/nuovo1'), { nome: 'Telefono nuovo' });
    await setDoc(doc(db, 'bookings/b1'), validBooking());
    await setDoc(doc(db, 'beachLayout/Mare'), { name: 'Mare', rows: 1, crossAxisCount: 1, umbrellas: [] });
    await setDoc(doc(db, 'meta/schema'), { version: 2 });
  });
});

describe('accesso', () => {
  test('chi non è entrato in Firebase non legge niente', async () => {
    await assertFails(getDoc(doc(as(null), 'bookings/b1')));
    await assertFails(getDoc(doc(as(null), 'beachLayout/Mare')));
  });

  test('un telefono non approvato non legge e non scrive niente', async () => {
    await assertFails(getDoc(doc(as('estraneo'), 'bookings/b1')));
    await assertFails(getDoc(doc(as('estraneo'), 'beachLayout/Mare')));
    await assertFails(setDoc(doc(as('estraneo'), 'bookings/nuova'), validBooking()));
  });

  test('un telefono approvato legge prenotazioni, mappa e schema', async () => {
    const db = as('staff1');
    await assertSucceeds(getDoc(doc(db, 'bookings/b1')));
    await assertSucceeds(getDoc(doc(db, 'beachLayout/Mare')));
    await assertSucceeds(getDoc(doc(db, 'meta/schema')));
  });

  test('un telefono approvato può fare le query usate dall\'app', async () => {
    const db = as('staff1');
    await assertSucceeds(getDocs(query(collection(db, 'bookings'), where('endDate', '>=', ts('2027-01-01T00:00:00Z')))));
    await assertSucceeds(getDocs(query(collection(db, 'bookings'), where('umbrellaId', '==', 'Mare-1'))));
  });

  test('collezioni sconosciute sono chiuse', async () => {
    await assertFails(getDoc(doc(as('admin1'), 'altro/x')));
    await assertFails(setDoc(doc(as('admin1'), 'altro/x'), { a: 1 }));
  });
});

describe('prenotazioni', () => {
  test('crea, modifica ed elimina una prenotazione valida', async () => {
    const db = as('staff1');
    await assertSucceeds(setDoc(doc(db, 'bookings/nuova'), validBooking({ umbrellaId: 'Mare-2' })));
    await assertSucceeds(updateDoc(doc(db, 'bookings/b1'), { arrived: true, updatedBy: 'Telefono di mamma' }));
    await assertSucceeds(deleteDoc(doc(db, 'bookings/b1')));
  });

  test('prezzo nullo è ammesso (non ancora deciso)', async () => {
    await assertSucceeds(setDoc(doc(as('staff1'), 'bookings/p'), validBooking({ price: null })));
  });

  test('rifiuta date al contrario', async () => {
    await assertFails(setDoc(doc(as('staff1'), 'bookings/x'),
      validBooking({ startDate: ts('2027-07-10T00:00:00Z'), endDate: ts('2027-07-01T00:00:00Z') })));
  });

  test('rifiuta campi sconosciuti', async () => {
    await assertFails(setDoc(doc(as('staff1'), 'bookings/x'), validBooking({ ruolo: 'admin' })));
  });

  test('rifiuta campi obbligatori mancanti o vuoti', async () => {
    const { clientName, ...noName } = validBooking();
    await assertFails(setDoc(doc(as('staff1'), 'bookings/x'), noName));
    await assertFails(setDoc(doc(as('staff1'), 'bookings/x'), validBooking({ clientName: '' })));
    await assertFails(setDoc(doc(as('staff1'), 'bookings/x'), validBooking({ umbrellaId: '' })));
  });

  test('rifiuta tipi sbagliati e valori fuori misura', async () => {
    const db = as('staff1');
    await assertFails(setDoc(doc(db, 'bookings/x'), validBooking({ startDate: '2027-07-01' })));
    await assertFails(setDoc(doc(db, 'bookings/x'), validBooking({ price: -10 })));
    await assertFails(setDoc(doc(db, 'bookings/x'), validBooking({ deposit: 'tanti' })));
    await assertFails(setDoc(doc(db, 'bookings/x'), validBooking({ arrived: 'si' })));
    await assertFails(setDoc(doc(db, 'bookings/x'), validBooking({ clientName: 'x'.repeat(101) })));
    await assertFails(setDoc(doc(db, 'bookings/x'), validBooking({ notes: 'n'.repeat(501) })));
  });

  test('una modifica non può rendere invalida la prenotazione', async () => {
    await assertFails(updateDoc(doc(as('staff1'), 'bookings/b1'), { endDate: ts('2027-06-01T00:00:00Z') }));
  });
});

describe('mappa e schema', () => {
  test('solo l\'admin modifica la mappa', async () => {
    const layout = { name: 'Mare', rows: 2, crossAxisCount: 2, umbrellas: [] };
    await assertFails(setDoc(doc(as('staff1'), 'beachLayout/Mare'), layout));
    await assertSucceeds(setDoc(doc(as('admin1'), 'beachLayout/Mare'), layout));
  });

  test('solo l\'admin aggiorna la versione dello schema', async () => {
    await assertFails(setDoc(doc(as('staff1'), 'meta/schema'), { version: 3 }));
    await assertSucceeds(setDoc(doc(as('admin1'), 'meta/schema'), { version: 2 }));
  });
});

describe('telefoni e richieste', () => {
  test('un telefono nuovo può chiedere l\'accesso solo per se stesso', async () => {
    await assertSucceeds(setDoc(doc(as('estraneo'), 'richieste/estraneo'), { nome: 'Telefono di Luca' }));
    await assertFails(setDoc(doc(as('estraneo'), 'richieste/altro'), { nome: 'Finto' }));
    await assertFails(setDoc(doc(as('estraneo'), 'richieste/estraneo'), { nome: 'x', ruolo: 'admin' }));
    await assertFails(setDoc(doc(as('estraneo'), 'richieste/estraneo'), { nome: 'n'.repeat(41) }));
    await assertFails(setDoc(doc(as(null), 'richieste/anonimo'), { nome: 'Senza accesso' }));
  });

  test('un telefono nuovo non può approvarsi da solo', async () => {
    await assertFails(setDoc(doc(as('estraneo'), 'dispositivi/estraneo'), { nome: 'Io', ruolo: 'admin' }));
  });

  test('un telefono vede solo il proprio stato e la propria richiesta', async () => {
    await assertSucceeds(getDoc(doc(as('estraneo'), 'dispositivi/estraneo')));
    await assertSucceeds(getDoc(doc(as('nuovo1'), 'richieste/nuovo1')));
    await assertFails(getDoc(doc(as('estraneo'), 'dispositivi/admin1')));
    await assertFails(getDoc(doc(as('estraneo'), 'richieste/nuovo1')));
    await assertFails(getDocs(collection(as('staff1'), 'richieste')));
  });

  test('l\'admin vede le richieste e approva un telefono', async () => {
    const db = as('admin1');
    await assertSucceeds(getDocs(collection(db, 'richieste')));
    await assertSucceeds(setDoc(doc(db, 'dispositivi/nuovo1'), { nome: 'Telefono nuovo', ruolo: 'staff', approvatoDa: 'Telefono di Ale' }));
    await assertSucceeds(deleteDoc(doc(db, 'richieste/nuovo1')));
    await assertSucceeds(getDoc(doc(as('nuovo1'), 'bookings/b1')));
  });

  test('l\'admin non può dare ruoli inventati', async () => {
    await assertFails(setDoc(doc(as('admin1'), 'dispositivi/nuovo1'), { nome: 'x', ruolo: 'superuser' }));
  });

  test('lo staff non può approvare telefoni', async () => {
    await assertFails(setDoc(doc(as('staff1'), 'dispositivi/nuovo1'), { nome: 'x', ruolo: 'staff' }));
  });

  test('l\'admin toglie l\'accesso agli altri ma non a se stesso', async () => {
    await assertSucceeds(deleteDoc(doc(as('admin1'), 'dispositivi/staff1')));
    await assertFails(getDoc(doc(as('staff1'), 'bookings/b1')));
    await assertFails(deleteDoc(doc(as('admin1'), 'dispositivi/admin1')));
  });
});
