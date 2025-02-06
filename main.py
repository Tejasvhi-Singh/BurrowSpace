from main import FastAPI, Request
from pydantic import BaseModel
from typing import Dict
import uvicorn

app = FastAPI()

# Store device IPs {device_id: { "ip": "xxx.xxx.xxx.xxx" }}
devices: Dict[str, Dict[str, str]] = {}

class RegisterDevice(BaseModel):
    device_id: str

@app.post("/register")
async def register_device(request: Request, data: RegisterDevice):
    client_ip = request.client.host  # Get real public IP
    devices[data.device_id] = {"ip": client_ip}
    print(f"Registered: {data.device_id} -> {client_ip}")
    return {"message": "Device registered", "ip": client_ip}

@app.get("/lookup/{device_id}")
async def lookup_device(device_id: str):
    if device_id in devices:
        return {"ip": devices[device_id]["ip"]}
    return {"error": "Device not found"}, 404

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5000)