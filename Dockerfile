# =============================================================================
# unoptimised dockerfile
# shrink edilecek
# 
#
# problemler:
#   - Tek asamali build (builder ve runtime ayrimi yok)
#   - Full "python" base image (slim/distroless degil)
#   - gcc, build-essential, git, curl, vim gibi gereksiz derleme/debug araclari
#   - apt-get / pip cache temizlenmiyor
#   - root kullanicisiyla calisiyor
#   - Katman sirasi optimize edilmemis (cache invalidation her degisiklikte)
# =============================================================================

FROM python:3.11

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    vim \
    nano \
    unzip

WORKDIR /app

# tum project
COPY . /app

# requirements kurulumu
RUN pip install --upgrade pip
RUN pip install -r requirements.txt

RUN pip install requests urllib3

EXPOSE 8000

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
