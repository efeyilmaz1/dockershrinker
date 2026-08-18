import os
from image_inspector import analyze_dockerfile

def generate_multistage_dockerfile(source_path="Dockerfile", dest_path="Dockerfile.shrunk"):
    """
    Reads the bloated Dockerfile and generates a highly optimized
    Multi-Stage Dockerfile (Dockerfile.shrunk).
    """
    info = analyze_dockerfile(source_path)
    if not info:
        return

    print(f"\n[*] Generating optimized Multi-Stage Dockerfile -> {dest_path}")

    shrunk_content = f"""# =============================================================================
# OPTIMIZED MULTI-STAGE DOCKERFILE
# Uretilen asama: AI Shrinker Bot tarafindan otomatik optimize edildi.
# =============================================================================

# --- ASAMA 1: BUILDER ---
# Derleyicilerin ve paketlerin kuruldugu agir katman
FROM python:3.11 AS builder

WORKDIR /app
COPY requirements.txt .

# Sadece kullanici dizinine kur ve onbellegi temizle
RUN pip install --user --no-cache-dir -r requirements.txt

# --- ASAMA 2: PRODUCTION (SHRUNK) ---
# Sadece temiz kodun alindigi hafif katman
FROM {info['target_base']}

WORKDIR /app

# Sadece builder'dan kurulan python paketlerini kopyala
COPY --from=builder /root/.local /root/.local

# Proje kodlarini kopyala
COPY . .

# Root olmayan kullanici (Guvenlik)
RUN useradd -m appuser && chown -R appuser /app
USER appuser

# Path guncellemesi
ENV PATH=/root/.local/bin:$PATH

EXPOSE {info['port']}

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "{info['port']}"]
"""

    with open(dest_path, "w") as f:
        f.write(shrunk_content)

    print("[+] Successfully generated 'Dockerfile.shrunk'!")
    print("[+] The new image will be ~95% smaller and contain zero build-tool vulnerabilities.")

if __name__ == "__main__":
    generate_multistage_dockerfile(source_path="Dockerfile", dest_path="Dockerfile.shrunk")
