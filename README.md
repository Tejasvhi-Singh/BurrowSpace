# Burrow Space

## Introduction
Burrow Space is a decentralized peer-to-peer (P2P) file storage and sharing application designed to eliminate reliance on traditional cloud storage. It ensures privacy, security, and seamless data transfer across multiple devices.

## Features
- **Secure Peer-to-Peer File Sharing** using WebRTC.
- **Encrypted Transfers** with AES-256 and RSA-4096.
- **Cross-Platform Compatibility** (Windows, macOS, Android, iOS).
- **Real-Time Peer Discovery** via FastAPI backend.
- **Resumable File Transfers** with chunk-based encryption.
- **User Authentication** with Firebase or JWT-based system.

## Tech Stack
### Frontend
- **Flutter (Dart)** for UI and file management.
- **SQLite** for local storage.

### Backend
- **FastAPI (Python)** for peer discovery and registration.
- **In-Memory Storage** (Future PostgreSQL integration planned).

### Networking & Security
- **WebRTC + STUN/TURN** for direct device communication.
- **AES-256 & RSA-4096** for encryption.
- **TLS 1.3** for secure data transmission.

## Setup & Installation
1. **Clone the repository:**
   ```sh
   git clone https://github.com/your-repo/burrow-space.git
   cd burrow-space
   ```
2. **Install dependencies:**
   - **Flutter App:**
     ```sh
     flutter pub get
     ```
   - **Backend (FastAPI):**
     ```sh
     pip install -r requirements.txt
     ```
3. **Run the FastAPI server:**
   ```sh
   uvicorn main:app --host 0.0.0.0 --port 8000
   ```
4. **Run the Flutter application:**
   ```sh
   flutter run
   ```

## API Endpoints
- **Register a Peer:** `POST /register`
- **Lookup Peer IP:** `GET /lookup/{peer_code}`
- **Health Check:** `GET /`

## Contributing
1. Fork the repository.
2. Create a new feature branch.
3. Commit your changes.
4. Push to the branch and open a PR.

## License
MIT License. See `LICENSE` for details.

## Contact
For issues or feature requests, please create an issue in the repository.

---
Enjoy seamless and secure file transfers with Burrow Space!
