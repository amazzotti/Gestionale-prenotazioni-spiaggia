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
  updatedBy: 'staff@test.it',
  ...extra,
});

/** Firestore come un utente con questa email (null = non autenticato). */
const as = (email) => (email
  ? env.authenticatedContext(email.replace(/\W/g, '_'), { email }).firestore()
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
    await setDoc(doc(db, 'utenti/admin@test.it'), { ruolo: 'admin' });
    await setDoc(doc(db, 'utenti/staff@test.it'), { ruolo: 'staff' });
    await setDoc(doc(db, 'bookings/b1'), validBooking());
    await setDoc(doc(db, 'beachLayout/Mare'), { name: 'Mare', rows: 1, crossAxisCount: 1, umbrellas: [] });
    await setDoc(doc(db, 'meta/schema'), { version: 2 });
  });
});

describe('accesso', () => {
  test('chi non ha fatto login non legge niente', async () => {
    await assertFails(getDoc(doc(as(null), 'bookings/b1')));
    await assertFails(getDoc(doc(as(null), 'beachLayout/Mare')));
  });

  test('un account non presente in "utenti" non legge niente', async () => {
    await assertFails(getDoc(doc(as('estraneo@test.it'), 'bookings/b1')));
    await assertFails(setDoc(doc(as('estraneo@test.it'), 'bookings/nuova'), validBooking()));
  });

  test('lo staff legge prenotazioni, mappa e schema', async () => {
    const db = as('staff@test.it');
    await assertSucceeds(getDoc(doc(db, 'bookings/b1')));
    await assertSucceeds(getDoc(doc(db, 'beachLayout/Mare')));
    await assertSucceeds(getDoc(doc(db, 'meta/schema')));
  });

  test('l\'email con maiuscole viene riconosciuta', async () => {
    await assertSucceeds(getDoc(doc(as('Staff@Test.it'), 'bookings/b1')));
  });

  test('lo staff può fare le query usate dall\'app', async () => {
    const db = as('staff@test.it');
    await assertSucceeds(getDocs(query(collection(db, 'bookings'), where('endDate', '>=', ts('2027-01-01T00:00:00Z')))));
    await assertSucceeds(getDocs(query(collection(db, 'bookings'), where('umbrellaId', '==', 'Mare-1'))));
  });

  test('collezioni sconosciute sono chiuse', async () => {
    await assertFails(getDoc(doc(as('admin@test.it'), 'altro/x')));
    await assertFails(setDoc(doc(as('admin@test.it'), 'altro/x'), { a: 1 }));
  });
});

describe('prenotazioni', () => {
  test('lo staff crea, modifica ed elimina una prenotazione valida', async () => {
    const db = as('staff@test.it');
    await assertSucceeds(setDoc(doc(db, 'bookings/nuova'), validBooking({ umbrellaId: 'Mare-2' })));
    await assertSucceeds(updateDoc(doc(db, 'bookings/b1'), { arrived: true, updatedBy: 'staff@test.it' }));
    await assertSucceeds(deleteDoc(doc(db, 'bookings/b1')));
  });

  test('prezzo nullo è ammesso (non ancora deciso)', async () => {
    await assertSucceeds(setDoc(doc(as('staff@test.it'), 'bookings/p'), validBooking({ price: null })));
  });

  test('rifiuta date al contrario', async () => {
    await assertFails(setDoc(doc(as('staff@test.it'), 'bookings/x'),
      validBooking({ startDate: ts('2027-07-10T00:00:00Z'), endDate: ts('2027-07-01T00:00:00Z') })));
  });

  test('rifiuta campi sconosciuti', async () => {
    await assertFails(setDoc(doc(as('staff@test.it'), 'bookings/x'), validBooking({ ruolo: 'admin' })));
  });

  test('rifiuta campi obbligatori mancanti o vuoti', async () => {
    const { clientName, ...noName } = validBooking();
    await assertFails(setDoc(doc(as('staff@test.it'), 'bookings/x'), noName));
    await assertFails(setDoc(doc(as('staff@test.it'), 'bookings/x'), validBooking({ clientName: '' })));
    await assertFails(setDoc(doc(as('staff@test.it'), 'bookings/x'), validBooking({ umbrellaId: '' })));
  });

  test('rifiuta tipi sbagliati e valori fuori misura', async () => {
    const db = as('staff@test.it');
    await assertFails(setDoc(doc(db, 'bookings/x'), validBooking({ startDate: '2027-07-01' })));
    await assertFails(setDoc(doc(db, 'bookings/x'), validBooking({ price: -10 })));
    await assertFails(setDoc(doc(db, 'bookings/x'), validBooking({ deposit: 'tanti' })));
    await assertFails(setDoc(doc(db, 'bookings/x'), validBooking({ arrived: 'si' })));
    await assertFails(setDoc(doc(db, 'bookings/x'), validBooking({ clientName: 'x'.repeat(101) })));
    await assertFails(setDoc(doc(db, 'bookings/x'), validBooking({ notes: 'n'.repeat(501) })));
  });

  test('una modifica non può rendere invalida la prenotazione', async () => {
    await assertFails(updateDoc(doc(as('staff@test.it'), 'bookings/b1'), { endDate: ts('2027-06-01T00:00:00Z') }));
  });
});

describe('mappa, schema e utenti', () => {
  test('solo l\'admin modifica la mappa', async () => {
    const layout = { name: 'Mare', rows: 2, crossAxisCount: 2, umbrellas: [] };
    await assertFails(setDoc(doc(as('staff@test.it'), 'beachLayout/Mare'), layout));
    await assertSucceeds(setDoc(doc(as('admin@test.it'), 'beachLayout/Mare'), layout));
  });

  test('solo l\'admin aggiorna la versione dello schema', async () => {
    await assertFails(setDoc(doc(as('staff@test.it'), 'meta/schema'), { version: 3 }));
    await assertSucceeds(setDoc(doc(as('admin@test.it'), 'meta/schema'), { version: 2 }));
  });

  test('ognuno legge solo il proprio ruolo', async () => {
    await assertSucceeds(getDoc(doc(as('staff@test.it'), 'utenti/staff@test.it')));
    await assertFails(getDoc(doc(as('staff@test.it'), 'utenti/admin@test.it')));
  });

  test('nessuno può cambiare i ruoli dall\'app, nemmeno l\'admin', async () => {
    await assertFails(setDoc(doc(as('staff@test.it'), 'utenti/staff@test.it'), { ruolo: 'admin' }));
    await assertFails(setDoc(doc(as('admin@test.it'), 'utenti/nuovo@test.it'), { ruolo: 'staff' }));
  });
});
