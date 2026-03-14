# FFmpeg Master CLI

Herramienta CLI multiplataforma para codificación de medios multimedia con FFmpeg, con detección automática de hardware y soporte para aceleración por hardware (GPU).

## Características

- **Detección automática de hardware**: Identifica CPU, GPU y capacidades de FFmpeg disponibles
- **Aceleración por hardware**: Soporte para VAAPI, NVENC, QSV, AMF, VideoToolbox y Vulkan
- **Codificación optimizada**: Configuraciones predefinidas para diferentes codecs de video
- **Interfaz intuitiva**: Tablas visuales con información del sistema y barra de progreso en tiempo real
- **Validación robusta**: Verifica compatibilidad de codecs, preset y parámetros antes de codificar

## Requisitos

- Python 3.14+
- FFmpeg y FFprobe instalados en el sistema
- (Opcional) Drivers GPU actualizados con soporte para aceleración por hardware

## Instalación

```bash
# Clonar el repositorio
cd ffmpeg_master

# Instalar y crear entorno virtual con uv
uv sync

# Activar entorno virtual
source .venv/bin/activate  # Linux/macOS
# .venv\Scripts\activate   # Windows

# Ejecutar la herramienta
python main.py info
python main.py encode input.mp4 output.mp4
```

## Desarrollo

Este proyecto usa las siguientes herramientas de desarrollo:

- **UV**: Gestor de paquetes y entornos virtuales (usa `uv sync` para instalar dependencias)
- **Python 3.14**: Versión mínima requerida
- **Ruff**: Linter y formateador de código (configurado en `pyproject.toml`)
- **Ty**: LSP para soporte de type hints en el editor

```bash
# Instalar herramientas de desarrollo
uv tool install ruff
uv tool install ty

# Ejecutar linter
ruff check .

# Formatear código
ruff format .

# Verificar types con ty
ty check main.py
```

## Comandos

### info

Detecta y muestra información del hardware del sistema y las capacidades de FFmpeg.

```bash
python main.py info
```

Muestra:
- Información del CPU (modelo, núcleos, hilos, arquitectura)
- GPUs detectadas (nombre y proveedor)
- Capacidades de FFmpeg (hwaccels disponibles y encoders de hardware)

### encode

Codifica un archivo multimedia con configuraciones optimizadas.

```bash
python main.py encode <input_file> <output_file> [options]
```

## Opciones

### Opciones de codificación

| Opción | Alias | Descripción | Valor por defecto |
|--------|-------|-------------|-------------------|
| `--codec` | `-c` | Codec de video (h264, hevc, h264_vaapi, hevc_qsv, libx264, etc.) | h264 |
| `--acodec` | `-a` | Codec de audio (aac, copy, etc.) | aac |
| `--crf` | - | Factor de tasa constante (menor = mejor calidad) | - |
| `--bitrate` | `-b` | Bitrate objetivo (ej: 5M, 2500k). No compatible con --crf | - |
| `--preset` | `-p` | Preset de codificación: veryfast, fast, medium, slow | veryfast |

### Opciones de aceleración por hardware

| Opción | Descripción |
|--------|-------------|
| `--hwaccel` | Aceleración por hardware: vaapi, qsv, nvenc, cuda, videotoolbox, vulkan. Use "auto" para detección automática |

### Opciones avanzadas (requieren --hwaccel vaapi)

| Opción | Descripción |
|--------|-------------|
| `--upscale` | Factor de escalado: 2, 4 u 8 |
| `--smooth-fps` | FPS objetivo para suavizado (1-240) |

## Ejemplos de uso

### Codificación básica H.264

```bash
python main.py encode input.mp4 output.mp4
```

### Codificación H.265 con CRF

```bash
python main.py encode input.mp4 output.mp4 --codec hevc --crf 24
```

### Codificación con bitrate específico

```bash
python main.py encode input.mp4 output.mp4 --bitrate 5M
```

### Usar aceleración por hardware (VAAPI)

```bash
python main.py encode input.mp4 output.mp4 --hwaccel vaapi --codec h264_vaapi
```

### Detección automática de aceleración

```bash
python main.py encode input.mp4 output.mp4 --hwaccel auto
```

### Upscaling 4K con VAAPI

```bash
python main.py encode input.mp4 output.mp4 --hwaccel vaapi --upscale 2 --smooth-fps 60
```

### Codificación en NVIDIA (NVENC)

```bash
python main.py encode input.mp4 output.mp4 --hwaccel nvenc --codec h264_nvenc
```

### Usar preset rápido

```bash
python main.py encode input.mp4 output.mp4 --preset fast --crf 20
```

## Tabla de compatibilidad de aceleración por hardware

| GPU Vendor | Linux | Windows | macOS |
|------------|-------|---------|-------|
| NVIDIA | vaapi, cuda, nvenc | cuda, nvenc, d3d11va | - |
| Intel | vaapi, qsv | qsv | - |
| AMD | vaapi | amf, d3d11va | - |
| Apple Silicon | - | - | videotoolbox |

## Valores de CRF por codec

| Codec | Rango | Valor recomendado |
|-------|-------|-------------------|
| H.264 (x264) | 0-51 | 23 |
| H.265 (x265) | 0-51 | 28 |
| VP9 | 0-63 | 31 |
| AV1 | 0-63 | 30 |
| NVENC | 0-51 | 23 |
| QSV | 0-51 | 28 |
| VAAPI | 0-52 | 28 |

## Señales de parada

La herramienta maneja correctamente las señales SIGINT y SIGTERM, permitiendo detener la codificación de forma segura (finaliza el frame actual antes de salir).

## Notas

- Para usar VAAPI en Linux, asegúrate de tener drivers Intel o AMD instalados y configurados
- NVIDIA NVENC requiere drivers propietarios de NVIDIA
- Vulkan encoding no es soportado en GPUs NVIDIA (usa nvenc en su lugar). El soporte Vulkan es incompleto y no está correctamente probado.
- Las opciones `--upscale` y `--smooth-fps` requieren el filtro `scale_vaapi` en FFmpeg. Sin soporte Vulkan, cosas como FSR no funcionan, aún en desarrollo. 

## Licencia

MIT
