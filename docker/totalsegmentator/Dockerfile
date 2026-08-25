FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    libglib2.0-0 \
    libgl1 \
    libgomp1 \
    procps \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --upgrade pip setuptools wheel

RUN python3 -m pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch

RUN python3 -m pip install --no-cache-dir \
    TotalSegmentator \
    nibabel \
    SimpleITK \
    pydicom \
    numpy \
    scipy

WORKDIR /app

CMD ["TotalSegmentator", "--help"]
