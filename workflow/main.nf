nextflow.enable.dsl=2

include { jobmanSubmit } from 'plugin/nf-jobman'

workflow {
    println "Pipeline is starting! 🚀"
    println "=== DEMO FINAL 31 - END TO END EUCAIM + NEXTFLOW + JOBMAN ==="

    def runId = new Date().format('yyyyMMddHHmmss')
    def base = "/home/chaimeleon/persistent-home/tfm-demo-final-31/run${runId}"

    /*
     * 31A:
     * Descarga/reutilización de dataset público, generación estructura EUCAIM e index.json.
     */
    def job31a = "tfm-demo-31a-prepare-dataset-${runId}"

    def cmd31a = """
set -euo pipefail

BASE="${base}"
RAW_DIR="\$BASE/00-public-source"
EUCAIM_DATASET="\$BASE/01-eucaim-dataset/nsclc-radiomics-eucaim"
LOG_FILE="\$BASE/prueba31a_prepare_dataset.log"
SUMMARY_FILE="\$BASE/prueba31a_summary.txt"

mkdir -p "\$RAW_DIR" "\$EUCAIM_DATASET"

{
  echo "=== PRUEBA 31A - DESCARGA/REUTILIZACION DATASET + ESTRUCTURA EUCAIM + INDEX.JSON ==="
  echo "HOST=\$(hostname)"
  echo "BASE=\$BASE"
  echo "RAW_DIR=\$RAW_DIR"
  echo "EUCAIM_DATASET=\$EUCAIM_DATASET"
  echo

  echo "=== HERRAMIENTAS ==="
  python3 --version
  echo

  export RAW_DIR
  export EUCAIM_DATASET

  python3 - <<'PY'
import os
import json
import shutil
import urllib.request
import zipfile
from pathlib import Path
from datetime import datetime, timezone

import pydicom

raw_dir = Path(os.environ["RAW_DIR"])
eucaim_dataset = Path(os.environ["EUCAIM_DATASET"])

raw_dir.mkdir(parents=True, exist_ok=True)
eucaim_dataset.mkdir(parents=True, exist_ok=True)

# Serie CT usada en las pruebas previas. El workflow intenta descarga pública NBIA.
# Si la descarga no está disponible en ese momento, reutiliza el dataset público ya descargado en persistent-home.
series_uid_hint = "1.3.6.1.4.1.32722.99.99.320898527671900265039224224949289088459"
nbia_url = f"https://services.cancerimagingarchive.net/nbia-api/services/v1/getImage?SeriesInstanceUID={series_uid_hint}"
zip_path = raw_dir / "nsclc-radiomics-series.zip"
extract_dir = raw_dir / "downloaded-dicom"

download_mode = "unknown"

def count_dicoms(root: Path):
    n = 0
    for f in root.rglob("*"):
        if not f.is_file():
            continue
        try:
            ds = pydicom.dcmread(str(f), stop_before_pixels=True, force=True)
            if getattr(ds, "Modality", None):
                n += 1
        except Exception:
            pass
    return n

# 1) Intento de descarga pública.
try:
    print("PUBLIC_DOWNLOAD_URL=" + nbia_url)
    req = urllib.request.Request(nbia_url, headers={"User-Agent": "tfm-nextflow-jobman-demo"})
    with urllib.request.urlopen(req, timeout=180) as r:
        content = r.read()
    zip_path.write_bytes(content)

    if zip_path.stat().st_size > 1024 * 1024:
        extract_dir.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(extract_dir)
        if count_dicoms(extract_dir) > 0:
            source_root = extract_dir
            download_mode = "public-nbia-download"
        else:
            raise RuntimeError("Downloaded ZIP did not contain readable DICOM files")
    else:
        raise RuntimeError(f"Downloaded file too small: {zip_path.stat().st_size} bytes")
except Exception as e:
    print("PUBLIC_DOWNLOAD_WARNING=" + repr(e))
    print("FALLBACK=using previously downloaded public dataset from persistent-home")

    candidates = sorted(Path("/home/chaimeleon/persistent-home/plugin-jobman/prueba22a").rglob("nsclc-radiomics-eucaim-real-dicom"))
    if not candidates:
        raise SystemExit("No fallback dataset found in persistent-home")

    source_root = candidates[-1]
    download_mode = "fallback-existing-public-dataset"

# 2) Escaneo DICOM y creación de estructura EUCAIM: PatientID / StudyInstanceUID / SeriesInstanceUID.
records = []
for f in sorted(source_root.rglob("*")):
    if not f.is_file():
        continue
    try:
        ds = pydicom.dcmread(str(f), stop_before_pixels=True, force=True)
        modality = str(getattr(ds, "Modality", ""))
        if not modality:
            continue

        patient_id = str(getattr(ds, "PatientID", "UNKNOWN_PATIENT"))
        study_uid = str(getattr(ds, "StudyInstanceUID", "UNKNOWN_STUDY"))
        series_uid = str(getattr(ds, "SeriesInstanceUID", "UNKNOWN_SERIES"))
        sop_uid = str(getattr(ds, "SOPInstanceUID", f.stem))

        target_dir = eucaim_dataset / patient_id / study_uid / series_uid
        target_dir.mkdir(parents=True, exist_ok=True)

        target_file = target_dir / f.name
        if not target_file.exists():
            shutil.copy2(f, target_file)

        records.append({
            "patient_id": patient_id,
            "study_instance_uid": study_uid,
            "series_instance_uid": series_uid,
            "sop_instance_uid": sop_uid,
            "modality": modality,
            "source_file": str(f),
            "target_file": str(target_file)
        })
    except Exception:
        pass

if not records:
    raise SystemExit("No DICOM records found")

# 3) Construcción de index.json estándar de la demo.
patients = {}
for r in records:
    p = patients.setdefault(r["patient_id"], {"patient_id": r["patient_id"], "studies": {}})
    st = p["studies"].setdefault(r["study_instance_uid"], {
        "study_instance_uid": r["study_instance_uid"],
        "series": {}
    })
    se = st["series"].setdefault(r["series_instance_uid"], {
        "series_instance_uid": r["series_instance_uid"],
        "modality": r["modality"],
        "folder": str(Path(r["target_file"]).parent.relative_to(eucaim_dataset)),
        "instances": []
    })
    se["instances"].append({
        "sop_instance_uid": r["sop_instance_uid"],
        "file": str(Path(r["target_file"]).relative_to(eucaim_dataset))
    })

index_patients = []
for p in patients.values():
    studies = []
    for st in p["studies"].values():
        series = []
        for se in st["series"].values():
            se["instances_count"] = len(se["instances"])
            series.append(se)
        st["series"] = series
        st["series_count"] = len(series)
        studies.append(st)
    p["studies"] = studies
    p["studies_count"] = len(studies)
    index_patients.append(p)

index = {
    "dataset_id": "tfm-nsclc-radiomics-eucaim-demo31",
    "dataset_type": "source-dicom",
    "public_source": "NSCLC-Radiomics / The Cancer Imaging Archive",
    "download_mode": download_mode,
    "created_at_utc": datetime.now(timezone.utc).isoformat(),
    "root": str(eucaim_dataset),
    "patients": index_patients,
    "total_dicom_instances": len(records)
}

index_path = eucaim_dataset / "index.json"
index_path.write_text(json.dumps(index, indent=2), encoding="utf-8")

# Resumen plano para logs.
first = records[0]
summary = {
    "PRUEBA31A_STATUS": "SUCCESS",
    "download_mode": download_mode,
    "source_root": str(source_root),
    "eucaim_dataset": str(eucaim_dataset),
    "index_json": str(index_path),
    "patient_id": first["patient_id"],
    "study_instance_uid": first["study_instance_uid"],
    "series_instance_uid": first["series_instance_uid"],
    "total_dicom_instances": len(records)
}

summary_path = eucaim_dataset / "prepare_summary.json"
summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

print("PRUEBA31A_STATUS=SUCCESS")
print("DOWNLOAD_MODE=" + download_mode)
print("SOURCE_ROOT=" + str(source_root))
print("EUCAIM_DATASET=" + str(eucaim_dataset))
print("INDEX_JSON=" + str(index_path))
print("PATIENT_ID=" + first["patient_id"])
print("STUDY_INSTANCE_UID=" + first["study_instance_uid"])
print("SERIES_INSTANCE_UID=" + first["series_instance_uid"])
print("TOTAL_DICOM_INSTANCES=" + str(len(records)))
PY

  {
    echo "PRUEBA31A_STATUS=SUCCESS"
    echo "EUCAIM_DATASET=\$EUCAIM_DATASET"
    echo "INDEX_JSON=\$EUCAIM_DATASET/index.json"
  } > "\$SUMMARY_FILE"

  echo
  echo "=== SUMMARY 31A ==="
  cat "\$SUMMARY_FILE"

  echo
  echo "=== DATASET EUCAIM GENERADO - PRIMEROS FICHEROS ==="
  set +o pipefail
  find "\$EUCAIM_DATASET" -maxdepth 4 -type f | head -20 || true
  set -o pipefail
  echo

} > "\$LOG_FILE" 2>&1
cat "\$LOG_FILE"
exit 0
"""

    def logs31a = jobmanSubmit(
        job31a,
        cmd31a,
        'cpu-medico',
        'library-batch-public/ubuntu-python:latest'
    )

    /*
     * 31B:
     * Conversión DICOM a NIfTI.
     */
    def job31b = "tfm-demo-31b-dicom-to-nifti-${runId}"

    def cmd31b = """
set -euo pipefail

BASE="${base}"
EUCAIM_DATASET="\$BASE/01-eucaim-dataset/nsclc-radiomics-eucaim"
NIFTI_OUT="\$BASE/02-nifti"
LOG_FILE="\$BASE/prueba31b_dicom_to_nifti.log"
SUMMARY_FILE="\$BASE/prueba31b_summary.txt"

mkdir -p "\$NIFTI_OUT"

{
  echo "=== PRUEBA 31B - DICOM A NIFTI ==="
  echo "HOST=\$(hostname)"
  echo "EUCAIM_DATASET=\$EUCAIM_DATASET"
  echo "NIFTI_OUT=\$NIFTI_OUT"
  echo

  python3 --version
  command -v dcm2niix
  dcm2niix -h | head -10 || true
  echo

  if [ ! -s "\$EUCAIM_DATASET/index.json" ]; then
    echo "[ERROR] No existe index.json del dataset EUCAIM"
    exit 1
  fi

  export EUCAIM_DATASET

  DICOM_DIR=\$(python3 - <<'PY'
import os
import json
from pathlib import Path

root = Path(os.environ["EUCAIM_DATASET"])
idx = json.loads((root / "index.json").read_text())

best = None
best_count = -1

for patient in idx["patients"]:
    for study in patient["studies"]:
        for series in study["series"]:
            count = int(series.get("instances_count", 0))
            if series.get("modality") == "CT" and count > best_count:
                best = root / series["folder"]
                best_count = count

if best is None:
    raise SystemExit("No CT series found in index.json")

print(best)
PY
)

  echo "DICOM_DIR=\$DICOM_DIR"

  if [ ! -d "\$DICOM_DIR" ]; then
    echo "[ERROR] No existe DICOM_DIR"
    exit 1
  fi

  DICOM_COUNT=\$(find "\$DICOM_DIR" -type f | wc -l)
  echo "DICOM_COUNT=\$DICOM_COUNT"

  dcm2niix -z y -f ct_lung1_048_demo31 -o "\$NIFTI_OUT" "\$DICOM_DIR"

  NIFTI_FILE=\$(find "\$NIFTI_OUT" -name "*.nii.gz" -type f | sort | tail -1 || true)

  echo "NIFTI_FILE=\$NIFTI_FILE"

  if [ -z "\$NIFTI_FILE" ] || [ ! -s "\$NIFTI_FILE" ]; then
    echo "[ERROR] No se genero NIfTI"
    exit 1
  fi

  export NIFTI_FILE

  python3 - <<'PY'
import os
import nibabel as nib

p = os.environ["NIFTI_FILE"]
img = nib.load(p)

print("NIFTI_READ_OK=true")
print("NIFTI_FILE=" + p)
print("NIFTI_SHAPE=" + str(img.shape))
print("NIFTI_ZOOMS=" + str(img.header.get_zooms()))
print("NIFTI_DTYPE=" + str(img.get_data_dtype()))
PY

  {
    echo "PRUEBA31B_STATUS=SUCCESS"
    echo "DICOM_DIR=\$DICOM_DIR"
    echo "DICOM_COUNT=\$DICOM_COUNT"
    echo "NIFTI_FILE=\$NIFTI_FILE"
  } > "\$SUMMARY_FILE"

  echo "=== SUMMARY 31B ==="
  cat "\$SUMMARY_FILE"

} > "\$LOG_FILE" 2>&1
cat "\$LOG_FILE"
exit 0
"""

    def logs31b = jobmanSubmit(
        job31b,
        cmd31b,
        'cpu-medico',
        'library-batch-public/ubuntu-python:latest'
    )

    /*
     * 31C:
     * Segmentación con TotalSegmentator.
     */
    def job31c = "tfm-demo-31c-totalsegmentator-${runId}"

    def cmd31c = """
set -euo pipefail

BASE="${base}"
NIFTI_OUT="\$BASE/02-nifti"
SEG_OUT="\$BASE/03-segmentation"
HOME_DIR="/home/chaimeleon/persistent-home/tfm-demo-final-31/cache/totalsegmentator-home"
CACHE_DIR="\$BASE/cache"
LOG_FILE="\$BASE/prueba31c_totalsegmentator.log"
SUMMARY_FILE="\$BASE/prueba31c_summary.txt"

mkdir -p "\$SEG_OUT" "\$HOME_DIR" "\$CACHE_DIR" "\$CACHE_DIR/torch" "\$CACHE_DIR/torchinductor" "\$CACHE_DIR/numba"

export HOME="\$HOME_DIR"
export USER="\${PLATFORM_USERNAME:-dsanlag}"
export LOGNAME="\$USER"
export XDG_CACHE_HOME="\$CACHE_DIR"
export TORCH_HOME="\$CACHE_DIR/torch"
export TORCHINDUCTOR_CACHE_DIR="\$CACHE_DIR/torchinductor"
export NUMBA_CACHE_DIR="\$CACHE_DIR/numba"

{
  echo "=== PRUEBA 31C - SEGMENTACION CON TOTALSEGMENTATOR ==="
  echo "HOST=\$(hostname)"
  echo "SEG_OUT=\$SEG_OUT"
  echo "HOME=\$HOME"
  echo

  python3 --version
  command -v TotalSegmentator
  TotalSegmentator --version
  echo

  NIFTI_FILE=\$(find "\$NIFTI_OUT" -name "*.nii.gz" -type f | sort | tail -1 || true)

  echo "NIFTI_FILE=\$NIFTI_FILE"

  if [ -z "\$NIFTI_FILE" ] || [ ! -s "\$NIFTI_FILE" ]; then
    echo "[ERROR] No existe NIfTI de entrada"
    exit 1
  fi

  MASK_FILE="\$SEG_OUT/ct_lung1_048_totalseg_fastest_ml.nii.gz"
  export NIFTI_FILE
  export MASK_FILE

  python3 - <<'PY'
import os
import nibabel as nib

p = os.environ["NIFTI_FILE"]
img = nib.load(p)

print("INPUT_NIFTI_READ_OK=true")
print("INPUT_NIFTI_SHAPE=" + str(img.shape))
print("INPUT_NIFTI_ZOOMS=" + str(img.header.get_zooms()))
print("INPUT_NIFTI_DTYPE=" + str(img.get_data_dtype()))
PY

  echo
  echo "=== EJECUTAR TOTALSEGMENTATOR ==="
  echo "MASK_FILE=\$MASK_FILE"

  TotalSegmentator -i "\$NIFTI_FILE" -o "\$MASK_FILE" --fastest --ml --task total -d cpu

  if [ ! -s "\$MASK_FILE" ]; then
    echo "[ERROR] No se genero mascara"
    exit 1
  fi

  python3 - <<'PY'
import os
import nibabel as nib
import numpy as np

p = os.environ["MASK_FILE"]
img = nib.load(p)
data = np.asanyarray(img.dataobj)
labels = np.unique(data)
nonzero = int(np.count_nonzero(data))

print("MASK_READ_OK=true")
print("MASK_FILE=" + p)
print("MASK_SHAPE=" + str(img.shape))
print("MASK_ZOOMS=" + str(img.header.get_zooms()))
print("MASK_DTYPE=" + str(img.get_data_dtype()))
print("MASK_NONZERO_VOXELS=" + str(nonzero))
print("MASK_UNIQUE_LABELS_COUNT=" + str(len(labels)))
print("MASK_LABELS_NONZERO_COUNT=" + str(len([x for x in labels if int(x) != 0])))

assert nonzero > 0
assert len(labels) > 1
PY

  {
    echo "PRUEBA31C_STATUS=SUCCESS"
    echo "NIFTI_FILE=\$NIFTI_FILE"
    echo "MASK_FILE=\$MASK_FILE"
  } > "\$SUMMARY_FILE"

  echo "=== SUMMARY 31C ==="
  cat "\$SUMMARY_FILE"

} > "\$LOG_FILE" 2>&1
cat "\$LOG_FILE"
exit 0
"""

    def logs31c = jobmanSubmit(
        job31c,
        cmd31c,
        'cpu-medico',
        'library-batch-public/totalsegmentator:2.14.0'
    )

    /*
     * 31D:
     * NIfTI mask a DICOM-SEG.
     */
    def job31d = "tfm-demo-31d-mask-to-dicomseg-${runId}"

    def cmd31d = """
set -euo pipefail

BASE="${base}"
EUCAIM_DATASET="\$BASE/01-eucaim-dataset/nsclc-radiomics-eucaim"
SEG_OUT="\$BASE/03-segmentation"
DICOMSEG_OUT="\$BASE/04-dicom-seg"
LOG_FILE="\$BASE/prueba31d_dicomseg.log"
SUMMARY_FILE="\$BASE/prueba31d_summary.txt"

mkdir -p "\$DICOMSEG_OUT"

{
  echo "=== PRUEBA 31D - NIFTI MASK A DICOM-SEG ==="
  echo "HOST=\$(hostname)"
  echo "DICOMSEG_OUT=\$DICOMSEG_OUT"
  echo

  python3 --version
  command -v itkimage2segimage
  itkimage2segimage --help | head -10 || true
  echo

  MASK_FILE=\$(find "\$SEG_OUT" -name "*.nii.gz" -type f | sort | tail -1 || true)

  if [ -z "\$MASK_FILE" ] || [ ! -s "\$MASK_FILE" ]; then
    echo "[ERROR] No existe mascara NIfTI"
    exit 1
  fi

  export EUCAIM_DATASET

  DICOM_DIR=\$(python3 - <<'PY'
import os
import json
from pathlib import Path

root = Path(os.environ["EUCAIM_DATASET"])
idx = json.loads((root / "index.json").read_text())

best = None
best_count = -1
for patient in idx["patients"]:
    for study in patient["studies"]:
        for series in study["series"]:
            count = int(series.get("instances_count", 0))
            if series.get("modality") == "CT" and count > best_count:
                best = root / series["folder"]
                best_count = count

if best is None:
    raise SystemExit("No CT series found")

print(best)
PY
)

  echo "MASK_FILE=\$MASK_FILE"
  echo "DICOM_DIR=\$DICOM_DIR"

  METADATA_JSON="\$DICOMSEG_OUT/metadata_dcmqi_totalseg.json"
  DICOM_SEG="\$DICOMSEG_OUT/ct_lung1_048_totalseg_dicomseg.dcm"
  CONVERT_LOG="\$DICOMSEG_OUT/itkimage2segimage_convert.log"

  export MASK_FILE
  export METADATA_JSON

  python3 - <<'PY'
import os
import json
from pathlib import Path
import numpy as np
import nibabel as nib

mask_file = os.environ["MASK_FILE"]
metadata_json = Path(os.environ["METADATA_JSON"])

img = nib.load(mask_file)
data = np.asanyarray(img.dataobj)
labels = [int(x) for x in np.unique(data) if int(x) != 0]

if not labels:
    raise SystemExit("Mask has no non-zero labels")

def rgb(label):
    return [int((label * 53) % 256), int((label * 97) % 256), int((label * 193) % 256)]

segments = []
for label in labels:
    segments.append({
        "labelID": label,
        "SegmentDescription": f"TotalSegmentator label {label}",
        "SegmentAlgorithmType": "AUTOMATIC",
        "SegmentAlgorithmName": "TotalSegmentator 2.14.0",
        "SegmentedPropertyCategoryCodeSequence": {
            "CodeValue": "T-D0050",
            "CodingSchemeDesignator": "SRT",
            "CodeMeaning": "Tissue"
        },
        "SegmentedPropertyTypeCodeSequence": {
            "CodeValue": "T-D0050",
            "CodingSchemeDesignator": "SRT",
            "CodeMeaning": "Tissue"
        },
        "AnatomicRegionSequence": {
            "CodeValue": "T-D3000",
            "CodingSchemeDesignator": "SRT",
            "CodeMeaning": "Chest"
        },
        "recommendedDisplayRGBValue": rgb(label)
    })

metadata = {
    "ContentCreatorName": "TFM",
    "ClinicalTrialSeriesID": "TFM-DEMO31",
    "ClinicalTrialTimePointID": "1",
    "SeriesDescription": "TotalSegmentator DICOM SEG",
    "SeriesNumber": "900",
    "InstanceNumber": "1",
    "BodyPartExamined": "CHEST",
    "segmentAttributes": [segments]
}

metadata_json.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

print("METADATA_JSON_CREATED=true")
print("METADATA_JSON=" + str(metadata_json))
print("SEGMENTS_COUNT=" + str(len(segments)))
PY

  itkimage2segimage \\
    --inputImageList "\$MASK_FILE" \\
    --inputDICOMDirectory "\$DICOM_DIR" \\
    --inputMetadata "\$METADATA_JSON" \\
    --outputDICOM "\$DICOM_SEG" \\
    --segmentationType labelmap \\
    --useLabelIDAsSegmentNumber \\
    --noDicomValueChecks \\
    --referencesGeometryCheck 0 \\
    --skip 1 \\
    > "\$CONVERT_LOG" 2>&1

  echo "=== LOG itkimage2segimage TAIL ==="
  tail -20 "\$CONVERT_LOG" || true

  if [ ! -s "\$DICOM_SEG" ]; then
    echo "[ERROR] No se genero DICOM-SEG"
    exit 1
  fi

  export DICOM_SEG

  python3 - <<'PY'
import os
import pydicom

p = os.environ["DICOM_SEG"]
ds = pydicom.dcmread(p, stop_before_pixels=True, force=True)

print("DICOMSEG_READ_OK=true")
print("DICOMSEG_FILE=" + p)
print("SOP_CLASS_UID=" + str(getattr(ds, "SOPClassUID", "")))
print("MODALITY=" + str(getattr(ds, "Modality", "")))
print("NUMBER_OF_FRAMES=" + str(getattr(ds, "NumberOfFrames", "")))
print("SEGMENT_SEQUENCE_COUNT=" + str(len(getattr(ds, "SegmentSequence", []))))

assert str(getattr(ds, "Modality", "")) == "SEG"
assert len(getattr(ds, "SegmentSequence", [])) > 0
PY

  {
    echo "PRUEBA31D_STATUS=SUCCESS"
    echo "MASK_FILE=\$MASK_FILE"
    echo "DICOM_SEG=\$DICOM_SEG"
    echo "METADATA_JSON=\$METADATA_JSON"
  } > "\$SUMMARY_FILE"

  echo "=== SUMMARY 31D ==="
  cat "\$SUMMARY_FILE"

} > "\$LOG_FILE" 2>&1
cat "\$LOG_FILE"
exit 0
"""

    def logs31d = jobmanSubmit(
        job31d,
        cmd31d,
        'cpu-medico',
        'library-batch-public/ubuntu-python:latest'
    )

    /*
     * 31E:
     * Dataset final de resultados.
     */
    def job31e = "tfm-demo-31e-result-dataset-${runId}"

    def cmd31e = """
set -euo pipefail

BASE="${base}"
EUCAIM_DATASET="\$BASE/01-eucaim-dataset/nsclc-radiomics-eucaim"
SEG_OUT="\$BASE/03-segmentation"
DICOMSEG_OUT="\$BASE/04-dicom-seg"
RESULT_DATASET="\$BASE/05-result-dataset/nsclc-radiomics-lung1-048-seg"
LOG_FILE="\$BASE/prueba31e_result_dataset.log"
SUMMARY_FILE="\$BASE/prueba31e_summary.txt"

mkdir -p "\$RESULT_DATASET"

{
  echo "=== PRUEBA 31E - DATASET FINAL DE RESULTADOS ==="
  echo "HOST=\$(hostname)"
  echo "RESULT_DATASET=\$RESULT_DATASET"
  echo

  MASK_FILE=\$(find "\$SEG_OUT" -name "*.nii.gz" -type f | sort | tail -1 || true)
  DICOM_SEG=\$(find "\$DICOMSEG_OUT" -name "*.dcm" -type f | sort | tail -1 || true)
  METADATA_JSON=\$(find "\$DICOMSEG_OUT" -name "metadata_dcmqi_totalseg.json" -type f | sort | tail -1 || true)

  if [ -z "\$MASK_FILE" ] || [ ! -s "\$MASK_FILE" ]; then echo "[ERROR] No mask"; exit 1; fi
  if [ -z "\$DICOM_SEG" ] || [ ! -s "\$DICOM_SEG" ]; then echo "[ERROR] No dicom seg"; exit 1; fi
  if [ -z "\$METADATA_JSON" ] || [ ! -s "\$METADATA_JSON" ]; then echo "[ERROR] No metadata"; exit 1; fi

  export EUCAIM_DATASET
  export RESULT_DATASET
  export MASK_FILE
  export DICOM_SEG
  export METADATA_JSON

  python3 - <<'PY'
import os
import json
import shutil
import hashlib
from pathlib import Path
from datetime import datetime, timezone

import pydicom
import nibabel as nib
import numpy as np

eucaim_dataset = Path(os.environ["EUCAIM_DATASET"])
result_dataset = Path(os.environ["RESULT_DATASET"])
mask_file = Path(os.environ["MASK_FILE"])
dicom_seg = Path(os.environ["DICOM_SEG"])
metadata_json = Path(os.environ["METADATA_JSON"])

result_dataset.mkdir(parents=True, exist_ok=True)

idx = json.loads((eucaim_dataset / "index.json").read_text())

source_patient = idx["patients"][0]
source_study = source_patient["studies"][0]
source_series = source_study["series"][0]

patient_id = source_patient["patient_id"]
study_uid = source_study["study_instance_uid"]
source_series_uid = source_series["series_instance_uid"]

series_folder = result_dataset / f"{source_series_uid}-SEG"
series_folder.mkdir(parents=True, exist_ok=True)

mask_dst = series_folder / mask_file.name
dicom_seg_dst = series_folder / dicom_seg.name
metadata_dst = series_folder / metadata_json.name
source_series_dst = series_folder / "source_series.json"

shutil.copy2(mask_file, mask_dst)
shutil.copy2(dicom_seg, dicom_seg_dst)
shutil.copy2(metadata_json, metadata_dst)

seg_ds = pydicom.dcmread(str(dicom_seg_dst), stop_before_pixels=True, force=True)
mask_img = nib.load(str(mask_dst))
mask_data = np.asanyarray(mask_img.dataobj)
labels = [int(x) for x in np.unique(mask_data) if int(x) != 0]

source_info = {
    "patient_id": patient_id,
    "study_instance_uid": study_uid,
    "source_series_instance_uid": source_series_uid,
    "source_modality": source_series.get("modality"),
    "source_dataset": str(eucaim_dataset),
    "source_index_json": str(eucaim_dataset / "index.json")
}

source_series_dst.write_text(json.dumps(source_info, indent=2), encoding="utf-8")

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

index = {
    "dataset_id": "tfm-nsclc-radiomics-lung1-048-seg-demo31",
    "dataset_type": "segmentation-results",
    "created_at_utc": datetime.now(timezone.utc).isoformat(),
    "pipeline": {
        "orchestrator": "Nextflow",
        "plugin": "nf-jobman",
        "execution_backend": "Jobman + Kubernetes",
        "steps": [
            "public dataset download/reuse",
            "EUCAIM structure generation",
            "source index.json generation",
            "DICOM to NIfTI",
            "TotalSegmentator segmentation",
            "NIfTI mask to DICOM-SEG",
            "result dataset generation"
        ],
        "segmentation_tool": "TotalSegmentator 2.14.0",
        "dicom_seg_tool": "itkimage2segimage / dcmqi"
    },
    "source": source_info,
    "results": [
        {
            "patient_id": patient_id,
            "study_instance_uid": study_uid,
            "source_series_instance_uid": source_series_uid,
            "result_series_instance_uid": str(getattr(seg_ds, "SeriesInstanceUID", "")),
            "dicom_seg_sop_instance_uid": str(getattr(seg_ds, "SOPInstanceUID", "")),
            "folder": series_folder.name,
            "files": {
                "nifti_mask": {
                    "path": str(mask_dst.relative_to(result_dataset)),
                    "size_bytes": mask_dst.stat().st_size,
                    "sha256": sha256(mask_dst),
                    "shape": list(mask_img.shape),
                    "dtype": str(mask_img.get_data_dtype()),
                    "nonzero_voxels": int(np.count_nonzero(mask_data)),
                    "labels_count": len(labels),
                    "labels": labels
                },
                "dicom_seg": {
                    "path": str(dicom_seg_dst.relative_to(result_dataset)),
                    "size_bytes": dicom_seg_dst.stat().st_size,
                    "sha256": sha256(dicom_seg_dst),
                    "sop_class_uid": str(getattr(seg_ds, "SOPClassUID", "")),
                    "modality": str(getattr(seg_ds, "Modality", "")),
                    "number_of_frames": str(getattr(seg_ds, "NumberOfFrames", "")),
                    "segment_sequence_count": len(getattr(seg_ds, "SegmentSequence", []))
                },
                "metadata_json": {
                    "path": str(metadata_dst.relative_to(result_dataset)),
                    "size_bytes": metadata_dst.stat().st_size,
                    "sha256": sha256(metadata_dst)
                },
                "source_series_json": {
                    "path": str(source_series_dst.relative_to(result_dataset)),
                    "size_bytes": source_series_dst.stat().st_size,
                    "sha256": sha256(source_series_dst)
                }
            }
        }
    ]
}

summary = {
    "PRUEBA31E_STATUS": "SUCCESS",
    "result_dataset": str(result_dataset),
    "series_folder": str(series_folder),
    "patient_id": patient_id,
    "study_instance_uid": study_uid,
    "source_series_instance_uid": source_series_uid,
    "mask_shape": list(mask_img.shape),
    "mask_labels_count": len(labels),
    "mask_nonzero_voxels": int(np.count_nonzero(mask_data)),
    "dicom_seg_modality": str(getattr(seg_ds, "Modality", "")),
    "dicom_seg_number_of_frames": str(getattr(seg_ds, "NumberOfFrames", "")),
    "dicom_seg_segment_sequence_count": len(getattr(seg_ds, "SegmentSequence", [])),
    "index_json": str(result_dataset / "index.json"),
    "result_summary_json": str(result_dataset / "result_summary.json")
}

(result_dataset / "index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")
(result_dataset / "result_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

print("RESULT_DATASET_CREATED=true")
print("RESULT_DATASET=" + str(result_dataset))
print("INDEX_JSON=" + str(result_dataset / "index.json"))
print("RESULT_SUMMARY_JSON=" + str(result_dataset / "result_summary.json"))
print("PATIENT_ID=" + patient_id)
print("MASK_LABELS_COUNT=" + str(len(labels)))
print("DICOM_SEG_MODALITY=" + str(getattr(seg_ds, "Modality", "")))
print("DICOM_SEG_NUMBER_OF_FRAMES=" + str(getattr(seg_ds, "NumberOfFrames", "")))
print("DICOM_SEG_SEGMENT_SEQUENCE_COUNT=" + str(len(getattr(seg_ds, "SegmentSequence", []))))
PY

  echo
  echo "=== FICHEROS DATASET FINAL ==="
  find "\$RESULT_DATASET" -type f -print -exec ls -lh {} \\;

  echo
  echo "=== RESULT SUMMARY ==="
  cat "\$RESULT_DATASET/result_summary.json"

  {
    echo "PRUEBA31_STATUS=SUCCESS"
    echo "BASE=\$BASE"
    echo "RESULT_DATASET=\$RESULT_DATASET"
    echo "INDEX_JSON=\$RESULT_DATASET/index.json"
    echo "RESULT_SUMMARY_JSON=\$RESULT_DATASET/result_summary.json"
  } > "\$SUMMARY_FILE"

  echo "=== SUMMARY 31E ==="
  cat "\$SUMMARY_FILE"

} > "\$LOG_FILE" 2>&1
cat "\$LOG_FILE"
exit 0
"""

    def logs31e = jobmanSubmit(
        job31e,
        cmd31e,
        'cpu-medico',
        'library-batch-public/ubuntu-python:latest'
    )

    Channel
        .of(
            "=== 31A LOGS ===\n${logs31a}",
            "=== 31B LOGS ===\n${logs31b}",
            "=== 31C LOGS ===\n${logs31c}",
            "=== 31D LOGS ===\n${logs31d}",
            "=== 31E LOGS ===\n${logs31e}"
        )
        .view { value -> value }
}
