FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    pydicom \
    numpy \
    nibabel \
    scipy \
    dicom2nifti \
    python-gdcm

WORKDIR /app

CMD ["python3", "--version"]
