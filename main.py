"""
Smart Docker Image Shrinker & Vulnerability Trimmer Bot
Örnek Python FastAPI Web Uygulaması

Bu uygulama, projenin "kurban" (victim) servisidir: gerçek bir iş mantığı
taşımaz, tek amacı Multi-Stage Build / Trivy / CI-CD pipeline'ının üzerinde
çalışacağı gerçekçi bir HTTP servisi sağlamaktır.
"""

from datetime import datetime, timezone
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(
    title="Docker Image Shrinker - Demo Service",
    description="Shrinker/Trimmer CI-CD botunun test edeceği örnek servis.",
    version="1.0.0",
)

class HealthResponse(BaseModel):
    status: str
    timestamp: str
    service: str

class EchoRequest(BaseModel):
    message: str

class EchoResponse(BaseModel):
    original_message: str
    length: int
    received_at: str

@app.get("/", response_model=HealthResponse, tags=["health"])
def read_root() -> HealthResponse:
    """Servisin ayakta olup olmadığını kontrol eden kök endpoint."""
    return HealthResponse(
        status="ok",
        timestamp=datetime.now(timezone.utc).isoformat(),
        service="docker-image-shrinker-demo",
    )

@app.get("/healthz", response_model=HealthResponse, tags=["health"])
def healthz() -> HealthResponse:
    """CI/CD pipeline'ının deployment sonrası kullanacağı health-check endpoint'i."""
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(timezone.utc).isoformat(),
        service="docker-image-shrinker-demo",
    )

@app.post("/echo", response_model=EchoResponse, tags=["demo"])
def echo(payload: EchoRequest) -> EchoResponse:
    """Basit bir echo endpoint'i - gerçekçi bir POST isteği senaryosu sunar."""
    return EchoResponse(
        original_message=payload.message,
        length=len(payload.message),
        received_at=datetime.now(timezone.utc).isoformat(),
    )
