import json
import logging
import platform
import re
import subprocess

import psutil


class HardwareManager:
    def __init__(self):
        self.os = platform.system().lower()
        self.cpu_info = self._get_cpu_info()
        self.gpu_info = self._get_gpu_info()
        self.ffmpeg_caps = self._get_ffmpeg_caps()

    def _get_cpu_info(self) -> dict:
        model = platform.processor()
        try:
            if self.os == "linux":
                # Robust detection for Linux brand name
                result = subprocess.run(
                    ["grep", "-m1", "model name", "/proc/cpuinfo"],
                    capture_output=True,
                    text=True,
                )
                if result.stdout:
                    model = result.stdout.split(":", 1)[1].strip()
            elif self.os == "windows":
                result = subprocess.run(
                    ["wmic", "cpu", "get", "name"], capture_output=True, text=True
                )
                if result.stdout:
                    lines = result.stdout.strip().split("\n")
                    if len(lines) > 1:
                        model = lines[1].strip()
            elif self.os == "darwin":
                result = subprocess.run(
                    ["sysctl", "-n", "machdep.cpu.brand_string"],
                    capture_output=True,
                    text=True,
                )
                if result.stdout:
                    model = result.stdout.strip()
        except Exception:
            pass

        return {
            "model": model or "Unknown CPU",
            "cores": psutil.cpu_count(logical=False),
            "threads": psutil.cpu_count(logical=True),
            "arch": platform.machine(),
        }

    def _get_gpu_info(self) -> list[dict]:
        gpus = []
        try:
            if self.os == "linux":
                # Try lspci for Linux
                result = subprocess.run(
                    ["lspci", "-vmm"], capture_output=True, text=True
                )
                for block in result.stdout.split("\n\n"):
                    if "VGA" in block or "Display" in block or "3D" in block:
                        gpu = {}
                        for line in block.split("\n"):
                            if ":" in line:
                                k, v = line.split(":", 1)
                                gpu[k.strip().lower()] = v.strip()
                        # Normalize keys for the CLI
                        if "device" in gpu and "name" not in gpu:
                            gpu["name"] = gpu["device"]
                        if "vendor" in gpu and "vendor_name" not in gpu:
                            gpu["vendor_name"] = gpu["vendor"]
                        gpus.append(gpu)
            elif self.os == "windows":
                # Try wmic for Windows
                result = subprocess.run(
                    [
                        "wmic",
                        "path",
                        "win32_VideoController",
                        "get",
                        "name,VideoProcessor",
                        "/format:json",
                    ],
                    capture_output=True,
                    text=True,
                )
                if result.stdout:
                    gpus = json.loads(result.stdout)
            elif self.os == "darwin":
                # Try system_profiler for macOS
                result = subprocess.run(
                    ["system_profiler", "SPDisplaysDataType", "-json"],
                    capture_output=True,
                    text=True,
                )
                data = json.loads(result.stdout)
                gpus = data.get("SPDisplaysDataType", [])
        except Exception as e:
            logging.warning(f"Error detecting GPU: {e}")
        return gpus

    def _get_ffmpeg_caps(self) -> dict[str, list[str]]:
        caps = {"hwaccels": [], "encoders": []}
        try:
            result = subprocess.run(
                ["ffmpeg", "-hwaccels"], capture_output=True, text=True
            )
            lines = result.stdout.splitlines()
            for line in lines:
                hwaccel_line = line.strip()
                if (
                    hwaccel_line
                    and not hwaccel_line.startswith("Hardware")
                    and not hwaccel_line.startswith("-")
                ):
                    caps["hwaccels"].append(hwaccel_line)

            result = subprocess.run(
                ["ffmpeg", "-encoders"], capture_output=True, text=True
            )
            for line in result.stdout.splitlines():
                if line.startswith(" V"):
                    parts = line.split()
                    if len(parts) >= 2:
                        encoder = parts[1]
                        if encoder and not encoder.startswith("=") and len(encoder) > 2:
                            caps["encoders"].append(encoder)
        except Exception as e:
            logging.error(f"Error detecting FFmpeg capabilities: {e}")
        return caps

    def get_hardware_encoders(self) -> list[str]:
        """Get list of hardware encoders from FFmpeg capabilities."""
        hw_engines = [
            "vaapi",
            "nvenc",
            "qsv",
            "amf",
            "videotoolbox",
            "v4l2m2m",
            "omx",
            "opencl",
        ]
        hw_encoders = []
        for encoder in self.ffmpeg_caps.get("encoders", []):
            engine = encoder.split("_")[-1] if "_" in encoder else encoder
            if engine in hw_engines:
                hw_encoders.append(encoder)
        return hw_encoders

    def get_detected_vendors(self) -> list[str]:
        vendors = []
        for gpu in self.gpu_info:
            vendor_str = (gpu.get("vendor_name") or gpu.get("vendor") or "").lower()
            if "intel" in vendor_str:
                vendors.append("intel")
            if "nvidia" in vendor_str:
                vendors.append("nvidia")
            if "amd" in vendor_str or "ati" in vendor_str:
                vendors.append("amd")
        if self.os == "darwin":
            vendors.append("apple")
        return list(set(vendors))

    def has_detected_gpu(self) -> bool:
        """Check if any GPU is detected."""
        return len(self.gpu_info) > 0

    def get_vulkan_env_vars(self) -> dict:
        """Return environment variables required for Vulkan encoding based on GPU vendor."""
        vendors = self.get_detected_vendors()

        if "nvidia" in vendors:
            return {}

        env_vars = {}
        if "intel" in vendors:
            env_vars = {"ANV_VIDEO_ENCODE": "1", "ANV_VIDEO_DECODE": "1"}
        elif "amd" in vendors:
            env_vars = {"RADV_PERFTEST": "video_decode,video_encode"}

        return env_vars

    def validate_crf(self, crf: int, encoder: str) -> tuple[bool, str]:
        """Validate CRF value based on encoder type."""
        encoder_lower = encoder.lower()

        crf_ranges = {
            "x264": (0, 51, 23),
            "x265": (0, 51, 28),
            "vp9": (0, 63, 31),
            "av1": (0, 63, 30),
            "theora": (0, 63, 31),
            "nvenc": (0, 51, 23),
            "qsv": (0, 51, 28),
            "vaapi": (0, 52, 28),
            "vulkan": (0, 51, 28),
        }

        encoder_type = (
            encoder.replace("lib", "")
            .replace("hevc", "")
            .replace("h264", "")
            .strip("_")
        )

        for key, (min_val, max_val, default) in crf_ranges.items():
            if key in encoder_lower or key in encoder_type:
                if not (min_val <= crf <= max_val):
                    return (
                        False,
                        f"CRF {crf} not valid for '{encoder}'. Range: {min_val}-{max_val} (default: {default})",
                    )
                return True, ""

        if not (0 <= crf <= 51):
            return False, f"CRF {crf} not valid. Default range: 0-51"

        return True, ""

    def get_video_info(self, input_file: str) -> dict:
        """Get video dimensions and fps using ffprobe."""
        try:
            result = subprocess.run(
                [
                    "ffprobe",
                    "-v",
                    "quiet",
                    "-print_format",
                    "json",
                    "-show_streams",
                    "-select_streams",
                    "v:0",
                    input_file,
                ],
                capture_output=True,
                text=True,
            )
            if not result.stdout:
                return {"width": 0, "height": 0, "fps": 0}

            data = json.loads(result.stdout)
            streams = data.get("streams", [])
            if not streams:
                return {"width": 0, "height": 0, "fps": 0}

            stream = streams[0]

            fps_str = stream.get("r_frame_rate", "0/1")
            if "/" in fps_str:
                num, denom = map(int, fps_str.split("/"))
                fps = num / denom if denom else 0
            else:
                fps = float(fps_str)

            return {
                "width": int(stream.get("width", 0)),
                "height": int(stream.get("height", 0)),
                "fps": fps,
            }
        except Exception as e:
            logging.error(f"Error getting video info: {e}")
            return {"width": 0, "height": 0, "fps": 0}

    def validate_scale_vaapi(self) -> tuple[bool, str]:
        """Check if scale_vaapi filter is available in FFmpeg."""
        try:
            result = subprocess.run(
                ["ffmpeg", "-filters"], capture_output=True, text=True
            )
            if "scale_vaapi" in result.stdout:
                return True, ""
            return False, "scale_vaapi filter not available in FFmpeg"
        except Exception:
            return False, "Cannot check FFmpeg filters"

    def validate_upscale(self, scale: int | None) -> tuple[bool, str]:
        """Validate upscale factor."""
        if scale is None:
            return True, ""
        if scale not in [2, 4, 8]:
            return False, "Invalid upscale factor. Use 2, 4 or 8"
        return True, ""

    def validate_smooth_fps(self, fps: int | None) -> tuple[bool, str]:
        """Validate smooth-fps target."""
        if fps is None:
            return True, ""
        if fps <= 0 or fps > 240:
            return False, "Invalid smooth-fps. Must be between 1 and 240"
        return True, ""

    def validate_bitrate(self, bitrate: str | None) -> tuple[bool, str]:
        """Validate bitrate format."""
        if bitrate is None:
            return True, ""
        import re

        pattern = r"^\d+(\.\d+)?[kmg]?$"
        if not re.match(pattern, bitrate, re.IGNORECASE):
            return (
                False,
                "Invalid bitrate format. Use format like '5M', '2500k', or '1G'",
            )
        return True, ""

    def validate_preset(self, preset: str, encoder: str) -> tuple[bool, str]:
        """Validate preset is compatible with encoder."""
        valid_presets = ["veryfast", "fast", "medium", "slow"]

        if preset not in valid_presets:
            return (
                False,
                f"Invalid preset '{preset}'. Valid: {', '.join(valid_presets)}",
            )

        encoder_lower = encoder.lower()

        if "vaapi" in encoder_lower:
            return True, ""

        if "nvenc" in encoder_lower:
            return True, ""

        if "qsv" in encoder_lower:
            return True, ""

        if "vulkan" in encoder_lower:
            return True, ""

        if "vp9" in encoder_lower:
            return True, ""

        if "av1" in encoder_lower:
            return True, ""

        if (
            "libx264" in encoder_lower
            or "libx265" in encoder_lower
            or "x264" in encoder_lower
            or "x265" in encoder_lower
        ):
            return True, ""

        return True, ""

    def validate_video_codec(self, codec: str) -> tuple[bool, str]:
        """Validate video codec against available FFmpeg codecs."""
        available_video = self._get_video_codecs()
        codec_lower = codec.lower()
        if codec_lower in available_video or codec_lower == "copy":
            return True, ""
        return (
            False,
            f"Invalid video codec '{codec}'. Available: {', '.join(sorted(available_video))}, copy",
        )

    def _get_video_codecs(self) -> list[str]:
        """Get list of available video encoders from FFmpeg."""
        video_codecs = []
        try:
            result = subprocess.run(
                ["ffmpeg", "-encoders"], capture_output=True, text=True
            )
            for line in result.stdout.splitlines():
                if line.startswith(" V"):
                    match = re.search(r"\(codec\s+(\w+)\)", line)
                    if match:
                        codec = match.group(1)
                        if codec not in video_codecs:
                            video_codecs.append(codec)
        except Exception:
            pass
        return video_codecs

    def validate_audio_codec(self, codec: str) -> tuple[bool, str]:
        """Validate audio codec against available FFmpeg codecs."""
        available_audio = self._get_audio_codecs()
        codec_lower = codec.lower()
        if codec_lower in available_audio or codec_lower == "copy":
            return True, ""
        return (
            False,
            f"Invalid audio codec '{codec}'. Available: {', '.join(sorted(available_audio))}, copy",
        )

    def _get_audio_codecs(self) -> list[str]:
        """Get list of available audio codecs from FFmpeg."""
        audio_codecs = []
        try:
            result = subprocess.run(
                ["ffmpeg", "-encoders"], capture_output=True, text=True
            )
            for line in result.stdout.splitlines():
                if line.startswith(" A"):
                    match = re.search(r"\(codec\s+(\w+)\)", line)
                    if match:
                        codec = match.group(1)
                        if codec not in audio_codecs:
                            audio_codecs.append(codec)
                    else:
                        parts = line.split()
                        if len(parts) >= 2:
                            codec = parts[1]
                            if codec not in audio_codecs and codec not in [
                                "=",
                                "Audio",
                            ]:
                                audio_codecs.append(codec)
        except Exception:
            pass
        return audio_codecs

    def validate_encoder(self, encoder: str) -> tuple[bool, str]:
        """Validate encoder exists and is compatible with OS."""
        available = self.ffmpeg_caps.get("encoders", [])

        if encoder in available:
            os_restricted = {
                "nvenc": ["linux", "windows"],
                "amf": ["windows"],
                "qsv": ["linux", "windows"],
                "videotoolbox": ["darwin"],
            }
            engine = encoder.split("_")[-1] if "_" in encoder else encoder
            if engine in os_restricted and self.os not in os_restricted[engine]:
                os_names = {"linux": "Linux", "windows": "Windows", "darwin": "macOS"}
                return (
                    False,
                    f"'{encoder}' is only available on {', '.join(os_restricted[engine])} (current: {os_names.get(self.os, self.os)})",
                )
            return True, ""

        return (
            False,
            f"Encoder '{encoder}' not available. Available: {', '.join(available[:10])}...",
        )

    def get_best_encoder(self, codec: str = "h264") -> str:
        """Returns the best compatible hardware encoder for the detected GPU."""
        vendors = self.get_detected_vendors()

        # Vendor specific priorities
        vendor_tech = {
            "nvidia": ["nvenc"],
            "intel": ["qsv", "vaapi"],
            "amd": ["amf", "vaapi"],
            "apple": ["videotoolbox"],
        }

        allowed_engines = []
        for v in vendors:
            allowed_engines.extend(vendor_tech.get(v, []))

        # Add Vulkan as a general fallback if supported
        if "vulkan" in self.ffmpeg_caps["hwaccels"]:
            allowed_engines.append("vulkan")

        priority = {
            "h264": [
                "h264_nvenc",
                "h264_qsv",
                "h264_amf",
                "h264_videotoolbox",
                "h264_vaapi",
                "h264_v4l2m2m",
            ],
            "hevc": [
                "hevc_nvenc",
                "hevc_qsv",
                "hevc_amf",
                "hevc_videotoolbox",
                "hevc_vaapi",
                "hevc_v4l2m2m",
            ],
        }

        # Filter priorities by allowed engines AND ffmpeg capabilities
        for enc in priority.get(codec, []):
            engine = enc.split("_")[-1]
            if engine in allowed_engines and enc in self.ffmpeg_caps["encoders"]:
                return enc

        return "libx264" if codec == "h264" else "libx265"

    def get_hwaccel_flag(self) -> str | None:
        """Returns the best compatible hwaccel flag for decoding."""
        vendors = self.get_detected_vendors()

        vendor_hwaccels = {
            "nvidia": ["cuda", "nvdec"],
            "intel": ["qsv", "vaapi"],
            "amd": ["vaapi", "d3d11va"],
            "apple": ["videotoolbox"],
        }

        allowed_accels = []
        for v in vendors:
            allowed_accels.extend(vendor_hwaccels.get(v, []))

        allowed_accels.extend(["vulkan", "opencl", "drm"])

        os_restricted = {
            "d3d11va": ["windows"],
            "dxva2": ["windows"],
            "videotoolbox": ["darwin"],
            "vaapi": ["linux"],
            "cuda": ["linux", "windows"],
            "nvdec": ["linux", "windows"],
        }

        priority = [
            "cuda",
            "qsv",
            "vaapi",
            "videotoolbox",
            "d3d11va",
            "dxva2",
            "vulkan",
        ]
        for flag in priority:
            if (
                flag in allowed_accels
                and flag in self.ffmpeg_caps["hwaccels"]
                and (flag not in os_restricted or self.os in os_restricted[flag])
            ):
                return flag
        return None

    def validate_hwaccel(self, hwaccel: str) -> tuple[bool, str]:
        """Validate if a specific hwaccel is compatible with detected hardware and OS."""
        vendors = self.get_detected_vendors()
        available = self.ffmpeg_caps["hwaccels"]

        if hwaccel not in available:
            return (
                False,
                f"'{hwaccel}' not available in FFmpeg. Available: {', '.join(available)}",
            )

        os_restricted = {
            "d3d11va": ["windows"],
            "dxva2": ["windows"],
            "videotoolbox": ["darwin"],
            "vaapi": ["linux"],
            "cuda": ["linux", "windows"],
            "nvdec": ["linux", "windows"],
        }

        if hwaccel in os_restricted:
            if self.os not in os_restricted[hwaccel]:
                os_names = {"linux": "Linux", "windows": "Windows", "darwin": "macOS"}
                return (
                    False,
                    f"'{hwaccel}' is only available on {', '.join(os_names.get(o, o) for o in os_restricted[hwaccel])} (current: {os_names.get(self.os, self.os)})",
                )

        vendor_hwaccels = {
            "nvidia": ["cuda", "nvdec"],
            "intel": ["qsv", "vaapi"],
            "amd": ["vaapi", "d3d11va"],
            "apple": ["videotoolbox"],
        }

        allowed = []
        for v in vendors:
            allowed.extend(vendor_hwaccels.get(v, []))
        allowed.extend(["vulkan", "opencl", "drm"])

        if hwaccel in allowed:
            return True, ""

        vendor_names = {
            "nvidia": "NVIDIA GPU",
            "intel": "Intel GPU",
            "amd": "AMD GPU",
            "apple": "Apple Silicon",
        }
        detected = ", ".join(vendor_names.get(v, v) for v in vendors) or "None detected"
        return False, f"'{hwaccel}' not compatible with {detected}"

    def get_available_hwaccels(self) -> list[str]:
        """Return list of hwaccels compatible with current hardware and OS."""
        vendors = self.get_detected_vendors()
        vendor_hwaccels = {
            "nvidia": ["cuda", "nvdec"],
            "intel": ["qsv", "vaapi"],
            "amd": ["vaapi", "d3d11va"],
            "apple": ["videotoolbox"],
        }
        allowed = []
        for v in vendors:
            allowed.extend(vendor_hwaccels.get(v, []))
        allowed.extend(["vulkan", "opencl", "drm"])

        os_restricted = {
            "d3d11va": ["windows"],
            "dxva2": ["windows"],
            "videotoolbox": ["darwin"],
            "vaapi": ["linux"],
            "cuda": ["linux", "windows"],
            "nvdec": ["linux", "windows"],
        }

        available = []
        for accel in allowed:
            if accel not in os_restricted or self.os in os_restricted[accel]:
                if accel in self.ffmpeg_caps["hwaccels"]:
                    available.append(accel)
        return available
