# Integración de Nextflow con Jobman en EUCAIM

Repositorio asociado al Trabajo Final de Máster sobre la integración de Nextflow con Jobman para ejecutar workflows de procesamiento de imagen médica en el entorno EUCAIM.

La solución utiliza Nextflow para definir y coordinar el workflow, el plugin `nf-jobman` para comunicarse con la API REST de Jobman y Kubernetes como infraestructura final de ejecución.

## Estructura del repositorio

tfm-nextflow-jobman/
- nf-jobman/: código fuente del plugin desarrollado.
- workflow/: versión final del workflow utilizada en las pruebas.
- docker/: Dockerfiles desarrollados durante las pruebas de integración.
- kubernetes/: manifiestos utilizados durante las pruebas iniciales sobre Kubernetes.

## Plugin nf-jobman

El directorio `nf-jobman/` contiene el código fuente del plugin desarrollado para integrar Nextflow con Jobman.

Las cuatro clases principales son:

- `JobmanPlugin`: punto de entrada del plugin.
- `JobmanExtension`: contiene `jobmanSubmit()` y la comunicación con la API REST de Jobman.
- `JobmanFactory`: crea el observador del ciclo de vida del workflow.
- `JobmanObserver`: gestiona los eventos de inicio y finalización del pipeline.

## Workflow final

El directorio `workflow/` contiene la versión final empleada en las pruebas del TFM.

El pipeline ejecuta cinco etapas:

1. Preparación y organización del dataset DICOM.
2. Conversión de DICOM a NIfTI.
3. Segmentación con TotalSegmentator.
4. Conversión de la máscara a DICOM-SEG.
5. Construcción del dataset final de resultados.

Los identificadores internos `PRUEBA31A` a `PRUEBA31E` se conservan porque corresponden a la versión utilizada en las ejecuciones finales presentadas en la memoria.

Algunas rutas son específicas del entorno utilizado durante el desarrollo. La ruta asociada a `prueba22a` se emplea únicamente como mecanismo de fallback para reutilizar una copia previamente almacenada del mismo dataset público cuando la descarga externa no está disponible.

## Dockerfiles

El directorio `docker/` contiene Dockerfiles desarrollados durante las pruebas de integración:

- `dicom2nifti`: entorno Python con herramientas de procesamiento de imagen médica.
- `dcmqi`: adaptación de DCMQI para utilizar `itkimage2segimage`.
- `totalsegmentator`: entorno CPU con TotalSegmentator y sus dependencias.

La ejecución final utilizó las imágenes disponibles en el registro autorizado del entorno EUCAIM.

## Kubernetes

El directorio `kubernetes/` contiene los manifiestos utilizados durante las pruebas iniciales de ejecución directa de Nextflow sobre Kubernetes.

Se incluyen la configuración RBAC, el pod utilizado como runner de Nextflow, el PersistentVolumeClaim empleado para compartir datos y un pod auxiliar de depuración.

En la arquitectura final, los Jobs del workflow no se crean mediante estos manifiestos, sino que Jobman genera dinámicamente los recursos de Kubernetes a partir de las solicitudes enviadas por `nf-jobman`.

## Datos y resultados

Los datos médicos, logs, resultados de ejecución, directorios de trabajo de Nextflow y ficheros temporales no se incluyen en el repositorio.

El caso de uso utiliza datos públicos de la colección NSCLC-Radiomics de The Cancer Imaging Archive (TCIA).
