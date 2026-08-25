FROM qiicr/dcmqi:latest

ENV DEBIAN_FRONTEND=noninteractive

# Validar que itkimage2segimage existe dentro de la imagen base.
# Si existe pero no está en PATH, se crea un enlace en /usr/local/bin.
RUN set -eux; \
    ITK_BIN="$(command -v itkimage2segimage || find / -type f -name itkimage2segimage 2>/dev/null | head -1)"; \
    test -n "$ITK_BIN"; \
    ln -sf "$ITK_BIN" /usr/local/bin/itkimage2segimage; \
    /usr/local/bin/itkimage2segimage --help >/tmp/itkimage2segimage_help.txt || true

# Quitamos el entrypoint propio de qiicr/dcmqi para poder usar sh/bash
# normalmente desde Docker, Kubernetes y Nextflow.
ENTRYPOINT []

WORKDIR /data

CMD ["itkimage2segimage", "--help"]
