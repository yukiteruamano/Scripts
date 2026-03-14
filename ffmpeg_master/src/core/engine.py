import logging
import os
import platform
import signal
import subprocess

from rich.console import Console
from rich.progress import (
    BarColumn,
    Progress,
    TextColumn,
    TimeElapsedColumn,
    TimeRemainingColumn,
)

from .hardware import HardwareManager
from .progress import ProgressHandler

console = Console()
shutdown_flag = False


def signal_handler(signum, frame):
    global shutdown_flag
    shutdown_flag = True
    console.print(
        "\n[yellow]Received shutdown signal. Finishing current task...[/yellow]"
    )


signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)


class FFmpegEngine:
    def __init__(self, hardware: HardwareManager):
        self.hardware = hardware
        self.os = platform.system().lower()

    def build_encode_cmd(
        self,
        input_file: str,
        output_file: str,
        encoder: str = "libx264",
        hwaccel: str | None = None,
        audio_codec: str = "aac",
        crf: int | None = None,
        preset: str = "veryfast",
        upscale: int | None = None,
        smooth_fps: int | None = None,
        video_info: dict | None = None,
        bitrate: str | None = None,
    ) -> list[str]:
        cmd = ["ffmpeg", "-y"]

        if hwaccel == "vulkan":
            cmd.extend(["-init_hw_device", "vulkan"])

        if hwaccel:
            cmd.extend(["-hwaccel", hwaccel])

        if hwaccel == "vaapi":
            cmd.extend(["-hwaccel_output_format", "vaapi"])

        cmd.extend(["-i", input_file])

        vaapi_filter = None
        if upscale is not None or smooth_fps is not None:
            if video_info and (video_info["width"] > 0 and video_info["height"] > 0):
                filter_parts = []

                if smooth_fps is not None:
                    filter_parts.append(f"fps={smooth_fps}")

                if upscale is not None:
                    out_w = video_info["width"] * upscale
                    out_h = video_info["height"] * upscale
                    filter_parts.append(
                        f"scale_vaapi=w={out_w}:h={out_h}:force_original_aspect_ratio=decrease:mode=hq"
                    )

                vaapi_filter = ",".join(filter_parts)

        if vaapi_filter:
            cmd.extend(["-vf", vaapi_filter])

        cmd.extend(["-c:v", encoder])

        encoder_lower = encoder.lower()
        use_qp = "vaapi" in encoder_lower

        if use_qp:
            quality_map = {"veryfast": 100, "fast": 80, "medium": 60, "slow": 40}
            quality = quality_map.get(preset, 60)
            cmd.extend(["-quality", str(quality)])
        elif "nvenc" in encoder_lower:
            preset_map = {"veryfast": "p1", "fast": "p2", "medium": "p3", "slow": "p4"}
            nvenc_preset = preset_map.get(preset, "p3")
            cmd.extend(["-preset", nvenc_preset])
        elif "qsv" in encoder_lower:
            cmd.extend(["-preset", preset])
        elif "vulkan" in encoder_lower:
            cmd.extend(["-preset", preset])
        elif (
            "vp9" in encoder_lower
            or "av1" in encoder_lower
            or "svtav1" in encoder_lower
            or "vpx" in encoder_lower
        ):
            quality_map = {"veryfast": 100, "fast": 80, "medium": 60, "slow": 40}
            quality = quality_map.get(preset, 60)
            cmd.extend(["-quality", str(quality)])
        else:
            cmd.extend(["-preset", preset])

        if crf is not None:
            if use_qp:
                cmd.extend(["-qp", str(crf)])
            else:
                cmd.extend(["-crf", str(crf)])

        if bitrate is not None:
            cmd.extend(["-b:v", bitrate])

        cmd.extend(["-c:a", audio_codec])

        cmd.append(output_file)
        return cmd

    def run(self, cmd: list[str], env_vars: dict[str, str] | None = None):
        global shutdown_flag
        shutdown_flag = False

        cmd = list(cmd)
        cmd = cmd[:-1] + ["-progress", "pipe:1", "-nostats"] + [cmd[-1]]

        console.print(f"[cyan]FFmpeg command:[/cyan] {' '.join(cmd)}")

        logging.info(f"Running command: {' '.join(cmd)}")

        env = os.environ.copy()
        if env_vars:
            env.update(env_vars)
            logging.info(f"With environment variables: {env_vars}")

        try:
            process = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                bufsize=1,
                env=env,
            )
        except FileNotFoundError:
            logging.error("FFmpeg executable not found. Please install FFmpeg.")
            return

        if process.stdout is None:
            logging.error("Failed to capture FFmpeg output.")
            return

        handler = ProgressHandler()

        with Progress(
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
            TimeElapsedColumn(),
            TimeRemainingColumn(),
            TextColumn("fps: {task.fields[fps]} speed: {task.fields[speed]}"),
        ) as progress:
            task = progress.add_task("Processing...", total=100, fps="0", speed="N/A")

            for line in process.stdout:
                if shutdown_flag:
                    if process.stdin:
                        process.stdin.write("q\n")
                        process.stdin.flush()
                    break

                handler.parse_line(line)
                progress.update(
                    task,
                    completed=handler.percentage,
                    fps=handler.fps,
                    speed=handler.speed,
                )

                if "Error" in line and "out_time_ms" not in line:
                    logging.error(line.strip())

        process.wait()
        if process.returncode != 0:
            logging.error(f"FFmpeg failed with return code {process.returncode}")
        else:
            logging.info("FFmpeg completed successfully.")
