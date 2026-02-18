# Database relations and app flow

## Firestore structure

All data is **scoped by logged-in user and current hotel**. Path pattern:

```
users / {userId} / hotels / {hotelId} / <subcollections>
```

- **`userId`** = Firebase Auth UID (the person using the app).
- **`hotelId`** = ID of the currently selected hotel (one hotel per “property”).
- Every read/write uses this pair so data is isolated per user and per hotel.

### Top-level and hotel list

| Path | Description |
|------|-------------|
| `users/{userId}/hotels` | Collection of **hotel documents** (HotelModel). Each doc = one property (name, ownerId, currencyCode, totalRooms). The app user can have multiple hotels and switch between them. |
| `users/{userId}/hotels/{hotelId}` | Single hotel **document** (metadata only). All operational data lives in subcollections under this doc. |

### Subcollections under each hotel

| Subcollection | Model | Description |
|---------------|--------|-------------|
| **clients** | UserModel | Guest/client records: name, phone, email. Document ID = client id used in bookings as `userId`. |
| **bookings** | BookingModel | Reservations: dates, rooms, status, payment, guest snapshot (userId, userName, userPhone, userEmail). |
| **rooms** | RoomModel | Room definitions: name (e.g. "1", "2", "a2"), optional tags. Used for availability and room picker. |
| **services** | ServiceModel | Add-on services (breakfast, spa, etc.). Bookings can reference them via `selectedServices`. |
| **employers** | EmployerModel | Employees: name, phone, role, department. |
| **roles** | — | Simple docs with `name` (e.g. "Receptionist"). Referenced by name from employers. |
| **departments** | — | Simple docs with `name`. Referenced by name from employers. |
| **shifts** | ShiftModel | Shift records; reference employer by `employeeId` (employer document ID). |

There are **no foreign-key constraints** in Firestore. Relations are logical:

- **Booking → client:** `Booking.userId` = document ID in `clients` (same hotel). Booking also stores denormalized `userName`, `userPhone`, `userEmail` for display and resilience.
- **Booking → rooms:** `Booking.selectedRooms` is a list of **room names** (e.g. `["1","2"]`), not room document IDs. Names must match `rooms` docs in that hotel.
- **Shift → employer:** `ShiftModel.employeeId` = document ID in `employers`.

---

## How the app uses this

### 1. App user and current hotel

- User logs in → **Auth UID** = `userId` for all Firestore paths.
- **HotelProvider** keeps the current hotel in memory and in SharedPreferences (`current_hotel_id`, `current_user_id`).
- On launch it loads the hotel doc from `users/{userId}/hotels/{hotelId}`.
- Every screen gets `userId` from **AuthScopeData** and `hotelId` from **HotelProvider** and passes them into **FirebaseService** for all calls.

### 2. Bookings flow

- **Create/update booking (AddBookingPage):**
  1. Resolve **client:** if the user chose an existing client (from search), use that client’s id; otherwise look up by phone in `clients`; if none, create a new doc in `clients` and use its id.
  2. Build **BookingModel** with that client id as `userId`, plus denormalized name/phone/email, dates, rooms, status, payment, services, etc.
  3. **Create:** `_bookingsRef(userId, hotelId).add(booking.toFirestore())`.
  4. **Update:** `_bookingsRef(...).doc(booking.id).update(booking.toFirestore())`.
- **Delete booking:** `_bookingsRef(userId, hotelId).doc(bookingId).delete()`.
- **Read bookings:** One-off `getBookings(...)` or live **streams** `bookingsStream(userId, hotelId, checkInOnOrAfter: date)` so Dashboard, Bookings list, and Clients update when data changes. Streams use a single inequality on `checkIn` to avoid composite indexes.

### 3. Where each screen gets its data

- **Dashboard:** Subscribes to `bookingsStream(userId, hotelId, checkInOnOrAfter: now - 120 days)`. Stats (occupancy, check-ins today, revenue) are computed in-memory from that list.
- **Bookings list:** Same stream with `checkInOnOrAfter: now - 365 days`. Filtering/sorting by status, date, search is in-memory.
- **Calendar:** Uses its own Firestore query (e.g. `checkOut > rangeStart`) for the visible date range; listens to real-time snapshot and updates the grid.
- **Clients:** Subscribes to `bookingsStream(userId, hotelId, checkInOnOrAfter: now - 730 days)`. “Clients” are **derived** by grouping bookings by `userPhone`: one row per phone, with total bookings, total spent, last check-in. The **clients** collection is used when adding/editing a booking (search by phone, create client if new).

### 4. Rooms and availability

- **Rooms** are stored in `rooms` (name + optional tags). Names are used in the calendar and in `Booking.selectedRooms`.
- Availability is **not** stored; it’s computed by overlapping booking dates and `selectedRooms` / `numberOfRooms` when creating or editing a booking.

---

## Summary diagram

```
Firestore:
  users / {authUid}
    hotels / {hotelId}                    ← Hotel doc (name, currency, totalRooms)
      clients / {clientId}                ← Guest records (name, phone, email)
      bookings / {bookingId}              ← userId = client doc id, selectedRooms = room names
      rooms / {roomId}                    ← name ("1", "2", …)
      services / {serviceId}
      employers / {employerId}
      roles / …
      departments / …
      shifts / {shiftId}                   ← employeeId → employers

App flow:
  Login → userId (auth). HotelProvider → hotelId + HotelModel.
  All FirebaseService(userId, hotelId) → reads/writes under users/{userId}/hotels/{hotelId}/...
  Booking create: resolve client (clients collection) → add booking with that userId + snapshot of name/phone/email.
  Dashboard / Bookings / Clients: listen to bookingsStream(...) → UI updates on add/update/delete.
```
