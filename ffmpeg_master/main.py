import logging
import os
from typing import Annotated

import typer
from rich.console import Console
from rich.table import Table

from src.core.engine import FFmpegEngine
from src.core.hardware import HardwareManager

app = typer.Typer(help="FFmpeg Master CLI - Optimized cross-platform media toolkit")
console = Console()
logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")


@app.command()
def info():
    """Detect and display system hardware and FFmpeg capabilities."""
    hw = HardwareManager()

    # CPU
    cpu_table = Table(title="CPU Info")
    cpu_table.add_column("Property", style="cyan")
    cpu_table.add_column("Value", style="magenta")
    cpu_table.add_row("Model", hw.cpu_info["model"])
    cpu_table.add_row(
        "Cores/Threads", f"{hw.cpu_info['cores']}/{hw.cpu_info['threads']}"
    )
    cpu_table.add_row("Arch", hw.cpu_info["arch"])
    console.print(cpu_table)

    # GPU
    gpu_table = Table(title="GPU Info")
    gpu_table.add_column("Device", style="cyan")
    gpu_table.add_column("Vendor", style="magenta")
    for gpu in hw.gpu_info:
        name = (
            gpu.get("name") or gpu.get("product") or gpu.get("device") or "Unknown GPU"
        )
        vendor = gpu.get("vendor_name") or gpu.get("vendor") or "Unknown Vendor"
        gpu_table.add_row(name, vendor)
    console.print(gpu_table)

    # FFmpeg
    ffmpeg_table = Table(title="FFmpeg Capabilities")
    ffmpeg_table.add_column("Feature", style="cyan")
    ffmpeg_table.add_column("Detected", style="magenta")
    ffmpeg_table.add_row("hwaccels", ", ".join(hw.ffmpeg_caps["hwaccels"]))
    hw_encoders = hw.get_hardware_encoders()
    ffmpeg_table.add_row(
        "Hardware Encoders", ", ".join(hw_encoders) if hw_encoders else "None detected"
    )
    console.print(ffmpeg_table)


@app.command()
def encode(
    input_file: str = typer.Argument(..., help="Path to input media file"),
    output_file: str = typer.Argument(..., help="Path to output media file"),
    video_codec: str = typer.Option(
        "h264",
        "--codec",
        "-c",
        help="Video codec (e.g., h264, hevc, h264_vaapi, hevc_qsv, libx264)",
    ),
    audio_codec: str = typer.Option(
        "aac", "--acodec", "-a", help="Audio codec (aac, copy, etc)"
    ),
    hwaccel: Annotated[
        str | None,
        typer.Option(
            "--hwaccel",
            help="Hardware acceleration: vaapi, qsv, nvenc, cuda, videotoolbox. Omit for auto-detect",
        ),
    ] = None,
    crf: Annotated[
        int | None,
        typer.Option(
            "--crf",
            help="Constant Rate Factor for quality (lower = better). For VAAPI, value is converted to QP",
        ),
    ] = None,
    bitrate: Annotated[
        str | None,
        typer.Option(
            "--bitrate",
            "-b",
            help="Target bitrate (e.g., 5M, 2500k). Cannot be used with --crf",
        ),
    ] = None,
    preset: str = typer.Option(
        "veryfast",
        "--preset",
        "-p",
        help="Encoding preset: veryfast, fast, medium, slow",
    ),
    upscale: Annotated[
        int | None,
        typer.Option(
            "--upscale",
            help="Upscaling factor: 2, 4 or 8 (requires --hwaccel vaapi)",
        ),
    ] = None,
    smooth_fps: Annotated[
        int | None,
        typer.Option(
            "--smooth-fps",
            help="Target FPS for smooth playback (requires --hwaccel vaapi)",
        ),
    ] = None,
):
    """Encode media file with optimal settings."""
    if not os.path.exists(input_file):
        console.print("[red]Error:[/red] Input file not found: {input_file}")
        raise typer.Exit(1)

    output_dir = os.path.dirname(output_file)
    if output_dir and not os.path.exists(output_dir):
        console.print(
            f"[red]Error:[/red] Output directory does not exist: {output_dir}"
        )
        raise typer.Exit(1)

    if output_dir and not os.access(output_dir, os.W_OK):
        console.print(
            f"[red]Error:[/red] Output directory is not writable: {output_dir}"
        )
        raise typer.Exit(1)

    hw = HardwareManager()
    engine = FFmpegEngine(hw)

    valid, msg = hw.validate_audio_codec(audio_codec)
    if not valid:
        console.print(f"[red]Error:[/red] {msg}")
        raise typer.Exit(1)

    hwaccel_value = None
    if hwaccel is not None:
        if hwaccel == "auto":
            hwaccel_value = hw.get_hwaccel_flag()
            if hwaccel_value:
                if not hw.has_detected_gpu():
                    console.print(
                        "[yellow]Warning:[/yellow] No GPU detected. Falling back to software encoding."
                    )
                    hwaccel_value = None
                else:
                    valid, msg = hw.validate_hwaccel(hwaccel_value)
                    if not valid:
                        console.print(
                            f"[yellow]Warning:[/yellow] {msg}. Falling back to software encoding."
                        )
                        hwaccel_value = None
        else:
            valid, msg = hw.validate_hwaccel(hwaccel)
            if not valid:
                console.print(f"[red]Error:[/red] {msg}")
                available = hw.get_available_hwaccels()
                if available:
                    console.print(
                        f"[yellow]Available for your hardware:[/yellow] {', '.join(available)}"
                    )
                raise typer.Exit(1)
            hwaccel_value = hwaccel

    encoder = video_codec

    if "_" in encoder:
        if hwaccel_value:
            encoder_suffix = encoder.split("_")[-1]
            if encoder_suffix != hwaccel_value:
                console.print(
                    f"[red]Error:[/red] Codec '{encoder}' is not compatible with hwaccel '{hwaccel_value}'. "
                    f"Use codec ending with '_{hwaccel_value}' (e.g., h264_{hwaccel_value})"
                )
                raise typer.Exit(1)
    else:
        if hwaccel_value:
            hw_encoder = f"{encoder}_{hwaccel_value}"
            if hw_encoder in hw.ffmpeg_caps["encoders"]:
                encoder = hw_encoder
            else:
                lib_hw_encoder = f"lib{encoder}_{hwaccel_value}"
                if lib_hw_encoder in hw.ffmpeg_caps["encoders"]:
                    encoder = lib_hw_encoder
                else:
                    console.print(
                        f"[red]Error:[/red] No hardware encoder found for '{encoder}' with '{hwaccel_value}'. "
                        f"Try without --hwaccel or use a different codec."
                    )
                    raise typer.Exit(1)
        else:
            if encoder in ["h264", "hevc"]:
                encoder = "libx264" if encoder == "h264" else "libx265"
            else:
                lib_encoder = f"lib{encoder}"
                if lib_encoder in hw.ffmpeg_caps["encoders"]:
                    encoder = lib_encoder
                else:
                    valid, msg = hw.validate_encoder(encoder)
                    if not valid:
                        console.print(f"[red]Error:[/red] {msg}")
                        raise typer.Exit(1)

    valid, msg = hw.validate_encoder(encoder)
    if not valid:
        console.print(f"[red]Error:[/red] {msg}")
        raise typer.Exit(1)

    if crf is not None and bitrate is not None:
        console.print(
            "[red]Error:[/red] Cannot use both --crf and --bitrate at the same time"
        )
        raise typer.Exit(1)

    if crf is not None:
        valid, msg = hw.validate_crf(crf, encoder)
        if not valid:
            console.print(f"[red]Error:[/red] {msg}")
            raise typer.Exit(1)

    if bitrate is not None:
        valid, msg = hw.validate_bitrate(bitrate)
        if not valid:
            console.print(f"[red]Error:[/red] {msg}")
            raise typer.Exit(1)

    valid, msg = hw.validate_preset(preset, encoder)
    if not valid:
        console.print(f"[red]Error:[/red] {msg}")
        raise typer.Exit(1)

    video_info = {"width": 0, "height": 0, "fps": 0}
    if upscale is not None or smooth_fps is not None:
        if hwaccel_value != "vaapi":
            console.print(
                "[red]Error:[/red] --upscale and --smooth-fps require --hwaccel vaapi"
            )
            raise typer.Exit(1)

        valid, msg = hw.validate_upscale(upscale)
        if not valid:
            console.print(f"[red]Error:[/red] {msg}")
            raise typer.Exit(1)

        valid, msg = hw.validate_smooth_fps(smooth_fps)
        if not valid:
            console.print(f"[red]Error:[/red] {msg}")
            raise typer.Exit(1)

        valid, msg = hw.validate_scale_vaapi()
        if not valid:
            console.print(f"[red]Error:[/red] {msg}")
            raise typer.Exit(1)

        video_info = hw.get_video_info(input_file)
        if video_info["width"] == 0 or video_info["height"] == 0:
            console.print("[red]Error:[/red] Could not get video info from input file")
            raise typer.Exit(1)

        if upscale is not None:
            console.print(
                f"[yellow]Info:[/yellow] Upscaling from {video_info['width']}x{video_info['height']} "
                f"to {video_info['width'] * upscale}x{video_info['height'] * upscale}"
            )

        if smooth_fps is not None:
            console.print(
                f"[yellow]Info:[/yellow] Smooth FPS: {video_info['fps']:.2f} -> {smooth_fps} fps"
            )

    vulkan_env = {}
    if hwaccel_value == "vulkan":
        vendors = hw.get_detected_vendors()
        if "nvidia" in vendors:
            console.print(
                "[red]Error:[/red] Vulkan encoding is not supported on NVIDIA GPUs. "
                "Use --hwaccel nvenc instead."
            )
            raise typer.Exit(1)

        vulkan_env = hw.get_vulkan_env_vars()
        if not vulkan_env:
            console.print(
                "[red]Error:[/red] Vulkan requires Intel or AMD GPU with proper drivers."
            )
            raise typer.Exit(1)

        console.print(
            f"[yellow]Info:[/yellow] Using Vulkan with environment variables: {vulkan_env}"
        )

    cmd = engine.build_encode_cmd(
        input_file,
        output_file,
        encoder,
        hwaccel_value,
        audio_codec,
        crf,
        preset,
        upscale,
        smooth_fps,
        video_info,
        bitrate,
    )

    if crf is not None and "vaapi" in encoder.lower():
        console.print(
            f"[yellow]Info:[/yellow] Using QP: {crf} (CRF converted to QP for VAAPI)"
        )
    elif bitrate is not None:
        console.print(f"[yellow]Info:[/yellow] Using bitrate: {bitrate}")

    engine.run(cmd, vulkan_env if vulkan_env else None)


if __name__ == "__main__":
    app()
