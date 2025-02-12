from fastapi import FastAPI, Request, HTTPException
from pydantic import BaseModel
from typing import Dict
import uvicorn
from starlette.middleware import Middleware
from starlette.middleware.cors import CORSMiddleware

app = FastAPI(middleware=[
    Middleware(
        CORSMiddleware,
        allow_origins=["*"],  # Allow all origins
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
])

# In-memory storage for registered peers (replace with a database for persistence)
devices: Dict[str, Dict[str, str]] = {}

class RegisterDevice(BaseModel):
    peerCode: str

@app.post("/register")
async def register_device(request: Request, data: RegisterDevice):
    client_ip = request.client.host  # Get sender's public IP
    devices[data.peerCode] = {"ip": client_ip}  # Store peer info

    print(f"Registered: {data.peerCode} -> {client_ip}")
    return {"message": "Device registered", "ip": client_ip}

@app.get("/lookup/{peer_code}")
async def lookup_device(peer_code: str):
    if peer_code in devices:
        return {"ip": devices[peer_code]["ip"]}

    raise HTTPException(status_code=404, detail="Device not found")

@app.get("/")
async def read_root():
    return {"message": "Welcome to BurrowSpace!"}

@app.head("/")
async def read_root_head():
    return {"message": "Welcome to BurrowSpace!"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)